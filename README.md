# claude-statusline

A Claude Code [status line](https://code.claude.com/docs/en/statusline) in
Catppuccin Mocha: model, effort, thinking, output style, cost, folder, branch
and worktree, with gradient bars for context tokens and the 5-hour and 7-day
usage limits. One bash script, no daemon.

```
small (default, 2 lines)
🤖 model · effort 💡 ┃ 🎨 style ┃ 💸 $cost ┃ 📂 folder ┃ 🌿 branch ┃ 🌳 worktree
🪣 [bar] used/size ┃ 5H [bar] % (left) ┃ 7D [bar] % (day)

medium (4 lines)
🤖 model · effort 💡 ┃ 🎨 style ┃ 💸 $cost
📂 folder ┃ 🌿 branch ┃ 🌳 worktree
🪣 Context [bar] used/size
🚀 Usage 5H [bar] % (left) ┃ 7D [bar] % (day)
```

## Install

Requirements: `/bin/bash` (3.2 or later), `jq`, and `git` for the branch
segment. Works on macOS and Linux, including slim containers.

```bash
curl -fsSL https://raw.githubusercontent.com/rinman24/claude-statusline/main/install.sh | sh
```

`install.sh` copies `statusline.sh` to `~/.claude/statusline.sh` and sets only
the `statusLine` key in `~/.claude/settings.json`; every other key is left as
Claude Code wrote it. It's safe to re-run, refuses to touch a `settings.json`
it can't parse, and says so if it replaced a different status line. Set
`CLAUDE_STATUSLINE_REF` to install a tag or branch other than `main`. From a
clone, `./install.sh` installs that checkout's script.

### With chezmoi

Pull the script as an external pinned to a release, and keep `statusLine` set
with a [modify script](https://www.chezmoi.io/user-guide/manage-different-types-of-file/#manage-part-but-not-all-of-a-file),
since Claude Code rewrites `settings.json` itself:

```toml
# .chezmoiexternal.toml
[".claude/statusline.sh"]
    type = "file"
    url = "https://raw.githubusercontent.com/rinman24/claude-statusline/v1.0.0/statusline.sh"
    executable = true
```

```sh
#!/bin/sh
# private_dot_claude/modify_settings.json
input=$(cat)
[ -n "$input" ] || input='{}'
printf '%s\n' "$input" | jq '.statusLine = {"type": "command", "command": "~/.claude/statusline.sh"}'
```

## Configure

Pick the layout per machine with a state file, or per session with an
environment variable, which wins. State files are re-read on every refresh,
so no restart is needed.

```bash
echo medium > ~/.claude/statusline-size        # or small; rm for the default
CLAUDE_STATUSLINE_SIZE=small claude            # this session only
```

Bars are whole `█` cells, each colored by its position along a gradient, on a
`░` track. Some fonts draw `░` as dots, others as a flat block; for dots in any
font, switch the track to braille `⣿`:

```bash
echo dots > ~/.claude/statusline-track         # rm for ░
CLAUDE_STATUSLINE_TRACK=dots claude            # this session only
```

## How it reads

The context bar spans 0–200k tokens whatever the window size, with its
gradient anchored at absolute thresholds: green, yellow at 95k, red from 120k,
and 🚨 in place of 🪣 at 200k. 5H runs teal → sapphire → mauve → red and 7D
rosewater → peach → red. Claude Code sends `rate_limits` only on Pro/Max and
only after the first response; until then both bars show empty with `--%`, at
the size they'll have once data arrives.

💡 means extended thinking is on, and 🎨 is the active `/output-style`, hidden
for the default style. Segments with no data are dropped.

Each bar line is as wide as line 1, capped at `$COLUMNS`. Bars sharing a line
get equal cell counts, and leftover columns pad the numbers. No bar gets fewer
than 10 cells. Numbers are fixed-width (`  5%`, `(0h05m)`, `  45k/200k`), so
bars resize only when line 1 does.

## Develop

Run a throwaway session against your working copy. `--settings` overrides the
user setting for that session only, and edits show on the next refresh:

```bash
claude --settings "{\"statusLine\":{\"type\":\"command\",\"command\":\"$PWD/statusline.sh\"}}"
```

Or render without a session:

```bash
echo '{"model":{"display_name":"Opus"},"effort":{"level":"high"},"workspace":{"current_dir":"'"$PWD"'"},"context_window":{"total_input_tokens":45000,"context_window_size":200000},"cost":{"total_cost_usd":0.42},"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":'"$(( $(date +%s) + 8100 ))"'},"seven_day":{"used_percentage":18,"resets_at":'"$(( $(date +%s) + 300000 ))"'}}}' \
  | CLAUDE_STATUSLINE_SIZE=medium ./statusline.sh
```

Tests, also run by CI on macOS, Ubuntu, Debian-slim and Alpine:

```bash
python3 tests/statusline-harness.py          # ~4,500 renders: widths, equal cells, minimums, no jitter
python3 tests/statusline-harness.py --show   # also print sample renders
sh tests/test-install.sh                     # install.sh against throwaway homes
```

## Credit

The layouts and bar style follow
[AwesomeZun/CC-statusline](https://github.com/AwesomeZun/CC-statusline) (MIT).
This version has diverged: Mocha-only colors, width fitting and absolute
context thresholds. The history before this repo lived in
[rinman24/dotfiles](https://github.com/rinman24/dotfiles).

## License

MIT. See [LICENSE](LICENSE).
