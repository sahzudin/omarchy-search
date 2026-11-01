#!/bin/bash

# Remove Web Search's managed Hyprland binding before uninstalling the plugin.
# Omarchy's `plugin remove` only unlinks the plugin folder and wires the bar;
# it cannot touch ~/.config/hypr/bindings.lua, so this step is manual.

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"

if [[ -f "$here/scripts/bindings.py" ]]; then
  python3 "$here/scripts/bindings.py" remove
else
  echo "uninstall.sh: scripts/bindings.py not found" >&2
  exit 1
fi

echo "Done. Now remove the plugin with:"
echo "  omarchy plugin remove io.github.sahzudin.omarchy-google-search"
