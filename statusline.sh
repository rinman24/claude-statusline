#!/bin/bash
# Claude Code status line — managed by chezmoi (rinman24/dotfiles).
# Reads session JSON on stdin (https://code.claude.com/docs/en/statusline) and prints:
#   model · effort │ folder │ ⎇ branch │ wt worktree │ ctx used/size │ $cost
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

reset=$'\033[0m' dim=$'\033[2m' cyan=$'\033[36m' magenta=$'\033[35m'
green=$'\033[32m' yellow=$'\033[33m' red=$'\033[31m' blue=$'\033[34m'

# Absolute token thresholds, independent of window size.
if   [ "$tokens" -ge 120000 ]; then ctx_color=$red
elif [ "$tokens" -ge 95000 ];  then ctx_color=$yellow
else                                ctx_color=$green
fi

sep=" ${dim}│${reset} "
line="${cyan}${model}${reset}"
[ -n "$effort" ]   && line+="${dim} · ${reset}${effort}"
[ -n "$dir" ]      && line+="${sep}${blue}${dir##*/}${reset}"
[ -n "$branch" ]   && line+="${sep}${magenta}⎇ ${branch}${reset}"
[ -n "$worktree" ] && line+="${sep}${yellow}wt ${worktree}${reset}"
line+="${sep}${ctx_color}${ctx}${reset}"
line+="${sep}$(printf '$%.2f' "$cost")"

printf '%s\n' "$line"
