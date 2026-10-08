#!/bin/sh
# Run install.sh from this checkout against throwaway home directories.
#
# usage: sh tests/test-install.sh
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
want='{"type":"command","command":"~/.claude/statusline.sh"}'
fails=0
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

check() {  # check <description> <command...>
  desc=$1; shift
  if "$@"; then printf 'ok   %s\n' "$desc"; else printf 'FAIL %s\n' "$desc"; fails=$((fails + 1)); fi
}
run() { HOME=$1 sh "$root/install.sh" >"$1/out" 2>&1; }
status_line() { jq -c .statusLine "$1/.claude/settings.json"; }

# Fresh home: no ~/.claude at all.
h=$work/fresh; mkdir -p "$h"
check "fresh install succeeds" run "$h"
check "fresh: script installed and executable" test -x "$h/.claude/statusline.sh"
check "fresh: script matches the checkout" cmp -s "$root/statusline.sh" "$h/.claude/statusline.sh"
check "fresh: statusLine set" test "$(status_line "$h")" = "$want"

# Existing settings: other keys survive, the old statusLine is reported.
h=$work/existing; mkdir -p "$h/.claude"
printf '{"model":"opus","permissions":{"allow":["Bash(ls)"]},"statusLine":{"type":"command","command":"other.sh"}}\n' \
  > "$h/.claude/settings.json"
check "existing install succeeds" run "$h"
check "existing: other keys kept" \
  test "$(jq -c 'del(.statusLine)' "$h/.claude/settings.json")" = '{"model":"opus","permissions":{"allow":["Bash(ls)"]}}'
check "existing: statusLine replaced" test "$(status_line "$h")" = "$want"
check "existing: replacement reported" grep -q 'Replaced the previous statusLine' "$h/out"

# Re-running changes nothing and reports no replacement.
cp "$h/.claude/settings.json" "$work/before.json"
check "re-run succeeds" run "$h"
check "re-run: settings unchanged" cmp -s "$work/before.json" "$h/.claude/settings.json"
check "re-run: no replacement reported" sh -c "! grep -q Replaced '$h/out'"

# Invalid JSON is refused and left as it was.
h=$work/invalid; mkdir -p "$h/.claude"
printf '{"model": \n' > "$h/.claude/settings.json"
cp "$h/.claude/settings.json" "$work/invalid.json"
check "invalid JSON: install fails" sh -c "! HOME='$h' sh '$root/install.sh' >/dev/null 2>&1"
check "invalid JSON: file untouched" cmp -s "$work/invalid.json" "$h/.claude/settings.json"

# A symlinked settings.json stays a symlink, and its target gets the change.
h=$work/symlink; mkdir -p "$h/.claude" "$h/dotfiles"
printf '{"model":"opus"}\n' > "$h/dotfiles/settings.json"
ln -s "$h/dotfiles/settings.json" "$h/.claude/settings.json"
check "symlink install succeeds" run "$h"
check "symlink: still a symlink" test -L "$h/.claude/settings.json"
check "symlink: target updated" test "$(jq -c .statusLine "$h/dotfiles/settings.json")" = "$want"

[ "$fails" -eq 0 ] && echo "all install checks passed" || { echo "$fails install checks failed"; exit 1; }
