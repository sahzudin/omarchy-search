#!/usr/bin/env python3
"""Install, change, or remove Web Search's managed Hyprland binding.

The widget's global shortcut lives in ~/.config/hypr/bindings.lua inside a
clearly marked managed block. This helper is the supported way to change it:
it backs the file up, refuses to steal a key that is already bound elsewhere,
writes the block, records the key in the widget's shell.json setting (so the
panel legend matches), and reloads Hyprland so the new binding is live.

Examples:
  python3 scripts/bindings.py set "SUPER + CTRL + K"
  python3 scripts/bindings.py install
  python3 scripts/bindings.py remove
  python3 scripts/bindings.py status
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import os
from pathlib import Path
import re
import secrets
import stat
import subprocess
import sys
import time


PLUGIN_ID = "io.github.sahzudin.omarchy-google-search"
DEFAULT_KEY = "SUPER + ALT + P"
DEFAULT_KEYCAP = "Super+Alt+P"
BEGIN = "-- BEGIN Web Search managed binding"
END = "-- END Web Search managed binding"
ACTION = f"omarchy-shell shell toggle {PLUGIN_ID} {{}}"
KEY_PATTERN = re.compile(r"^[A-Za-z0-9_-]+(?:\s*\+\s*[A-Za-z0-9_-]+)*$")
READ_SIZE = 1024 * 1024


@dataclass
class OpenRegularFile:
    """A regular file held open for the duration of one operation."""

    fd: int
    data: bytes
    metadata: os.stat_result

    def close(self) -> None:
        os.close(self.fd)


class AnchoredPath:
    """A path accessed only relative to a verified, open parent directory."""

    def __init__(self, path: Path):
        self.path = Path(os.path.abspath(os.fspath(path)))
        parts = self.path.parts
        if len(parts) < 2 or not self.path.name:
            raise RuntimeError(f"invalid bindings file path: {path}")

        directory_flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
        directory_fd = os.open(parts[0], directory_flags)
        try:
            for component in parts[1:-1]:
                try:
                    next_fd = os.open(component, directory_flags, dir_fd=directory_fd)
                except OSError as error:
                    raise RuntimeError(
                        f"unsafe parent chain for {self.path}: "
                        f"{component!r} is not a real directory"
                    ) from error
                os.close(directory_fd)
                directory_fd = next_fd
        except BaseException:
            os.close(directory_fd)
            raise

        self.directory_fd = directory_fd
        self.name = self.path.name

    def close(self) -> None:
        os.close(self.directory_fd)

    def __enter__(self) -> AnchoredPath:
        return self

    def __exit__(self, *_error: object) -> None:
        self.close()

    def open_regular(self, *, missing_ok: bool = False) -> OpenRegularFile | None:
        flags = os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW | os.O_CLOEXEC
        try:
            file_fd = os.open(self.name, flags, dir_fd=self.directory_fd)
        except FileNotFoundError:
            if missing_ok:
                return None
            raise RuntimeError(f"{self.path} does not exist") from None
        except OSError as error:
            raise RuntimeError(
                f"refusing to read {self.path}: path is a symlink or cannot be opened safely"
            ) from error

        try:
            before = os.fstat(file_fd)
            if not stat.S_ISREG(before.st_mode):
                raise RuntimeError(f"refusing to read {self.path}: not a regular file")

            chunks: list[bytes] = []
            while chunk := os.read(file_fd, READ_SIZE):
                chunks.append(chunk)

            after = os.fstat(file_fd)
            if _file_version(before) != _file_version(after):
                raise RuntimeError(f"refusing to use {self.path}: file changed while being read")
            return OpenRegularFile(file_fd, b"".join(chunks), after)
        except BaseException:
            os.close(file_fd)
            raise

    def assert_unchanged(self, opened: OpenRegularFile) -> None:
        held = os.fstat(opened.fd)
        if _file_version(held) != _file_version(opened.metadata):
            raise RuntimeError(f"refusing to replace {self.path}: file changed during update")

        try:
            current = os.stat(self.name, dir_fd=self.directory_fd, follow_symlinks=False)
        except FileNotFoundError:
            raise RuntimeError(f"refusing to replace {self.path}: file disappeared") from None
        if not stat.S_ISREG(current.st_mode):
            raise RuntimeError(f"refusing to replace {self.path}: no longer a regular file")
        if _file_version(current) != _file_version(opened.metadata):
            raise RuntimeError(f"refusing to replace {self.path}: file changed during update")

    def create_backup(self, opened: OpenRegularFile) -> Path:
        self.assert_unchanged(opened)
        stamp = time.strftime("%Y%m%d%H%M%S")
        for _attempt in range(128):
            backup_name = (
                f"{self.name}.bak.omarchy-search-{stamp}-"
                f"{time.time_ns() % 1_000_000_000:09d}-{secrets.token_hex(4)}"
            )
            try:
                backup_fd = self._create_file(backup_name, opened.data, 0o600)
            except FileExistsError:
                continue
            os.close(backup_fd)
            os.fsync(self.directory_fd)
            return self.path.with_name(backup_name)
        raise RuntimeError(f"could not create a unique backup beside {self.path}")

    def atomic_replace(self, opened: OpenRegularFile, data: bytes) -> None:
        temporary_name = f".{self.name}.tmp.omarchy-search-{secrets.token_hex(8)}"
        final_mode = stat.S_IMODE(opened.metadata.st_mode) & 0o777
        temporary_fd = self._create_file(temporary_name, data, final_mode)
        replaced = False
        try:
            self.assert_unchanged(opened)
            os.replace(
                temporary_name,
                self.name,
                src_dir_fd=self.directory_fd,
                dst_dir_fd=self.directory_fd,
            )
            replaced = True
            os.fsync(self.directory_fd)
        finally:
            os.close(temporary_fd)
            if not replaced:
                try:
                    os.unlink(temporary_name, dir_fd=self.directory_fd)
                except FileNotFoundError:
                    pass

    def _create_file(self, name: str, data: bytes, mode: int) -> int:
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC
        file_fd = os.open(name, flags, 0o600, dir_fd=self.directory_fd)
        try:
            view = memoryview(data)
            while view:
                written = os.write(file_fd, view)
                if written == 0:
                    raise OSError("short write while creating file")
                view = view[written:]
            os.fchmod(file_fd, mode)
            os.fsync(file_fd)
            return file_fd
        except BaseException:
            os.close(file_fd)
            try:
                os.unlink(name, dir_fd=self.directory_fd)
            except FileNotFoundError:
                pass
            raise


def _file_version(metadata: os.stat_result) -> tuple[int, int, int, int, int]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_size,
        metadata.st_mtime_ns,
        metadata.st_ctime_ns,
    )


def decode_text(opened: OpenRegularFile, path: Path) -> str:
    try:
        return opened.data.decode("utf-8")
    except UnicodeDecodeError as error:
        raise RuntimeError(f"{path} is not valid UTF-8") from error


def binding_file() -> Path:
    return Path.home() / ".config" / "hypr" / "bindings.lua"


def block_for(key: str) -> str:
    return f"{BEGIN}\no.bind(\"{key}\", \"Web search\", \"{ACTION}\")\n{END}\n"


def validate_key(key: str) -> str:
    key = " + ".join(part.strip().upper() for part in key.split("+"))
    if not KEY_PATTERN.fullmatch(key):
        raise RuntimeError(
            "invalid key combination; use names joined by '+', for example SUPER + CTRL + K"
        )
    return key


def installed_block(text: str) -> str | None:
    start = text.find(BEGIN)
    if start < 0:
        return None
    end = text.find(END, start)
    if end < 0:
        raise RuntimeError(f"found {BEGIN!r} without its closing marker")
    return text[start : end + len(END)]


def remove_block(text: str) -> tuple[str, bool]:
    start = text.find(BEGIN)
    if start < 0:
        return text, False
    end = text.find(END, start)
    if end < 0:
        raise RuntimeError(f"found {BEGIN!r} without its closing marker")
    end += len(END)
    if end < len(text) and text[end] == "\n":
        end += 1
    if start > 0 and text[start - 1] == "\n" and end == len(text):
        start -= 1
    return text[:start] + text[end:], True


def current_key(text: str) -> str | None:
    block = installed_block(text)
    if not block:
        return None
    # Pull the key out of o.bind("<KEY>", "Web search", ...).
    inner = block.split('o.bind("', 1)[1]
    key = inner.split('",', 1)[0]
    return key


def key_is_free(key: str) -> tuple[bool, str]:
    try:
        result = subprocess.run(
            ["omarchy", "menu", "keybindings", "--print"],
            check=False,
            capture_output=True,
            text=True,
            timeout=5,
        )
    except FileNotFoundError as error:
        raise RuntimeError("omarchy is required to check whether the key is free") from error
    except subprocess.TimeoutExpired as error:
        raise RuntimeError("timed out while checking existing Omarchy keybindings") from error

    if result.returncode != 0:
        detail = result.stderr.strip() or f"exit status {result.returncode}"
        raise RuntimeError(f"could not check existing Omarchy keybindings: {detail}")

    wanted = normalize_key(key)
    for line in result.stdout.splitlines():
        left, separator, right = line.partition("→")
        if separator and normalize_key(left) == wanted:
            return False, right.strip()
    return True, ""


def normalize_key(key: str) -> str:
    return " ".join(str(key).replace("+", " + ").split()).upper()


def persist_setting(key: str) -> None:
    try:
        subprocess.run(
            ["omarchy", "bar", "set", PLUGIN_ID, "openShortcut", key],
            check=True,
            capture_output=True,
            text=True,
            timeout=15,
        )
    except (FileNotFoundError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        print(f"bindings.py: could not update shell.json setting: {error}", file=sys.stderr)


def reload_hyprland() -> None:
    try:
        subprocess.run(["hyprctl", "reload"], check=False, capture_output=True, timeout=10)
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass


def cmd_set(path: Path, key: str) -> int:
    return update_binding(path, validate_key(key))


def update_binding(path: Path, requested_key: str | None) -> int:
    with AnchoredPath(path) as target:
        opened = target.open_regular()
        assert opened is not None
        try:
            text = decode_text(opened, target.path)
            key = requested_key or validate_key(current_key(text) or DEFAULT_KEY)
            new_block = block_for(key)

            if installed_block(text) == new_block:
                print(f"Keybinding already installed: {key}")
                return 0

            # Strip our previous block (if any) before checking/rewriting.
            text, owned = remove_block(text)

            if path == binding_file():
                free, description = key_is_free(key)
                if not free:
                    print(f"Skipping {key}; it is already bound to {description}.", file=sys.stderr)
                    print(f"Add this command to a key of your choice: {ACTION}", file=sys.stderr)
                    return 0

            backup_path = target.create_backup(opened)
            if owned:
                print(f"Replacing previous Web Search keybinding (backup: {backup_path})")
            else:
                print(f"Installing {key} keybinding (backup: {backup_path})")

            if not text or text.endswith("\n\n"):
                separator = ""
            elif text.endswith("\n"):
                separator = "\n"
            else:
                separator = "\n\n"
            updated = (text + separator + new_block).encode("utf-8")
            target.atomic_replace(opened, updated)
        finally:
            opened.close()

    # Only touch the live config (setting + reload) when this is the real file;
    # --file is for tests and must stay side-effect free.
    if path == binding_file():
        persist_setting(key)
        reload_hyprland()
    else:
        print("(dry run: live shell.json setting and Hyprland not touched)")
    print(f"Active keybinding: {key}")
    return 0


def cmd_install(path: Path) -> int:
    return update_binding(path, None)


def cmd_remove(path: Path) -> int:
    with AnchoredPath(path) as target:
        opened = target.open_regular(missing_ok=True)
        if opened is None:
            print("Hyprland bindings file is absent; nothing to remove.")
            return 0
        try:
            text = decode_text(opened, target.path)
            updated, changed = remove_block(text)
            if not changed:
                print("No managed Web Search keybinding found.")
                return 0
            backup_path = target.create_backup(opened)
            target.atomic_replace(opened, updated.encode("utf-8"))
        finally:
            opened.close()

    if path == binding_file():
        reload_hyprland()
    print(f"Removed Web Search keybinding (backup: {backup_path}).")
    return 0


def cmd_status(path: Path) -> int:
    with AnchoredPath(path) as target:
        opened = target.open_regular(missing_ok=True)
        if opened is None:
            text = ""
        else:
            try:
                text = decode_text(opened, target.path)
            finally:
                opened.close()
    key = current_key(text)
    if key:
        print(f"Managed Web Search keybinding: {key}")
    else:
        print("No managed Web Search keybinding installed.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("action", choices=("set", "install", "remove", "status"))
    parser.add_argument("key", nargs="?", default=None, help="key combination, e.g. \"SUPER + CTRL + K\"")
    parser.add_argument("--key", dest="key_opt", default=None, help="same as the positional KEY")
    parser.add_argument("--file", type=Path, default=binding_file(), help="bindings.lua path (for tests)")
    arguments = parser.parse_args()

    key = arguments.key_opt or arguments.key
    try:
        if arguments.action == "set":
            if not key:
                raise RuntimeError("set requires a key, e.g. set \"SUPER + CTRL + K\"")
            return cmd_set(arguments.file, key)
        if arguments.action == "install":
            return cmd_install(arguments.file)
        if arguments.action == "remove":
            return cmd_remove(arguments.file)
        return cmd_status(arguments.file)
    except (OSError, RuntimeError) as error:
        print(f"bindings.py: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
