#!/bin/bash
# Claude Code status line — managed by chezmoi (rinman24/dotfiles).
# Reads session JSON on stdin (https://code.claude.com/docs/en/statusline) and prints:
#   model · effort │ 📂 folder │ 🌿 branch │ 🌳 worktree │ used/size │ $cost
# Segments with no data (effort, folder, branch, worktree) are dropped.

input=$(cat)

# One jq pass; fields joined by \x1f so empty values survive `read`.
IFS=$'\x1f' read -r model effort dir worktree ctx tokens cost < <(
  printf '%s' "$input" | jq -r '
    def human: if . >= 1000000 then "\((. / 100000 | round) / 10)M"
               elif . >= 1000 then "\(. / 1000 | round)k"
               else tostring end;
    [ .model.display_name // .model.id // "?",
      .effort.level // "",
      .workspace.current_dir // .cwd // "",
      .workspace.git_worktree // .worktree.name // "",
      "\(.context_window.total_input_tokens // 0 | human)/\(.context_window.context_window_size // 200000 | human)",
      .context_window.total_input_tokens // 0,
      .cost.total_cost_usd // 0
    ] | map(tostring) | join("\u001f")'
)

branch=""
if [ -n "$dir" ]; then
  branch=$(git -C "$dir" --no-optional-locks branch --show-current 2>/dev/null)
  [ -z "$branch" ] && branch=$(git -C "$dir" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
fi

# Catppuccin Mocha (https://catppuccin.com/palette), 24-bit foreground.
rgb() { printf -v "$1" '\033[38;2;%d;%d;%dm' "0x${2:0:2}" "0x${2:2:2}" "0x${2:4:2}"; }
reset=$'\033[0m'
rgb mauve cba6f7; rgb lavender b4befe; rgb blue 89b4fa; rgb teal 94e2d5
rgb pink f5c2e7;  rgb peach fab387;    rgb green a6e3a1; rgb yellow f9e2af
rgb red f38ba8;   rgb overlay0 6c7086

# Absolute token thresholds, independent of window size.
if   [ "$tokens" -ge 120000 ]; then ctx_color=$red
elif [ "$tokens" -ge 95000 ];  then ctx_color=$yellow
else                                ctx_color=$green
fi

sep=" ${overlay0}│${reset} "
line="${mauve}${model}${reset}"
[ -n "$effort" ]   && line+="${overlay0} · ${lavender}${effort}${reset}"
[ -n "$dir" ]      && line+="${sep}📂 ${blue}${dir##*/}${reset}"
[ -n "$branch" ]   && line+="${sep}🌿 ${teal}${branch}${reset}"
[ -n "$worktree" ] && line+="${sep}🌳 ${pink}${worktree}${reset}"
line+="${sep}${ctx_color}${ctx}${reset}"
line+="${sep}${peach}$(printf '$%.2f' "$cost")${reset}"

printf '%s\n' "$line"
