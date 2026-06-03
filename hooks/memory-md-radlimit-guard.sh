#!/usr/bin/env bash
# Generic Claude Code hook. Adapt paths to your setup. See README.
#
# memory-md-radlimit-guard.sh - PreToolUse blocker.
# Blocks Edit/Write/MultiEdit on a target memory index file if the result would
# exceed a line/byte limit. Keeps an index file disciplined (index only, not detail).
#
# Configure the guarded file and limits via environment variables:
#   HOOK_MEMORY_FILE_SUFFIX  - path suffix that triggers the guard
#                              (default: "/memory/MEMORY.md")
#   HOOK_MEMORY_MAX_LINES    - max lines (default: 80)
#   HOOK_MEMORY_MAX_BYTES    - max bytes (default: 49152)
#
# Override: add "memory-radlimit-allow" to ~/.claude/state/hook-overrides.json
# Master kill-switch: touch ~/.claude/state/HOOKS_DISABLED

# (optional: add your own logging here)
set -uo pipefail
umask 077

LOG_FILE="$HOME/.claude/state/hook-blocks.log"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
chmod 700 "$(dirname "$LOG_FILE")" 2>/dev/null || true

# Kill-switch
[ -f "$HOME/.claude/state/HOOKS_DISABLED" ] && exit 0

# Override
OVERRIDE_FILE="$HOME/.claude/state/hook-overrides.json"
if [ -f "$OVERRIDE_FILE" ] && command -v jq >/dev/null 2>&1; then
    NOW_UTC=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    if jq -e --arg hook "memory-radlimit-allow" --arg now "$NOW_UTC" \
        '.active_overrides[]? | select(.hook == $hook and .expires > $now)' \
        "$OVERRIDE_FILE" >/dev/null 2>&1; then
        exit 0
    fi
fi

command -v python3 >/dev/null 2>&1 || exit 0

INPUT=$(timeout 2 cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0

REPORT=$(INPUT="$INPUT" python3 <<'PY'
import os, sys, json

raw = os.environ.get("INPUT", "")
try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)

tool = data.get("tool_name", "") or ""
inp = data.get("tool_input", {}) or {}
fp = (inp.get("file_path") or "").strip()

SUFFIX = os.environ.get("HOOK_MEMORY_FILE_SUFFIX", "/memory/MEMORY.md")

# Only the configured index file triggers
if not fp.endswith(SUFFIX):
    sys.exit(0)
if tool not in ("Write", "Edit", "MultiEdit"):
    sys.exit(0)

LIMIT_LINES = int(os.environ.get("HOOK_MEMORY_MAX_LINES", "80"))
LIMIT_BYTES = int(os.environ.get("HOOK_MEMORY_MAX_BYTES", "49152"))

# Compute the future size after the change
def predict():
    if tool == "Write":
        return inp.get("content") or ""
    try:
        with open(fp, "r", encoding="utf-8") as f:
            cur = f.read()
    except Exception:
        return None
    if tool == "Edit":
        old = inp.get("old_string") or ""
        new = inp.get("new_string") or ""
        replace_all = bool(inp.get("replace_all"))
        if replace_all:
            return cur.replace(old, new)
        return cur.replace(old, new, 1)
    if tool == "MultiEdit":
        result = cur
        for e in (inp.get("edits") or []):
            if not isinstance(e, dict): continue
            o = e.get("old_string") or ""
            n = e.get("new_string") or ""
            ra = bool(e.get("replace_all"))
            result = result.replace(o, n) if ra else result.replace(o, n, 1)
        return result
    return None

future = predict()
if future is None:
    sys.exit(0)

future_lines = future.count("\n") + (1 if future and not future.endswith("\n") else 0)
future_bytes = len(future.encode("utf-8"))

violations = []
if future_lines > LIMIT_LINES:
    violations.append(f"lines: {future_lines} (max {LIMIT_LINES})")
if future_bytes > LIMIT_BYTES:
    violations.append(f"bytes: {future_bytes} (max {LIMIT_BYTES})")

if not violations:
    sys.exit(0)

print(f"TOOL:{tool}")
print(f"FILE:{fp}")
for v in violations:
    print(f"  X {v}")
PY
)

if [ -n "$REPORT" ]; then
    {
        printf '[%s] BLOCKED memory-md-radlimit\n%s\n---\n' \
            "$(date -Iseconds)" "$REPORT"
    } >> "$LOG_FILE" 2>/dev/null || true

    cat >&2 <<EOF
BLOCKED by memory-md-radlimit-guard.sh

The memory index file must stay an index (small). This change exceeds the limit:

$REPORT

ACTION:
  1. Create a topic file under memory/<subfolder>/
  2. Write the detail there
  3. Add a one-line pointer in the index: "- [Title](path)"
  4. Move stale entries to an archive folder

RULE: the index file is an index only. One line per entry.

OVERRIDE (one-time):
  Add to ~/.claude/state/hook-overrides.json:
  {"hook":"memory-radlimit-allow","expires":"<ISO-UTC>","reason":"...","created_by":"you","created_at":"<ISO-UTC>"}
EOF
    exit 2
fi

exit 0
