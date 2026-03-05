# claude-statusline

A lightweight, dependency-free statusline script for [Claude Code](https://claude.ai/code) that displays native session metrics — context usage, model, cache efficiency, cost, and git status — directly in the Claude Code status bar.

No external API. No Python. No jq. Works out of the box on macOS and Linux.

---

## Preview

```
📂 ~/projects/myapp  🌿 main (3)  +47 -12
📊 143k/200k ▮▮▮▮▯▯▯▯▯▯ 48% | 🤖 Sonnet-4.5 | 💾 62% ↑3k | ☘️ $0.0031 | ⏱ 3m 5s
```

**Line 1** — workspace context  
**Line 2** — session metrics

---

## What it shows

| Element | Description |
|---|---|
| `📂 ~/projects/myapp` | Working directory (truncated to last 2 components if long) |
| `🌿 main (3)` | Git branch + number of staged/unstaged files changed |
| `+47 -12` | Lines added (green) and removed (red) this session |
| `📊 143k/200k` | Current context tokens used / context window size |
| `▮▮▮▮▯▯▯▯▯▯ 48%` | Context window progress bar — green < 70%, yellow 70–89%, red ≥ 90% |
| `🤖 Sonnet-4.5` | Active model (shortened display name) |
| `💾 62%` | Prompt cache hit ratio — percentage of input tokens served from cache |
| `↑3k` | Output tokens generated in last API call |
| `☘️ $0.0031` | Cumulative session cost in USD (native from Claude Code, not estimated) |
| `⏱ 3m 5s` | Elapsed wall-clock time since session started |

---

## Requirements

- [Claude Code](https://claude.ai/code) (any recent version)
- `bash`, `curl`, `sed`, `grep` — all pre-installed on macOS and most Linux distros
- No Python, no jq, no Node.js required

---

## Install (one command)

```bash
bash -c '
set -e
SETTINGS="$HOME/.claude/settings.json"
ENTRY="  \"statusLine\": {\"type\": \"command\", \"command\": \"~/.claude/statusline.sh\"}"

mkdir -p ~/.claude
curl -fsSL "https://raw.githubusercontent.com/dinhdobathi1992/claude-statusline/main/statusline.sh" \
  -o ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
echo "✓ Downloaded statusline.sh"

if [ ! -f "$SETTINGS" ] || [ ! -s "$SETTINGS" ]; then
  printf "{\n%s\n}\n" "$ENTRY" > "$SETTINGS"
  echo "✓ Created $SETTINGS"
elif grep -q "\"statusLine\"" "$SETTINGS"; then
  echo "✓ statusLine already configured — skipping"
else
  trimmed=$(sed "s/[[:space:]]*}[[:space:]]*$//" "$SETTINGS")
  if echo "$trimmed" | grep -q "[^{[:space:]]"; then
    printf "%s,\n%s\n}\n" "$trimmed" "$ENTRY" > "$SETTINGS"
  else
    printf "%s\n%s\n}\n" "$trimmed" "$ENTRY" > "$SETTINGS"
  fi
  echo "✓ Updated $SETTINGS"
fi

echo "Done — send your next message in Claude Code to activate"
'
```

The installer:
1. Downloads `statusline.sh` to `~/.claude/statusline.sh`
2. Makes it executable
3. Adds the `statusLine` entry to `~/.claude/settings.json` (creates the file if it does not exist, skips safely if already configured)

---

## Manual install

```bash
# 1. Download the script
curl -fsSL "https://raw.githubusercontent.com/dinhdobathi1992/claude-statusline/main/statusline.sh" \
  -o ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh

# 2. Add to ~/.claude/settings.json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  }
}
```

---

## Activation

No restart required. The statusline appears at the bottom of Claude Code after your **next message**. It updates automatically after every assistant response.

---

## Test locally

Pipe a sample JSON payload to the script to preview the output in your terminal:

```bash
echo '{
  "model": {"id": "claude-sonnet-4-5", "display_name": "Claude Sonnet 4.5"},
  "workspace": {"current_dir": "'"$PWD"'"},
  "cost": {"total_cost_usd": 0.005, "total_duration_ms": 90000, "total_lines_added": 20, "total_lines_removed": 5},
  "context_window": {
    "context_window_size": 200000,
    "used_percentage": 35,
    "current_usage": {
      "input_tokens": 5000,
      "output_tokens": 800,
      "cache_creation_input_tokens": 10000,
      "cache_read_input_tokens": 55000
    }
  }
}' | ~/.claude/statusline.sh
```

---

## Uninstall

Remove the `statusLine` block from `~/.claude/settings.json`, or run inside Claude Code:

```
/statusline remove
```

Then optionally delete the script:

```bash
rm ~/.claude/statusline.sh
```

---

## How it works

Claude Code runs the script after each assistant response, piping a JSON payload to stdin. The script parses the payload with `grep`/`sed` (no external JSON tools needed), formats the output with ANSI colours, and prints two lines that Claude Code renders in the status bar.

Key fields used from the Claude Code JSON context:

| JSON field | Used for |
|---|---|
| `cost.total_cost_usd` | Session cost (native, not estimated) |
| `cost.total_duration_ms` | Elapsed session time |
| `cost.total_lines_added/removed` | Code diff stats |
| `context_window.used_percentage` | Context bar percentage |
| `context_window.context_window_size` | Context window max |
| `context_window.current_usage.*` | Token breakdown + cache hit ratio |
| `model.display_name` / `model.id` | Model display |
| `workspace.current_dir` | Working directory |
| `gitNumStagedOrUnstagedFilesChanged` | Dirty file count |

Git branch is not included in the JSON payload — the script fetches it directly via `git branch --show-current` and caches the result for 5 minutes per directory.

---

## License

MIT
