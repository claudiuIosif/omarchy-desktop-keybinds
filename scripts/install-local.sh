#!/usr/bin/env bash
# Syncs the working repo into the installed plugin folder, then asks the shell
# to reload it. The plugin validator rejects symlinks inside a plugin folder, so
# this copies for real.
set -euo pipefail

SRC="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ID="io.github.claudiuiosif.desktop-keybinds"
DEST="$HOME/.config/omarchy/plugins/$ID"

[[ -f "$SRC/manifest.json" ]] || { echo "no manifest.json in $SRC" >&2; exit 1; }
actual_id=$(jq -r '.id' "$SRC/manifest.json")
[[ "$actual_id" == "$ID" ]] || { echo "manifest id is '$actual_id', expected '$ID'" >&2; exit 1; }

mkdir -p "$DEST"
# --delete keeps a renamed file from lingering; shortcuts.jsonc is gitignored
# and is never in the source tree, so it is preserved by the exclusion.
rsync -a --delete \
  --exclude '.git/' \
  --exclude 'shortcuts.jsonc' \
  --exclude 'shortcuts.json' \
  --exclude 'node_modules/' \
  "$SRC/" "$DEST/"

omarchy plugin validate "$DEST"
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
echo "synced to $DEST"
