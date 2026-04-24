# claude-statusline

A statusline script for [Claude Code](https://claude.ai/code) that displays session metrics, usage limits, mode detection, and account info — directly in the Claude Code status bar.

Includes optional **tmux status bar integration** that auto-refreshes every 5 minutes.

---

## Preview

```
📂 ~/Devops/ADI  🌿 main (3)  +86 -29
📊 66k/200k ████░░░░░░ 33% | 🤖 Sonnet-4.6 | ⚡ Native | 👤 you@gmail.com | 5h: 32% resets at 01:10 Sat 25 Apr | 7d: 4% resets at Fri 1st May 10:00 | ☘️ $0.15
```

**Line 1** — workspace context  
**Line 2** — session metrics (mode-aware)

---

## What it shows

### Always visible

| Element | Description |
|---|---|
| `📂 ~/projects/myapp` | Working directory (truncated to last 2 components if long) |
| `🌿 main (3)` | Git branch + number of staged/unstaged files changed |
| `+47 -12` | Lines added (green) and removed (red) this session |
| `📊 66k/200k ████░░░░░░ 33%` | Context tokens used / max + progress bar (green < 70%, yellow 70–89%, red ≥ 90%) |
| `🤖 Sonnet-4.6` | Active model (shortened display name) |
| `⚡ Native` or `⚡ Litellm` | API mode — detects `ANTHROPIC_BASE_URL` for LiteLLM proxy |
| `☘️ $0.15` | Session cost |

### Native mode only

| Element | Description |
|---|---|
| `👤 you@gmail.com` | Active Anthropic account email — reads from `~/.claude.json`, updates on account switch |
| `5h: 32% resets at 01:10 Sat 25 Apr` | 5-hour usage window — percentage used + exact reset time |
| `7d: 4% resets at Fri 1st May 10:00` | 7-day usage window — percentage used + exact reset date/time with ordinal suffix |

---

## Requirements

- [Claude Code](https://claude.ai/code) v2.1+
- `bash`, `python3` (pre-installed on macOS)
- For tmux integration: `tmux` 3.0+

---

## Install

### 1. Install the Claude Code statusline

```bash
bash -c '
set -e
mkdir -p ~/.claude
curl -fsSL "https://raw.githubusercontent.com/dinhdobathi1992/claude-statusline/main/statusline.sh" \
  -o ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh

SETTINGS="$HOME/.claude/settings.json"
ENTRY="  \"statusLine\": {\"type\": \"command\", \"command\": \"$HOME/.claude/statusline.sh\"}"

if [ ! -f "$SETTINGS" ] || [ ! -s "$SETTINGS" ]; then
  printf "{\n%s\n}\n" "$ENTRY" > "$SETTINGS"
elif grep -q "\"statusLine\"" "$SETTINGS"; then
  echo "statusLine already configured — skipping"
else
  trimmed=$(sed "s/[[:space:]]*}[[:space:]]*$//" "$SETTINGS")
  if echo "$trimmed" | grep -q "[^{[:space:]]"; then
    printf "%s,\n%s\n}\n" "$trimmed" "$ENTRY" > "$SETTINGS"
  else
    printf "%s\n%s\n}\n" "$trimmed" "$ENTRY" > "$SETTINGS"
  fi
fi
echo "Done — send a message in Claude Code to activate"
'
```

Send any message in Claude Code and the statusline activates immediately.

---

### 2. tmux integration (optional)

Shows Claude usage in your tmux status bar, **auto-refreshing every 5 minutes** independent of Claude Code responses.

**Step 1** — download the tmux script:

```bash
curl -fsSL "https://raw.githubusercontent.com/dinhdobathi1992/claude-statusline/main/tmux-statusline.sh" \
  -o ~/.claude/tmux-statusline.sh
chmod +x ~/.claude/tmux-statusline.sh
```

**Step 2** — add to your `~/.tmux.conf` (or download the example):

```bash
# Download example config (overwrites ~/.tmux.conf)
curl -fsSL "https://raw.githubusercontent.com/dinhdobathi1992/claude-statusline/main/tmux.conf.example" \
  -o ~/.tmux.conf
```

Or merge manually into your existing `~/.tmux.conf`:

```tmux
set -g status-interval 300
set -g status-right "#($HOME/.claude/tmux-statusline.sh) #[fg=colour244] %H:%M "
```

**Step 3** — reload tmux config:

```bash
tmux source-file ~/.tmux.conf
```

> The tmux script reads from a cache file written by `statusline.sh` on each Claude Code response. Reset times are always computed live from the stored Unix timestamps.

---

## How mode detection works

The script checks `$ANTHROPIC_BASE_URL` at runtime:

- Contains `litellm` → displays `⚡ Litellm`, hides email and usage limits
- Not set or no match → displays `⚡ Native`, shows email and usage limits

---

## How account email works

The active account email is read from `~/.claude.json` (Claude Code's main config file). This file is updated automatically whenever you switch accounts via `/login`, so the displayed email is always current.

---

## How usage limits work

Claude Code injects a `rate_limits` object into the statusline JSON on every response:

```json
"rate_limits": {
  "five_hour":  { "used_percentage": 32, "resets_at": 1777054200 },
  "seven_day":  { "used_percentage": 4,  "resets_at": 1777604400 }
}
```

The `resets_at` Unix timestamp is converted to a human-readable local time using `python3`:

- **5h window:** `01:10 Sat 25 Apr`
- **7d window:** `Fri 1st May 10:00` (with ordinal suffix — 1st, 2nd, 3rd, 11th, 21st, etc.)

Works on macOS and Linux.

---

## JSON fields used

| Field | Used for |
|---|---|
| `context_window.used_percentage` | Context bar |
| `context_window.context_window_size` | Context window max |
| `context_window.current_usage.*` | Token breakdown |
| `model.display_name` | Model label |
| `workspace.current_dir` | Working directory |
| `cost.total_cost_usd` | Session cost |
| `cost.total_lines_added/removed` | Code diff stats |
| `gitNumStagedOrUnstagedFilesChanged` | Dirty file count |
| `rate_limits.five_hour.*` | 5h usage window |
| `rate_limits.seven_day.*` | 7d usage window |

---

## Uninstall

Remove the `statusLine` block from `~/.claude/settings.json`, then:

```bash
rm ~/.claude/statusline.sh ~/.claude/tmux-statusline.sh
```

---

## License

MIT
