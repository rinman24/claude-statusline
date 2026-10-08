#!/bin/sh
# Install the Claude Code status line: copy statusline.sh to ~/.claude and
# point statusLine in ~/.claude/settings.json at it. Safe to re-run.
#
#   curl -fsSL https://raw.githubusercontent.com/rinman24/claude-statusline/main/install.sh | sh
#   ./install.sh                     # from a clone: installs that checkout's script
#
# CLAUDE_STATUSLINE_REF picks the git ref to download (default: main).
# Claude Code rewrites settings.json itself, so only statusLine is touched;
# every other key passes through unchanged.
set -eu

repo=rinman24/claude-statusline
ref=${CLAUDE_STATUSLINE_REF:-main}
dir=$HOME/.claude
script=$dir/statusline.sh
settings=$dir/settings.json

die() { printf 'install.sh: %s\n' "$*" >&2; exit 1; }

[ -x /bin/bash ] || die "/bin/bash is required"
command -v jq >/dev/null 2>&1 || die "jq is required (brew install jq, apt-get install jq, apk add jq)"
command -v git >/dev/null 2>&1 || printf 'install.sh: git not found; the branch segment will be empty\n' >&2

mkdir -p "$dir"
tmp=$(mktemp "$dir/.statusline.XXXXXX")
trap 'rm -f "$tmp"' EXIT

# A clone installs its own working copy; a piped install downloads the ref.
here=$(dirname "$0")
if [ "$(basename "$0")" = install.sh ] && [ -f "$here/statusline.sh" ]; then
  cp "$here/statusline.sh" "$tmp"
  from=$here/statusline.sh
else
  url=https://raw.githubusercontent.com/$repo/$ref/statusline.sh
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$tmp"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$tmp" "$url"
  else
    die "curl or wget is required to download $url"
  fi
  from=$url
fi
chmod 755 "$tmp"
mv "$tmp" "$script"

# Merge statusLine into settings.json, creating it if absent. A file jq can't
# parse is left alone rather than overwritten. Writing through the existing
# file keeps its permissions and any symlink.
[ -s "$settings" ] || printf '{}\n' > "$settings"
prev=$(jq -c '.statusLine // empty' "$settings") || die "$settings is not valid JSON; fix it and re-run"
want='{"type":"command","command":"~/.claude/statusline.sh"}'
tmp=$(mktemp "$dir/.settings.XXXXXX")
jq --argjson s "$want" '.statusLine = $s' "$settings" > "$tmp"
cat "$tmp" > "$settings"
rm -f "$tmp"

printf 'Installed %s\n     from %s\n' "$script" "$from"
if [ -n "$prev" ] && [ "$prev" != "$want" ]; then
  printf 'Replaced the previous statusLine: %s\n' "$prev"
fi
printf 'Pick a layout with: echo medium > ~/.claude/statusline-size   (default: small)\n'
