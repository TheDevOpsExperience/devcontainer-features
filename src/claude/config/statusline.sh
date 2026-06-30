#!/usr/bin/env bash
# Claude Code status line — two-line prompt with model, folder, git, rate limits, context, duration

input=$(cat)

CYAN='\033[36m'; GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'; RESET='\033[0m'

_bar_color() {
  local pct=$1
  if   [ "$pct" -ge 90 ]; then printf '%s' "$RED"
  elif [ "$pct" -ge 70 ]; then printf '%s' "$YELLOW"
  else                         printf '%s' "$GREEN"; fi
}

_bar() {
  local pct=$1 fill pad
  local filled=$((pct / 10)) empty=$((10 - pct / 10))
  printf -v fill "%${filled}s"; printf -v pad "%${empty}s"
  printf '%s' "${fill// /█}${pad// /░}"
}

_fmt_reset() {
  local resets_at=$1 now secs days hrs mins
  now=$(date +%s)
  secs=$(( resets_at - now ))
  [ "$secs" -lt 0 ] && secs=0
  days=$(( secs / 86400 )); hrs=$(( (secs % 86400) / 3600 )); mins=$(( (secs % 3600) / 60 ))
  if [ "$days" -gt 0 ]; then printf "%dd %dh" "$days" "$hrs"
  else                        printf "%dh %02dm" "$hrs" "$mins"; fi
}

# Parse all values in one jq call
IFS=$'\t' read -r model cwd five_pct five_resets week_pct week_resets used_pct duration_ms < <(
  echo "$input" | jq -r '[
    (.model.display_name // "Claude"),
    (.workspace.current_dir // ""),
    (.rate_limits.five_hour.used_percentage // "" | if . == "" then "" else floor | tostring end),
    (.rate_limits.five_hour.resets_at // ""),
    (.rate_limits.seven_day.used_percentage // "" | if . == "" then "" else floor | tostring end),
    (.rate_limits.seven_day.resets_at // ""),
    (.context_window.used_percentage // 0 | floor),
    (.cost.total_duration_ms // 0)
  ] | @tsv'
)

folder=$(basename "$cwd")
branch=""
git rev-parse --git-dir > /dev/null 2>&1 && branch=" | 🌿 $(git branch --show-current 2>/dev/null)"

hrs=$((duration_ms / 3600000)); mins=$(((duration_ms % 3600000) / 60000)); secs=$((duration_ms % 60000 / 1000))

# Context bar (always shown)
ctx_bar="$(_bar_color "$used_pct")$(_bar "$used_pct")${RESET} ${used_pct}%"

# Rate limit bars (omitted when data unavailable)
rate_limit_info=""
if [ -n "$five_pct" ] && [ -n "$week_pct" ]; then
  five_bar="5h $(_bar_color "$five_pct")$(_bar "$five_pct")${RESET} ${five_pct}% ($(_fmt_reset "$five_resets"))"
  week_bar="7d $(_bar_color "$week_pct")$(_bar "$week_pct")${RESET} ${week_pct}% ($(_fmt_reset "$week_resets"))"
  rate_limit_info="${five_bar} | ${week_bar} | "
fi

echo -e "${CYAN}[$model]${RESET} 📁 ${folder}${branch}"
duration_fmt="${mins}m ${secs}s"; [ "$hrs" -gt 0 ] && duration_fmt="${hrs}h ${mins}m ${secs}s"
echo -e "${rate_limit_info} ctx ${ctx_bar} | ⏱️ ${duration_fmt}"
