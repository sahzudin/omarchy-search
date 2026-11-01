# Omarchy Web Search

A native Omarchy Shell bar plugin for quick web search. Click the icon, type
a query, and press **Enter** — the results open in your default browser.

## Features

- Clickable bar icon (a magnifying glass) that opens a compact search panel.
- The panel header mirrors the selected engine — its icon, "Searching with
  Google" / "Asking Claude", and the shortcut that reselects it.
- Text field pre-fills with your last query and auto-selects it for quick
  retries. Its placeholder follows the engine ("Search GitHub…", "Ask
  ChatGPT…"), and the trailing ↵ runs the search on click.
- Ten built-in search engines as a labelled five-across grid, each tile
  showing its icon, name, and shortcut number: Google, ChatGPT, Claude, Bing,
  DuckDuckGo, GitHub, Wikipedia, YouTube, Reddit, and Stack Overflow. ChatGPT
  and Claude pre-fill a prompt in chatgpt.com / claude.ai.
- `Ctrl+1`–`Ctrl+9` picks engines by tile number, and `Ctrl+0` picks Stack
  Overflow, so every engine is reachable without leaving the keyboard
  (Google → `Ctrl+1`, ChatGPT → `Ctrl+2`, Claude → `Ctrl+3`, …).
- The default engine is configurable per-widget; clicking a tile or pressing
  its shortcut changes it for the current search only.
- An optional global Hyprland shortcut opens or closes the panel from anywhere
  — **Super+Alt+P** by default when installed with `scripts/bindings.py` (see
  below) — and is listed in the panel's keycap legend along with Enter,
  Ctrl+0–9, and Esc.
- `Enter` opens the results in your default browser (`omarchy launch browser`),
  which reuses an already-running browser window and adds a new tab.
- `Esc` closes the panel without running a search.
- Supports shell IPC (`open`, `close`, `toggle`, `show`, `hide`).

No privileges are required. The query is URL-encoded before being passed to the
browser, and commands are passed as argument arrays (no shell command strings
are evaluated).

## Requirements

- Omarchy with the Quickshell bar (`omarchy.bar`)
- A default web browser set via `xdg-settings` (checked by `omarchy launch
  browser`)
- Python 3, only when using the optional global-shortcut helper

## Install

```bash
omarchy plugin add https://github.com/zmnatz/omarchy-search.git --enable
```

The plugin does not change your Hyprland configuration during installation.
To opt into the optional **Super+Alt+P** global shortcut, run:

```bash
python3 ~/.config/omarchy/plugins/zmnatza.web-search/scripts/bindings.py install
```

The helper first verifies that the key is free, safely backs up
`~/.config/hypr/bindings.lua`, adds one clearly marked binding block, and
reloads Hyprland. It refuses symlinks and non-regular files anywhere in that
path and atomically replaces the configuration only after the backup and new
contents have been synced. The plugin itself works normally without this
shortcut.

For local development, link the checkout into the user plugin directory and
enable it:

```bash
ln -s ~/Projects/omarchy-search \
      ~/.config/omarchy/plugins/zmnatza.web-search
omarchy plugin enable zmnatza.web-search left
```

Saved changes under `~/.config/omarchy/plugins/` reload automatically. If a
change does not apply, force a reload:

```bash
omarchy-shell shell rescanPlugins
```

## Usage

- **Left-click** the magnifying glass — open the search panel and focus the
  query field.
- Type a query and press **Enter** — open the results for the selected engine
  in your browser.
- Press **Ctrl+1**…**Ctrl+9** (or click a tile) to pick the search engine, then
  press **Enter**.
- Press **Esc** — close the panel without searching.

## Configuration

Per-widget settings go in the widget's entry in `~/.config/omarchy/shell.json`
under `bar.layout.<section>`:

```jsonc
{
  "id": "zmnatza.web-search",
  "defaultEngine": "google",     // id of the engine preselected when the panel opens
  "openShortcut": "SUPER + ALT + P", // global panel shortcut (Hyprland combo)
  "icon": "󰍋"                    // any Nerd Font glyph
}
```

Engine ids: `google`, `chatgpt`, `claude`, `bing`, `duckduckgo`, `github`,
`wikipedia`, `youtube`, `reddit`, `stackoverflow`.

### Add, replace, or hide engines

Two optional settings customize the engine list without editing the plugin:

```jsonc
{
  "id": "zmnatza.web-search",
  "extraEngines": [
    {
      "id": "perplexity",                              // required, unique
      "label": "Perplexity",                           // required
      "prefix": "https://www.perplexity.ai/search?q=", // required, the query is appended
      "verb": "Ask",                                   // optional, "Search" (default) or "Ask"
      "icon": "\uf002",                                // optional, Nerd Font glyph or code point
      "after": "claude"                                // optional, insert after this engine id
    }
  ],
  "hiddenEngines": ["stackoverflow"]                   // engine ids to remove
}
```

An extra engine whose `id` matches a built-in replaces it. Engines are numbered
in list order, so keep the list to ten or fewer to give each a `Ctrl+0`–`Ctrl+9`
shortcut. Without these settings nothing changes.

The file hot-reloads on save.

### Change the global shortcut

The panel's open/close shortcut is a managed Hyprland binding in
`~/.config/hypr/bindings.lua` (a marked block between `-- BEGIN Web Search
managed binding` and the matching `-- END`). Change it safely with the helper;
it backs up the file, refuses to steal a key bound elsewhere, updates the
widget's `openShortcut` setting, and reloads Hyprland:

```bash
python3 scripts/bindings.py set "SUPER + CTRL + K"   # bind a new key
python3 scripts/bindings.py remove                    # drop the binding
python3 scripts/bindings.py status                    # show the active key
```

`install` re-binds the last-used key (or `SUPER + ALT + P`). Because the key
must be free, Hyprland may restart the shell or ask you to log in again if a
binding changes. To set it manually instead, remove the managed block and add
`o.bind("<KEY>", "Web search", "omarchy-shell shell toggle zmnatza.web-search {}")`.

## Remove

`omarchy plugin remove` only unlinks the plugin folder and rewires the bar;
it does **not** touch the Hyprland keybinding written to
`~/.config/hypr/bindings.lua`, so drop that first:

```bash
./uninstall.sh            # removes the managed binding block (see scripts/bindings.py)
omarchy plugin disable zmnatza.web-search
omarchy plugin remove zmnatza.web-search
```

The widget's per-widget settings (including `openShortcut`) live in the widget
entry in `shell.json` and are removed together with the entry.

## License

MIT — see `LICENSE`.
