#!/bin/bash
# Claude Code Native Statusline
# Receives JSON context from Claude Code via stdin.
# No external API calls - uses native cost/token fields provided by Claude Code.

CACHE_DIR="${TMPDIR:-/tmp}/claude-statusline"
GIT_CACHE_FILE="$CACHE_DIR/git_branch_cache"
GIT_CACHE_TTL=300  # 5 minutes

mkdir -p "$CACHE_DIR" 2>/dev/null

INPUT=$(cat)

# ---------------------------------------------------------------------------
# Parse JSON fields (portable grep/sed, no jq required)
# ---------------------------------------------------------------------------
parse_context() {
    local json="$1"

    # Workspace / git
    CWD=$(echo "$json" | grep -o '"current_dir"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*:.*"\([^"]*\)"/\1/' | head -1)
    # Fallback to legacy "cwd" field
    [ -z "$CWD" ] && CWD=$(echo "$json" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*:.*"\([^"]*\)"/\1/' | head -1)
    GIT_NUM_FILES=$(echo "$json" | grep -o '"gitNumStagedOrUnstagedFilesChanged"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:[[:space:]]*//' | head -1)

    # Model
    MODEL=$(echo "$json" | grep -o '"display_name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*:.*"\([^"]*\)"/\1/' | head -1)
    MODEL_ID=$(echo "$json" | grep -o '"model_id"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*:.*"\([^"]*\)"/\1/' | head -1)
    # Fallback to "id" field matching claude-* pattern
    [ -z "$MODEL_ID" ] && MODEL_ID=$(echo "$json" | grep -o '"id"[[:space:]]*:[[:space:]]*"claude[^"]*"' | sed 's/.*:.*"\([^"]*\)"/\1/' | head -1)

    # Context window (current_usage = tokens from last API call)
    INPUT_TOKENS=$(echo "$json" | grep -o '"input_tokens"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:[[:space:]]*//' | head -1)
    CACHE_CREATION=$(echo "$json" | grep -o '"cache_creation_input_tokens"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:[[:space:]]*//' | head -1)
    CACHE_READ=$(echo "$json" | grep -o '"cache_read_input_tokens"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:[[:space:]]*//' | head -1)
    OUTPUT_TOKENS=$(echo "$json" | grep -o '"output_tokens"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:[[:space:]]*//' | head -1)
    INPUT_TOKENS="${INPUT_TOKENS:-0}"
    CACHE_CREATION="${CACHE_CREATION:-0}"
    CACHE_READ="${CACHE_READ:-0}"
    OUTPUT_TOKENS="${OUTPUT_TOKENS:-0}"

    # Pre-calculated context percentage (null early in session)
    CTX_PCT=$(echo "$json" | grep -o '"used_percentage"[[:space:]]*:[[:space:]]*[0-9.]*' | sed 's/.*:[[:space:]]*//' | head -1 | cut -d. -f1)
    CTX_PCT="${CTX_PCT:-0}"

    MAX_TOKENS=$(echo "$json" | grep -o '"context_window_size"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:[[:space:]]*//' | head -1)
    # Detect 1M context models if context_window_size not provided
    if [ -z "$MAX_TOKENS" ]; then
        if echo "$MODEL $MODEL_ID" | grep -qiE '1m|1000k'; then
            MAX_TOKENS=1000000
        else
            MAX_TOKENS=200000
        fi
    fi
    # Derive used tokens from percentage and max to stay consistent with the bar
    if [ "$CTX_PCT" -gt 0 ]; then
        CONVERSATION_TOKENS=$((MAX_TOKENS * CTX_PCT / 100))
    else
        CONVERSATION_TOKENS=$((INPUT_TOKENS + CACHE_CREATION + CACHE_READ))
    fi

    # Native cost + duration (provided directly by Claude Code)
    TOTAL_COST=$(echo "$json" | grep -o '"total_cost_usd"[[:space:]]*:[[:space:]]*[0-9.]*' | sed 's/.*:[[:space:]]*//' | head -1)
    TOTAL_COST="${TOTAL_COST:-0}"
    DURATION_MS=$(echo "$json" | grep -o '"total_duration_ms"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:[[:space:]]*//' | head -1)
    DURATION_MS="${DURATION_MS:-0}"

    # Lines changed
    LINES_ADDED=$(echo "$json" | grep -o '"total_lines_added"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:[[:space:]]*//' | head -1)
    LINES_REMOVED=$(echo "$json" | grep -o '"total_lines_removed"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:[[:space:]]*//' | head -1)
    LINES_ADDED="${LINES_ADDED:-0}"
    LINES_REMOVED="${LINES_REMOVED:-0}"

    # Rate limits (5h and 7d windows) — parsed via python3 for nested JSON reliability
    read -r FIVE_HR_PCT FIVE_HR_RESET SEVEN_DAY_PCT SEVEN_DAY_RESET <<< "$(echo "$json" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    rl=d.get('rate_limits',{})
    fh=rl.get('five_hour',{})
    sd=rl.get('seven_day',{})
    print(int(fh.get('used_percentage',0)), int(fh.get('resets_at',0)), int(sd.get('used_percentage',0)), int(sd.get('resets_at',0)))
