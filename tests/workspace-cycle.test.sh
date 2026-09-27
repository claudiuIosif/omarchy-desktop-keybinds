#!/usr/bin/env bash
#
# Checks the workspace-cycle script's decision table without moving the user's
# actual workspaces: a stub `hyprctl` stands in, and the dispatch at the end of
# the script is swapped for an echo so a run only ever prints its choice.
#
#   ./tests/workspace-cycle.test.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin"
sed 's|^hyprctl dispatch .*|echo "DISPATCH $target"|' \
  "$ROOT/bin/desktop-keybinds-workspace-cycle" > "$WORK/script"
chmod +x "$WORK/script"

cat > "$WORK/bin/hyprctl" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  workspaces)     printf '%s' "$WS" ;;
  activeworkspace) printf '{"id": %s}' "$ACTIVE" ;;
  dispatch)       exit 0 ;;
esac
STUB
chmod +x "$WORK/bin/hyprctl"

failed=0
total=0

# check <description> <active workspace> <workspaces json> <expected target>
check() {
  local desc="$1" active="$2" workspaces="$3" expect="$4" got
  total=$((total + 1))
  got=$(PATH="$WORK/bin:$PATH" ACTIVE="$active" WS="$workspaces" "$WORK/script" 2>&1)
  if [[ "$got" == "DISPATCH $expect" ]]; then
    printf 'ok   %-44s -> %s\n' "$desc" "$expect"
  else
    printf 'FAIL %-44s -> got "%s", want "%s"\n' "$desc" "$got" "$expect"
    failed=1
  fi
}

# Workspaces 2, 3 and 5 hold windows; 1 and 4 are clean.
SPARSE='[{"id":1,"windows":0},{"id":2,"windows":3},{"id":3,"windows":1},{"id":4,"windows":0},{"id":5,"windows":2}]'

check "on 2, next occupied is 3"            2 "$SPARSE" 3
check "on 3, next occupied is 5"            3 "$SPARSE" 5
check "on 5, past the last occupied -> 1"   5 "$SPARSE" 1
check "on clean 1, back to first occupied"  1 "$SPARSE" 2
check "on clean 4, back to first occupied"  4 "$SPARSE" 2

# The whole point of the script: an empty screen is never a dead end.
check "nothing occupied anywhere"           1 '[{"id":1,"windows":0}]' 1
check "nothing occupied, sat on 7"          7 '[{"id":7,"windows":0}]' 1
check "empty workspace list"                1 '[]' 1
check "no workspaces reported at all"       3 '[]' 1

# Every workspace occupied means the clean one is the next id along.
check "1..3 all occupied, on 3 -> 4"        3 '[{"id":1,"windows":1},{"id":2,"windows":1},{"id":3,"windows":1}]' 4
check "1..3 all occupied, on 1 -> 2"        1 '[{"id":1,"windows":1},{"id":2,"windows":1},{"id":3,"windows":1}]' 2
check "1..3 all occupied, on 4 -> 1"        4 '[{"id":1,"windows":1},{"id":2,"windows":1},{"id":3,"windows":1}]' 1

printf '\n%s\n' "$([[ $failed -eq 0 ]] && echo "all $total checks passed" || echo "$total checks, some failed")"
exit $failed
