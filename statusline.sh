#!/bin/bash
# Claude Code status line — managed by chezmoi (rinman24/dotfiles).
# Reads session JSON on stdin (https://code.claude.com/docs/en/statusline) and prints:
#   🤖 model · effort │ 🪣 [bar] used/size │ 💸 $cost
#   📂 folder │ 🌿 branch │ 🌳 worktree
# Two short lines so it fits a vertically split Ghostty pane.
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
track=$'\033[48;2;49;50;68m'  # surface0 background for the bar's empty track

# Context thresholds in absolute tokens, independent of window size.
# The bar spans 0..CTX_BAR_MAX; at or past it the bar is full and 🚨 replaces 🪣.
CTX_WARN=95000 CTX_CRIT=120000 CTX_BAR_MAX=200000 BAR_CELLS=10

if   [ "$tokens" -ge "$CTX_CRIT" ]; then ctx_color=$red
elif [ "$tokens" -ge "$CTX_WARN" ]; then ctx_color=$yellow
else                                     ctx_color=$green
fi

# Eighth-block resolution: CTX_BAR_MAX / (BAR_CELLS * 8) tokens per step.
eighths=(' ' ▏ ▎ ▍ ▌ ▋ ▊ ▉)
steps=$(( tokens * BAR_CELLS * 8 / CTX_BAR_MAX ))
[ "$steps" -gt $(( BAR_CELLS * 8 )) ] && steps=$(( BAR_CELLS * 8 ))
bar=""
for (( i = 0; i < BAR_CELLS; i++ )); do
  n=$(( steps - i * 8 ))
  if   [ "$n" -ge 8 ]; then bar+="█"
  elif [ "$n" -gt 0 ]; then bar+="${eighths[n]}"
  else                      bar+=" "
  fi
done
ctx_icon="🪣"
[ "$tokens" -ge "$CTX_BAR_MAX" ] && ctx_icon="🚨"
printf -v cost_fmt '$%.2f' "$cost"

sep=" ${overlay0}│${reset} "

# Line 1: session — model · effort │ context │ cost
line1="🤖 ${mauve}${model}${reset}"
[ -n "$effort" ] && line1+="${overlay0} · ${lavender}${effort}${reset}"
line1+="${sep}${ctx_icon} ${track}${ctx_color}${bar}${reset} ${ctx_color}${ctx}${reset}"
line1+="${sep}💸 ${peach}${cost_fmt}${reset}"

# Line 2: location — folder │ branch │ worktree (omitted when all are empty)
line2=""
[ -n "$dir" ]      && line2+="${sep}📂 ${blue}${dir##*/}${reset}"
[ -n "$branch" ]   && line2+="${sep}🌿 ${teal}${branch}${reset}"
[ -n "$worktree" ] && line2+="${sep}🌳 ${pink}${worktree}${reset}"
line2=${line2#"$sep"}

printf '%s\n' "$line1"
if [ -n "$line2" ]; then printf '%s\n' "$line2"; fi