except: print('0 0 0 0')
" 2>/dev/null)"
    FIVE_HR_PCT="${FIVE_HR_PCT:-0}"
    FIVE_HR_RESET="${FIVE_HR_RESET:-0}"
    SEVEN_DAY_PCT="${SEVEN_DAY_PCT:-0}"
    SEVEN_DAY_RESET="${SEVEN_DAY_RESET:-0}"

    # Write cache for tmux statusline
    if [ "$FIVE_HR_RESET" -gt 0 ] || [ "$SEVEN_DAY_RESET" -gt 0 ]; then
        printf '{"five_hr_pct":%s,"five_hr_reset":%s,"seven_day_pct":%s,"seven_day_reset":%s}\n' \
            "$FIVE_HR_PCT" "$FIVE_HR_RESET" "$SEVEN_DAY_PCT" "$SEVEN_DAY_RESET" \
            > "$CACHE_DIR/rate_cache.json" 2>/dev/null
    fi

    # Defaults
    CWD="${CWD:-$(pwd)}"
    GIT_NUM_FILES="${GIT_NUM_FILES:-0}"
    MODEL="${MODEL:-unknown}"
    MODEL_ID="${MODEL_ID:-}"

    # Git branch (not in JSON - fetched locally with caching)
    GIT_BRANCH=""
    if [ -n "$CWD" ] && [ -d "$CWD" ] && command -v git >/dev/null 2>&1; then
        if git -C "$CWD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            local cache_key="$GIT_CACHE_FILE.$(printf '%s' "$CWD" | md5 -q 2>/dev/null || printf '%s' "$CWD" | md5sum 2>/dev/null | cut -d' ' -f1 || echo "x")"
            local now
            now=$(date +%s)

            if [ -f "$cache_key" ]; then
                local cache_time
                cache_time=$(stat -f %m "$cache_key" 2>/dev/null || stat -c %Y "$cache_key" 2>/dev/null || echo 0)
                [ $((now - cache_time)) -lt "$GIT_CACHE_TTL" ] && GIT_BRANCH=$(cat "$cache_key" 2>/dev/null)
            fi

            if [ -z "$GIT_BRANCH" ]; then
                GIT_BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null)
                [ -n "$GIT_BRANCH" ] && echo "$GIT_BRANCH" > "$cache_key" 2>/dev/null
            fi
        fi
    fi
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
format_model() {
    local model="$1"
    local tier version

    if echo "$model" | grep -qiE '(opus|sonnet|haiku)[[:space:]]*[0-9]'; then
        tier=$(echo "$model" | grep -oiE '(opus|sonnet|haiku)' | head -1)
        version=$(echo "$model" | grep -oE '[0-9]+\.[0-9]+' | head -1)
        tier="$(echo "${tier:0:1}" | tr '[:lower:]' '[:upper:]')${tier:1}"
        [ -n "$version" ] && echo "${tier}-${version}" || echo "$tier"
        return
    fi

    if echo "$model" | grep -qiE 'claude.*(opus|sonnet|haiku)'; then
        tier=$(echo "$model" | grep -oiE '(opus|sonnet|haiku)' | head -1)
        tier="$(echo "${tier:0:1}" | tr '[:lower:]' '[:upper:]')${tier:1}"
        version=$(echo "$model" | grep -oE '[0-9]+[\.\-][0-9]+' | tail -1 | tr '-' '.')
        [ -n "$version" ] && echo "${tier}-${version}" || echo "$tier"
        return
    fi

    echo "$model" | sed 's/^claude-//' | cut -c1-14
}

