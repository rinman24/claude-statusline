#!/bin/bash
# Claude Code status line — managed by chezmoi (rinman24/dotfiles).
# Reads session JSON on stdin (https://code.claude.com/docs/en/statusline).
# Two layouts, after AwesomeZun/CC-statusline's small and medium presets:
#   small (2 lines)
#     🤖 model · effort 💡 ┃ 🎨 style ┃ 💸 $cost ┃ 📂 folder ┃ 🌿 branch ┃ 🌳 worktree
#     🪣 [bar] used/size ┃ 5H [bar] % (left) ┃ 7D [bar] % (day)
#   medium (4 lines)
#     🤖 model · effort 💡 ┃ 🎨 style ┃ 💸 $cost
#     📂 folder ┃ 🌿 branch ┃ 🌳 worktree
#     🪣 Context [bar] used/size
#     🚀 Usage 5H [bar] % (left) ┃ 7D [bar] % (day)
# 💡 means extended thinking is on; 🎨 is the active /output-style.
# $CLAUDE_STATUSLINE_SIZE picks the layout for one session; otherwise
# ~/.claude/statusline-size does, re-read on every refresh. Default: small.
# Segments with no data (effort, 💡, folder, branch, worktree) are dropped,
# as is 🎨 for the default style. All three bars always show.
#
# Bars are gradient-filled █ cells on a ░ track, as upstream draws them. Fonts
# that render ░ as a flat block can switch to ⣿ dots: "dots" in
# $CLAUDE_STATUSLINE_TRACK or ~/.claude/statusline-track, read like the size.
# Each bar line spans the width of line 1, capped at $COLUMNS, but never gives
# a bar fewer than MIN_CELLS cells; bars sharing a line get equal cell counts
# and the leftover columns pad the numbers. Numbers have fixed widths, so bars
# only resize when line 1 does.

# Width measurement needs character, not byte, lengths.
LC_ALL=en_US.UTF-8

input=$(cat)

size=$CLAUDE_STATUSLINE_SIZE
[ -z "$size" ] && read -r size 2>/dev/null < ~/.claude/statusline-size
track=$CLAUDE_STATUSLINE_TRACK
[ -z "$track" ] && read -r track 2>/dev/null < ~/.claude/statusline-track

# One jq pass; fields joined by \x1f so empty values survive `read`.
IFS=$'\x1f' read -r model effort thinking style dir worktree ctx_used ctx_size \
  tokens cost five_pct five_left seven_pct seven_day < <(
  printf '%s' "$input" | jq -r '
    def human: if . >= 999500 then "\((. / 100000 | round) / 10)M"
               elif . >= 1000 then "\(. / 1000 | round)k"
               else tostring end;
    def pct: if . == null then "" else round end;
    def left: if . == null then ""
              else . - now | if . < 0 then 0 else floor end
                   | "\(. / 3600 | floor)h\(. % 3600 / 60 | floor
                        | if . < 10 then "0\(.)" else tostring end)m" end;
    def day: if . == null then "" else strflocaltime("%a") end;
    [ .model.display_name // .model.id // "?",
      .effort.level // "",
      .thinking.enabled // false,
      .output_style.name // "",
      .workspace.current_dir // .cwd // "",
      .workspace.git_worktree // .worktree.name // "",
      (.context_window.total_input_tokens // 0 | human),
      (.context_window.context_window_size // 200000 | human),
      .context_window.total_input_tokens // 0,
      .cost.total_cost_usd // 0,
      (.rate_limits.five_hour.used_percentage | pct),
      (.rate_limits.five_hour.resets_at | left),
      (.rate_limits.seven_day.used_percentage | pct),
      (.rate_limits.seven_day.resets_at | day)
    ] | map(tostring) | join("\u001f")'
)

branch=""
if [ -n "$dir" ]; then
  branch=$(git -C "$dir" --no-optional-locks branch --show-current 2>/dev/null)
  [ -z "$branch" ] && branch=$(git -C "$dir" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
fi

# Catppuccin Mocha (https://catppuccin.com/palette), 24-bit foreground.
rgb() { printf -v "$1" '\033[38;2;%d;%d;%dm' "0x${2:0:2}" "0x${2:2:2}" "0x${2:4:2}"; }
reset=$'\033[0m' bold=$'\033[1m'
rgb mauve cba6f7; rgb lavender b4befe; rgb blue 89b4fa; rgb teal 94e2d5
rgb pink f5c2e7;  rgb peach fab387;    rgb yellow f9e2af; rgb flamingo f2cdcd
rgb overlay0 6c7086

# Gradient stops as POSITION HEX pairs, positions in the bar's own units.
# Usage bars run 0..100 percent, ending in red as in AwesomeZun/CC-statusline
# (MIT). Mocha colors share one lightness, so the stops swing wide in hue to
# stay visible where upstream ran pale to saturated.
FIVE_STOPS=(0 94e2d5 33 74c7ec 66 cba6f7 100 f38ba8)  # teal → sapphire → mauve → red
SEVEN_STOPS=(0 f5e0dc 50 fab387 100 f38ba8)           # rosewater → peach → red

# Context runs 0..CTX_BAR_MAX tokens, with stops at absolute thresholds
# independent of window size: green → yellow at CTX_WARN → red from CTX_CRIT.
# At or past CTX_BAR_MAX the bar is full and 🚨 replaces 🪣.
CTX_WARN=95000 CTX_CRIT=120000 CTX_BAR_MAX=200000
CTX_STOPS=(0 a6e3a1 "$CTX_WARN" f9e2af "$CTX_CRIT" f38ba8)

MIN_CELLS=10  # narrowest bar that still shows every gradient stop

case $size in
  m|medium) ;;
  *)        size=small ;;
