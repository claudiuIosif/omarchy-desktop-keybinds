#!/usr/bin/env bash
set -euo pipefail

SRC="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ID="io.github.claudiuiosif.desktop-keybinds"
DEST="$HOME/.config/omarchy/plugins/$ID"

[[ -f "$SRC/manifest.json" ]] || { echo "no manifest.json in $SRC" >&2; exit 1; }
actual_id=$(jq -r '.id' "$SRC/manifest.json")
[[ "$actual_id" == "$ID" ]] || { echo "manifest id is '$actual_id', expected '$ID'" >&2; exit 1; }

mkdir -p "$DEST"
rsync -a \
  --exclude '.git/' \
  --exclude 'shortcuts.jsonc' \
  --exclude 'shortcuts.json' \
  --exclude 'node_modules/' \
  --exclude '*.bak' \
  --exclude '*.orig' \
  --exclude '*.backup' \
  --exclude '*.swp' \
  --exclude '*.swo' \
  --exclude '.DS_Store' \
  --exclude 'README.md' \
  --exclude '.user-*' \
  --exclude '.local-*' \
  "$SRC/" "$DEST/"

omarchy plugin validate "$DEST"
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
echo "synced to $DEST"