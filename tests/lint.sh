#!/usr/bin/env bash
# Lints the plugin's QML with qmllint.
#
# The Omarchy shell modules resolve as `qs.*` URIs even though they live in a
# plain `Commons`/`Ui` directory layout qmllint cannot map directly, so this
# builds a temporary `qs/` tree and passes it via -I. Real copies rather than
# symlinks, matching what the other community plugins do.
#
# Surviving warnings are the same cosmetic classes the Omarchy shell's own
# plugins emit against the shipped Quickshell qmltypes: PanelWindow is marked
# uncreatable, Style.spacing/Style.font go through a QtObject-typed property
# qmllint cannot introspect, and QProcess::ExitStatus is not declared in the
# Quickshell.Io qmltypes. This script fails only on qmllint's exit status.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHIM="$(mktemp -d)"
trap 'rm -rf "$SHIM"' EXIT

mkdir -p "$SHIM/qs"
cp -rL /usr/share/omarchy/shell/Commons "$SHIM/qs/Commons"
cp -rL /usr/share/omarchy/shell/Ui "$SHIM/qs/Ui"

/usr/lib/qt6/bin/qmllint -I "$SHIM" -I /usr/lib/qt6/qml "$DIR/KeybindsPanel.qml"

echo "qmllint: OK"