shorten_path() {
    local path="$1"
    path="${path/#$HOME/~}"
    [ ${#path} -gt 40 ] && path=$(echo "$path" | awk -F'/' '{print $(NF-1)"/"$NF}')
    echo "$path"
}

progress_bar() {
    local pct="$1"  # 0-100
    local width=10
    local filled=$((pct * width / 100))
    local empty=$((width - filled))
    local bar=""

    # Color thresholds: green < 70, yellow 70-89, red >= 90
    local color
    if [ "$pct" -ge 90 ]; then color="\033[31m"
    elif [ "$pct" -ge 70 ]; then color="\033[33m"
    else color="\033[32m"; fi

    for ((i=0; i<filled; i++)); do bar+="${color}█\033[0m"; done
    for ((i=0; i<empty; i++)); do bar+="\033[90m░\033[0m"; done

    echo "$bar"
}

format_tokens() {
    local num="$1"
    [ "$num" -ge 1000000 ] && { echo "$((num / 1000000))M"; return; }
    [ "$num" -ge 1000 ] && echo "$((num / 1000))k" || echo "$num"
}

format_duration() {
    local ms="$1"
    local secs=$((ms / 1000))
    local mins=$((secs / 60))
    secs=$((secs % 60))
    [ "$mins" -gt 0 ] && echo "${mins}m ${secs}s" || echo "${secs}s"
}

format_cost() {
    local cost="$1"
    # Show 4 decimal places if < $0.01, otherwise 2
    if command -v bc >/dev/null 2>&1; then
        local is_small
        is_small=$(echo "$cost < 0.01" | bc 2>/dev/null || echo "0")
        if [ "$is_small" = "1" ]; then
            printf '%.4f' "$cost" 2>/dev/null || echo "$cost"
        else
            printf '%.2f' "$cost" 2>/dev/null || echo "$cost"
        fi
    else
        printf '%.4f' "$cost" 2>/dev/null || echo "$cost"
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    parse_context "$INPUT"

    local W="\033[97m"   # Bright white
    local G="\033[32m"   # Green
    local R="\033[31m"   # Red
    local Y="\033[33m"   # Yellow
    local C="\033[36m"   # Cyan
    local DM="\033[90m"  # Dim grey
    local D="\033[0m"    # Reset

    # --- Line 1: path  git branch  lines diff ---
    local line1=""
    local short_cwd
    short_cwd=$(shorten_path "$CWD")
    line1+="📂 ${W}${short_cwd}${D}"

    if [ -n "$GIT_BRANCH" ]; then
        line1+="  🌿 ${W}${GIT_BRANCH}${D}"
        [ "$GIT_NUM_FILES" -gt 0 ] && line1+=" ${DM}(${GIT_NUM_FILES})${D}"
    fi

    if [ "$LINES_ADDED" -gt 0 ] || [ "$LINES_REMOVED" -gt 0 ]; then
        line1+="  ${G}+${LINES_ADDED}${D} ${R}-${LINES_REMOVED}${D}"
    fi

    # --- Line 2: context bar  model  cache hit  cost  duration ---
    local line2=""

    # Context bar (uses pre-calculated percentage from Claude Code)
    local ctx_bar
    ctx_bar=$(progress_bar "$CTX_PCT")
    local ctx_used
    ctx_used=$(format_tokens "$CONVERSATION_TOKENS")
    local ctx_max
    ctx_max=$(format_tokens "$MAX_TOKENS")
    line2+="📊 ${W}${ctx_used}/${ctx_max}${D} $ctx_bar ${W}${CTX_PCT}%${D}"

    # Model
    local model_display
    model_display=$(format_model "$MODEL")
    line2+=" ${DM}|${D} 🤖 ${W}${model_display}${D}"

    # Mode: Litellm or Native
    local mode="Native"
    if echo "${ANTHROPIC_BASE_URL:-}" | grep -qi "litellm"; then
        mode="Litellm"
    fi
    line2+=" ${DM}|${D} ⚡ ${W}${mode}${D}"

    # Account email + usage limits — Native mode only
    if [ "$mode" = "Native" ]; then
        local acct_email=""
        if [ -f "$HOME/.claude.json" ]; then
            acct_email=$(python3 -c "
import json,sys
try:
    d=json.load(open('$HOME/.claude.json'))
    print(d.get('oauthAccount',{}).get('emailAddress',''))
except: pass
" 2>/dev/null)
        fi
        [ -n "$acct_email" ] && line2+=" ${DM}|${D} 👤 ${W}${acct_email}${D}"
    fi

    # 5-hour usage limit (Native only)
    if [ "$mode" = "Native" ] && ([ "$FIVE_HR_PCT" -gt 0 ] || [ "$FIVE_HR_RESET" -gt 0 ]); then
        local usage_color
        if [ "$FIVE_HR_PCT" -ge 90 ]; then usage_color="$R"
        elif [ "$FIVE_HR_PCT" -ge 70 ]; then usage_color="$Y"
        else usage_color="$G"; fi
        local reset_str=""
        if [ "$FIVE_HR_RESET" -gt 0 ]; then
            local now remain_secs
            now=$(date +%s)
            remain_secs=$((FIVE_HR_RESET - now))
            if [ "$remain_secs" -gt 0 ]; then
                local reset_time
                reset_time=$(python3 -c "
from datetime import datetime
dt = datetime.fromtimestamp($FIVE_HR_RESET)
print(dt.strftime('%H:%M %a') + f' {dt.day} ' + dt.strftime('%b'))
" 2>/dev/null)
                [ -n "$reset_time" ] && reset_str=" ${DM}resets at ${reset_time}${D}"
            fi
        fi
        line2+=" ${DM}|${D} 5h: ${usage_color}${FIVE_HR_PCT}%${D}${reset_str}"
    fi

    # 7-day usage limit (Native only)
    if [ "$mode" = "Native" ] && ([ "$SEVEN_DAY_PCT" -gt 0 ] || [ "$SEVEN_DAY_RESET" -gt 0 ]); then
        local w_color
        if [ "$SEVEN_DAY_PCT" -ge 90 ]; then w_color="$R"
        elif [ "$SEVEN_DAY_PCT" -ge 70 ]; then w_color="$Y"
        else w_color="$G"; fi
        local w_reset_str=""
        if [ "$SEVEN_DAY_RESET" -gt 0 ]; then
            local now remain_secs
            now=$(date +%s)
            remain_secs=$((SEVEN_DAY_RESET - now))
            if [ "$remain_secs" -gt 0 ]; then
                local reset_time
                reset_time=$(python3 -c "
from datetime import datetime
dt = datetime.fromtimestamp($SEVEN_DAY_RESET)
day = dt.day
suffix = 'th' if 11 <= day <= 13 else {1:'st',2:'nd',3:'rd'}.get(day%10,'th')
print(dt.strftime('%a ') + f'{day}{suffix} ' + dt.strftime('%b %H:%M'))
" 2>/dev/null)
                [ -n "$reset_time" ] && w_reset_str=" ${DM}resets at ${reset_time}${D}"
            fi
        fi
        line2+=" ${DM}|${D} 7d: ${w_color}${SEVEN_DAY_PCT}%${D}${w_reset_str}"
    fi

    # Session cost
    if command -v bc >/dev/null 2>&1 || [ "$TOTAL_COST" != "0" ]; then
        local cost_fmt
        cost_fmt=$(format_cost "$TOTAL_COST")
        line2+=" ${DM}|${D} ☘️ ${W}\$${cost_fmt}${D}"
    fi


    echo -e "$line1"
    echo -e "$line2"
}

main
