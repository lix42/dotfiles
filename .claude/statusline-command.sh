#!/bin/sh
# Claude Code status line - inspired by Starship Catppuccin Mocha theme

# Catppuccin Mocha palette (ANSI approximations)
RED='\033[38;2;243;139;168m'       # red #f38ba8
PEACH='\033[38;2;250;179;135m'     # peach #fab387
YELLOW='\033[38;2;249;226;175m'    # yellow #f9e2af
GREEN='\033[38;2;166;227;161m'     # green #a6e3a1
SAPPHIRE='\033[38;2;116;199;236m'  # sapphire #74c7ec
LAVENDER='\033[38;2;180;190;254m'  # lavender #b4befe
CRUST='\033[38;2;17;17;27m'        # crust #11111b (for bg text reference)
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

input=$(cat)

# --- Directory ---
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
# Truncate: show last 3 path segments
short_dir=$(echo "$cwd" | awk -F'/' '{
  n=NF
  if (n<=3) { print $0 }
  else { print "…/" $(n-2) "/" $(n-1) "/" $n }
}')

# --- Git info (skip optional locks for speed) ---
git_branch=""
git_status_str=""
if git_output=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null); then
  git_branch="$git_output"
  dirty=$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null | head -1)
  if [ -n "$dirty" ]; then
    git_status_str="✗"
  fi
fi

# --- Model ---
model=$(echo "$input" | jq -r '.model.display_name // ""')

# --- Context usage ---
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# --- Rate limit usage (session / weekly); displayed as remaining % ---
five_hour_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
seven_day_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
five_hour_resets_at=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
seven_day_resets_at=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

# Format seconds-until-reset as a short human string ("3h12m", "4d", "45m")
format_remaining() {
  resets_at="$1"
  now=$(date +%s)
  remaining=$(awk -v r="$resets_at" -v n="$now" 'BEGIN { d = r - n; if (d < 0) d = 0; print int(d) }')
  if [ "$remaining" -le 0 ]; then
    return
  fi
  days=$((remaining / 86400))
  hours=$(((remaining % 86400) / 3600))
  minutes=$(((remaining % 3600) / 60))
  if [ "$days" -ge 1 ]; then
    printf "%dd" "$days"
  elif [ "$hours" -ge 1 ]; then
    printf "%dh%dm" "$hours" "$minutes"
  else
    printf "%dm" "$minutes"
  fi
}

five_hour_remaining=""
[ -n "$five_hour_resets_at" ] && five_hour_remaining=$(format_remaining "$five_hour_resets_at")
seven_day_remaining=""
[ -n "$seven_day_resets_at" ] && seven_day_remaining=$(format_remaining "$seven_day_resets_at")

# --- Build output ---
printf "${RED} ${RESET}"
printf "${PEACH}${BOLD} %s ${RESET}" "$short_dir"
printf "${YELLOW}"
if [ -n "$git_branch" ]; then
  printf " ${YELLOW}${BOLD} %s" "$git_branch"
  if [ -n "$git_status_str" ]; then
    printf " %s" "$git_status_str"
  fi
  printf " ${RESET}"
fi
printf "${SAPPHIRE}${BOLD} %s ${RESET}" "$model"
if [ -n "$used_pct" ]; then
  printf "${DIM}${LAVENDER}ctx: %s%%${RESET}" "$used_pct"
fi
if [ -n "$five_hour_pct" ] || [ -n "$seven_day_pct" ]; then
  printf " ${DIM}${GREEN}"
  if [ -n "$five_hour_pct" ]; then
    printf "%.0f%%" "$(awk -v u="$five_hour_pct" 'BEGIN { print 100 - u }')"
    [ -n "$five_hour_remaining" ] && printf "(-%s)" "$five_hour_remaining"
  fi
  [ -n "$five_hour_pct" ] && [ -n "$seven_day_pct" ] && printf " / "
  if [ -n "$seven_day_pct" ]; then
    printf "%.0f%%" "$(awk -v u="$seven_day_pct" 'BEGIN { print 100 - u }')"
    [ -n "$seven_day_remaining" ] && printf "(-%s)" "$seven_day_remaining"
  fi
  printf "${RESET}"
fi