esac
case $track in
  dots|⣿) track=⣿ ;;
  *)      track=░ ;;
esac

# Bash scopes locals dynamically, so a callee's local would capture a caller's
# output variable of the same name. Each function prefixes its locals.

# gradient VAR X POS HEX [POS HEX]... — set VAR to the color at X, interpolated
# between the stops around it and clamped to the first and last.
gradient() {
  local g_out=$1 g_x=$2 g_p0=$3 g_c0=$4 g_p1=$3 g_c1=$4 g_i g_ch=()
  shift 2
  while [ $# -ge 2 ]; do
    g_p1=$1 g_c1=$2
    [ "$g_x" -le "$g_p1" ] && break
    g_p0=$1 g_c0=$2
    shift 2
  done
  for g_i in 0 2 4; do
    if [ "$g_p1" -gt "$g_p0" ]; then
      g_ch+=( $(( 0x${g_c0:g_i:2} + (0x${g_c1:g_i:2} - 0x${g_c0:g_i:2}) * (g_x - g_p0) / (g_p1 - g_p0) )) )
    else
      g_ch+=( $(( 0x${g_c1:g_i:2} )) )
    fi
  done
  printf -v "$g_out" '\033[38;2;%d;%d;%dm' "${g_ch[@]}"
}

# draw_bar BAR_VAR COLOR_VAR CELLS VALUE MAX STOPS... — CELLS whole cells over
# 0..MAX. Each filled cell takes the color at its own position; the track,
# and COLOR_VAR for the caller's text, take the color at VALUE.
draw_bar() {
  local b_bar=$1 b_color=$2 b_cells=$3 b_value=$4 b_max=$5 b_out="" b_end b_c b_i b_filled
  shift 5
  b_filled=$(( (b_value * b_cells + b_max / 2) / b_max ))
  [ "$b_filled" -gt "$b_cells" ] && b_filled=$b_cells
  gradient b_end "$b_value" "$@"
  for (( b_i = 0; b_i < b_cells; b_i++ )); do
    if [ "$b_i" -lt "$b_filled" ]; then
      gradient b_c $(( b_i * b_max / b_cells )) "$@"; b_out+="${b_c}█"
    else
      b_out+="${b_end}${track}"
    fi
  done
  printf -v "$b_bar" '%s' "${b_out}${reset}"
  printf -v "$b_color" '%s' "$b_end"
}

# width VAR STRING — display columns: ANSI escapes stripped and the wide emoji
# this script prints counted as 2. Other wide characters (CJK in a branch
# name) count as 1, so the bar lines then fall a little short of line 1.
width() {
  local w_s=$2 w_plain="" w_e w_rest w_n
  # Strip escapes one at a time; an extglob ${s//…/} takes seconds in bash 3.2.
  while [[ $w_s == *$'\033['* ]]; do
    w_plain+=${w_s%%$'\033['*}
    w_s=${w_s#*$'\033['}
    w_s=${w_s#*m}
  done
  w_s=$w_plain$w_s
  w_n=${#w_s}
  for w_e in 🤖 💡 🎨 💸 📂 🌿 🌳 🪣 🚨 🚀; do
    w_rest=${w_s//"$w_e"/}
    w_n=$(( w_n + ${#w_s} - ${#w_rest} ))
  done
  printf -v "$1" '%d' "$w_n"
}

# context_segment VAR CELLS PAD — bar, then used/size after PAD extra spaces.
context_segment() {
  local x_out=$1 x_bar x_color x_text
  draw_bar x_bar x_color "$2" "$tokens" "$CTX_BAR_MAX" "${CTX_STOPS[@]}"
  printf -v x_text '%*s%4s/%s' "$3" '' "$ctx_used" "$ctx_size"
  printf -v "$x_out" '%s' "${x_bar} ${x_color}${x_text}${reset}"
}

# usage_segment VAR CELLS PAD LABEL_COLOR LABEL PCT NOTE NOTE_WIDTH STOPS...
# Before the first response Claude Code sends no rate_limits: the bar is drawn
# empty with "--%", and a missing note is blanked to NOTE_WIDTH so the bars
# keep their size when the data arrives.
usage_segment() {
  local u_out=$1 u_cells=$2 u_pad=$3 u_label="$4$5$reset" u_pct=$6 u_note=$7 u_nw=$8 u_bar u_color u_seg
  shift 8
  draw_bar u_bar u_color "$u_cells" "${u_pct:-0}" 100 "$@"
  if [ -n "$u_pct" ]; then
    printf -v u_seg '%s %s %*s%s%s%3d%%%s' \
      "$u_label" "$u_bar" "$u_pad" '' "$bold" "$u_color" "$u_pct" "$reset"
  else
    printf -v u_seg '%s %s %*s%s --%%%s' "$u_label" "$u_bar" "$u_pad" '' "$overlay0" "$reset"
  fi
  if [ -n "$u_note" ]; then
    u_seg+=" ${overlay0}(${u_note})${reset}"
  else
    printf -v u_seg '%s%*s' "$u_seg" $(( u_nw + 3 )) ''
  fi
  printf -v "$u_out" '%s' "$u_seg"
}

# usage_segments VAR CELLS R FIRST — "5H … │ 7D …". Numbers are counted from
# FIRST, and each one numbered below R gets one extra space.
usage_segments() {
  local s_out=$1 s_cells=$2 s_r=$3 s_j=$4 s_five s_seven
  usage_segment s_five "$s_cells" $(( s_j < s_r )) "$lavender" 5H "$five_pct" "$five_left" 5 "${FIVE_STOPS[@]}"
  usage_segment s_seven "$s_cells" $(( s_j + 1 < s_r )) "$yellow" 7D "$seven_pct" "$seven_day" 3 "${SEVEN_STOPS[@]}"
  printf -v "$s_out" '%s' "${s_five}${sep}${s_seven}"
}

# Bar-line builders: BUILDER CELLS R sets $built with CELLS-cell bars and the
# first R numbers padded by one space.
small_bars() {
  local l_ctx l_usage
  context_segment l_ctx "$1" $(( 0 < $2 ))
  built="${ctx_icon} ${l_ctx}"
  usage_segments l_usage "$1" "$2" 1
  built+="${sep}${l_usage}"
}
medium_context() {
  local l_ctx
  context_segment l_ctx "$1" "$2"
  built="${ctx_icon} ${pink}Context${reset} ${l_ctx}"
}
medium_usage() {
  local l_usage
  usage_segments l_usage "$1" "$2" 0
  built="🚀 ${pink}Usage${reset} ${l_usage}"
}

# fit_line VAR TARGET BARS BUILDER — render with empty bars to measure the
# rest, then give each of BARS bars an equal share of what's left of TARGET
# (at least MIN_CELLS) and spread the remainder over the numbers.
fit_line() {
  local f_out=$1 f_target=$2 f_k=$3 f_build=$4 f_fixed f_n f_r
  "$f_build" 0 0
  width f_fixed "$built"
  f_n=$(( (f_target - f_fixed) / f_k ))
  [ "$f_n" -lt "$MIN_CELLS" ] && f_n=$MIN_CELLS
  f_r=$(( f_target - f_fixed - f_k * f_n ))
  [ "$f_r" -lt 0 ] && f_r=0
  "$f_build" "$f_n" "$f_r"
  printf -v "$f_out" '%s' "$built"
}

ctx_icon="🪣"
[ "$tokens" -ge "$CTX_BAR_MAX" ] && ctx_icon="🚨"
printf -v cost_fmt '$%.2f' "$cost"
cols=$COLUMNS
case $cols in ''|*[!0-9]*) cols=0 ;; esac

# ┃ (heavy) rather than │: terminals draw box characters themselves, so bold
# doesn't reliably thicken a light line.
sep=" ${overlay0}┃${reset} "

# Segments
session="🤖 ${mauve}${model}${reset}"
[ -n "$effort" ] && session+="${overlay0} · ${lavender}${effort}${reset}"
[ "$thinking" = true ] && session+=" 💡"
case $style in ''|[Dd]efault) ;; *) session+="${sep}🎨 ${flamingo}${style}${reset}" ;; esac
session+="${sep}💸 ${peach}${cost_fmt}${reset}"

location=""
[ -n "$dir" ]      && location+="${sep}📂 ${blue}${dir##*/}${reset}"
[ -n "$branch" ]   && location+="${sep}🌿 ${teal}${branch}${reset}"
[ -n "$worktree" ] && location+="${sep}🌳 ${pink}${worktree}${reset}"
location=${location#"$sep"}

# Layout. Bar lines target line 1's width, capped at the terminal's.
line1=$session
[ "$size" = small ] && [ -n "$location" ] && line1+="${sep}${location}"
width target "$line1"
[ "$cols" -gt 0 ] && [ "$target" -gt "$cols" ] && target=$cols

if [ "$size" = small ]; then
  fit_line line2 "$target" 3 small_bars
  lines=("$line1" "$line2")
else
  lines=("$line1")
  [ -n "$location" ] && lines+=("$location")
  fit_line row "$target" 1 medium_context
  lines+=("$row")
  fit_line row "$target" 2 medium_usage
  lines+=("$row")
fi

printf '%s\n' "${lines[@]}"
