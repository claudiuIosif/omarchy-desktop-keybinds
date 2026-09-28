#!/usr/bin/env bash
# Lints the plugin's QML with qmllint, plus one check qmllint does not make.
#
# The Omarchy shell modules resolve as `qs.*` URIs even though they live in a
# plain `Commons`/`Ui` directory layout qmllint cannot map directly, so this
# builds a temporary `qs/` tree and passes it via -I. Real copies rather than
# symlinks, matching what the other community plugins do.
#
# Surviving warnings have to be enumerated, not tolerated wholesale. qmllint exits
# 0 on warnings, so a "passing" run says nothing on its own, and the bugs found
# while building this panel were invisible to it: a signal handler reading
# `exitCode` by bare name parses fine, and a call to a nonexistent
# `root.noticeTimer` was only caught by accident. The allowlist below is
# deliberately short, so anything genuinely new stops the build:
#
#   uncreatable-type        PanelWindow is marked uncreatable in the shipped
#                           Quickshell qmltypes
#   missing-property        only for members reached through Style.*, which is
#                           QtObject-typed and cannot be introspected
#   signal-handler-...      QProcess::ExitStatus is missing from Quickshell.Io's
#   parameters              qmltypes, so the exited signature is incomplete
#   unqualified             follows from the above, plus the inline component
#                           that cannot be Bound
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHIM="$(mktemp -d)"
trap 'rm -rf "$SHIM"' EXIT

mkdir -p "$SHIM/qs"
cp -rL /usr/share/omarchy/shell/Commons "$SHIM/qs/Commons"
cp -rL /usr/share/omarchy/shell/Ui "$SHIM/qs/Ui"

REPORT="$(mktemp)"
/usr/lib/qt6/bin/qmllint -I "$SHIM" -I /usr/lib/qt6/qml "$DIR/KeybindsPanel.qml" >"$REPORT" 2>&1 || true

unexpected="$(grep '^Warning:' "$REPORT" \
  | grep -v '\[uncreatable-type\]$' \
  | grep -v '\[unqualified\]$' \
  | grep -v '\[signal-handler-parameters\]$' \
  | grep -v 'Member ".*" not found on type "QObject"' || true)"

if [[ -n "$unexpected" ]]; then
  echo "unexpected qmllint warnings:" >&2
  echo "$unexpected" >&2
  echo >&2
  cat "$REPORT" >&2
  exit 1
fi

echo "qmllint: OK ($(grep -c '^Warning:' "$REPORT" || true) known-cosmetic warnings)"

# Signal parameters reached by bare name inside an on<Signal> handler. qmllint
# does not flag these, and on current Qt the name is not injected at all, so the
# branch is dead and whatever it guarded silently never runs. That is how the
# Edit button came to do nothing.
offenders="$(grep -nE '^[[:space:]]*on[A-Z][A-Za-z0-9]*:.*\b(exitCode|exitStatus)\b' "$DIR"/*.qml \
  | grep -v '=>' || true)"

if [[ -n "$offenders" ]]; then
  echo "signal parameters read without being declared:" >&2
  echo "$offenders" >&2
  echo "use a formal parameter list: onExited: (exitCode) => ..." >&2
  exit 1
fi

echo "signal parameters: OK"
