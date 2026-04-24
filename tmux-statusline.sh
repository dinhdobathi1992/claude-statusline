#!/bin/bash
# Claude Code tmux status bar — reads from cache written by statusline.sh

CACHE_FILE="${TMPDIR:-/tmp}/claude-statusline/rate_cache.json"

# Colors (tmux format)
W="#[fg=colour255,bold]"
G="#[fg=colour82]"
Y="#[fg=colour226]"
R="#[fg=colour196]"
DM="#[fg=colour244,nobold]"
D="#[default]"

format_reset_time() {
    local reset_ts="$1"
    local window="$2"  # "5h" or "7d"
    local now remain
    now=$(date +%s)
    remain=$((reset_ts - now))
    [ "$remain" -le 0 ] && echo "now" && return
    if [ "$window" = "7d" ]; then
        python3 -c "
from datetime import datetime
dt = datetime.fromtimestamp($reset_ts)
day = dt.day
suffix = 'th' if 11 <= day <= 13 else {1:'st',2:'nd',3:'rd'}.get(day%10,'th')
print(dt.strftime('%a ') + f'{day}{suffix} ' + dt.strftime('%b %H:%M'))
" 2>/dev/null
    else
        python3 -c "
from datetime import datetime
dt = datetime.fromtimestamp($reset_ts)
print(dt.strftime('%H:%M %a') + f' {dt.day} ' + dt.strftime('%b'))
" 2>/dev/null
    fi
}

pct_color() {
    local pct="$1"
    if [ "$pct" -ge 90 ]; then echo "$R"
    elif [ "$pct" -ge 70 ]; then echo "$Y"
    else echo "$G"; fi
}

out=""

# Mode
if echo "${ANTHROPIC_BASE_URL:-}" | grep -qi "litellm"; then
    mode="Litellm"
elif echo "${ANTHROPIC_BASE_URL:-}" | grep -q "20128"; then
    mode="9router"
else
    mode="Native"
fi
out+=" ${DM}⚡${D} ${W}${mode}${D}"

# Native-only: email + rate limits
if [ "$mode" = "Native" ]; then
    # Account email
    if [ -f "$HOME/.claude.json" ]; then
        email=$(python3 -c "
import json
try:
    d=json.load(open('$HOME/.claude.json'))
    print(d.get('oauthAccount',{}).get('emailAddress',''))
except: pass
" 2>/dev/null)
        [ -n "$email" ] && out+=" ${DM}|${D} ${W}${email}${D}"
    fi

    # Rate limits from cache
    if [ -f "$CACHE_FILE" ]; then
        read -r FH_PCT FH_RESET SD_PCT SD_RESET <<< "$(python3 -c "
import json
try:
    d=json.load(open('$CACHE_FILE'))
    print(d['five_hr_pct'], d['five_hr_reset'], d['seven_day_pct'], d['seven_day_reset'])
except: print('0 0 0 0')
" 2>/dev/null)"

        if [ "${FH_RESET:-0}" -gt 0 ]; then
            c=$(pct_color "${FH_PCT:-0}")
            t=$(format_reset_time "$FH_RESET" "5h")
            out+=" ${DM}|${D} 5h: ${c}${FH_PCT}%${D} ${DM}resets at ${t}${D}"
        fi

        if [ "${SD_RESET:-0}" -gt 0 ]; then
            c=$(pct_color "${SD_PCT:-0}")
            t=$(format_reset_time "$SD_RESET" "7d")
            out+=" ${DM}|${D} 7d: ${c}${SD_PCT}%${D} ${DM}resets at ${t}${D}"
        fi
    fi
fi

echo "$out"
