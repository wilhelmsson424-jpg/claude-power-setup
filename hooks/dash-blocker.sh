#!/usr/bin/env bash
# Generic Claude Code hook. Adapt paths to your setup. See README.
#
# dash-blocker.sh - PreToolUse blocker
# Blocks em-dash (-, U+2014) and en-dash (-, U+2013) in:
#   - Write/Edit/MultiEdit (file content)
#   - mcp__google-workspace__send_gmail_message / draft_gmail_message (body+subject)
#   - mcp__linkedin__create_post / create_image_post / create_document_post / create_video_post
#   - mcp__linkedin__update_draft / schedule_post
#   - Bash commands writing to public web paths
#
# Rationale: em/en-dash often signals AI-generated text. Some writers never use it.
#
# Exceptions (file paths under): internal dirs, the rule files themselves.
# Override (file-based, with expiry): ~/.claude/state/hook-overrides.json
# Master kill-switch: touch ~/.claude/state/HOOKS_DISABLED

# (optional: add your own logging here)
set -uo pipefail

umask 077
LOG_FILE="$HOME/.claude/state/hook-blocks.log"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
chmod 700 "$(dirname "$LOG_FILE")" 2>/dev/null || true

# Master kill-switch
[ -f "$HOME/.claude/state/HOOKS_DISABLED" ] && exit 0

# File-based override with expiry
OVERRIDE_FILE="$HOME/.claude/state/hook-overrides.json"
if [ -f "$OVERRIDE_FILE" ] && command -v jq >/dev/null 2>&1; then
    NOW_UTC=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    if jq -e --arg hook "dash-allow" --arg now "$NOW_UTC" \
        '.active_overrides[]? | select(.hook == $hook and .expires > $now)' \
        "$OVERRIDE_FILE" >/dev/null 2>&1; then
        exit 0
    fi
fi

# Fail-open on missing dependencies
command -v python3 >/dev/null 2>&1 || exit 0

INPUT=$(timeout 2 cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0

REPORT=$(INPUT="$INPUT" python3 <<'PY'
import os, sys, json, re

raw = os.environ.get("INPUT", "")
try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)

tool_name = data.get("tool_name", "") or ""
inp = data.get("tool_input", {}) or {}

# Path exceptions (for Write/Edit/MultiEdit).
# Two lists: SKIP_DIRS require "/" on both ends (path-segment match);
# SKIP_BASENAMES require the file's basename to start with the string.
fp_raw = inp.get("file_path") or ""
fp = fp_raw.lower()

# Adapt these to your own internal dirs.
SKIP_DIRS = [
    "/notes/", "/_archive/", "/memory/",
    "/.claude/",
    "/_handovers/", "/_internal/",
]
SKIP_BASENAMES = [
    "dash-blocker.sh",
]
import os.path as _osp_skip
fp_basename = _osp_skip.basename(fp)
skip_reason = None
for x in SKIP_DIRS:
    if x in fp:
        skip_reason = f"dir-segment:{x}"
        break
if not skip_reason:
    for x in SKIP_BASENAMES:
        if fp_basename.startswith(x):
            skip_reason = f"basename-prefix:{x}"
            break

# Optional: internal report docs under a configured public/downloads root.
# Set HOOK_DOWNLOADS_ROOT to enable; left blank by default.
DOWNLOADS_ROOT = os.environ.get("HOOK_DOWNLOADS_ROOT", "").lower()
if not skip_reason and fp_raw and DOWNLOADS_ROOT:
    try:
        import os.path
        canonical = os.path.realpath(fp_raw).lower()
        if canonical.startswith(DOWNLOADS_ROOT):
            basename = os.path.basename(canonical)
            REPORT_RE = re.compile(
                r"^(report|summary|status|health|audit)-\d{4}-?\d{2}-?\d{2}([-_].*)?\.(md|html|txt)$",
                re.IGNORECASE
            )
            if REPORT_RE.match(basename):
                skip_reason = f"report-doc:{basename}"
    except Exception:
        pass  # fail-closed: block if path resolution fails

if skip_reason:
    try:
        log_path = os.path.expanduser("~/.claude/state/dash-blocker-skips.log")
        with open(log_path, "a") as f:
            from datetime import datetime, timezone
            f.write(f"{datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.%f')}Z\t{tool_name}\t{skip_reason}\t{fp_raw}\n")
    except Exception:
        pass
    sys.exit(0)

# Collect all strings to scan, depending on tool
chunks = []  # list of (label, text)

def add(label, val):
    if isinstance(val, str) and val:
        chunks.append((label, val))

if tool_name in ("Write",):
    add("content", inp.get("content"))
elif tool_name in ("Edit",):
    add("new_string", inp.get("new_string"))
elif tool_name in ("MultiEdit",):
    edits = inp.get("edits") or []
    for i, e in enumerate(edits):
        if isinstance(e, dict):
            add(f"edits[{i}].new_string", e.get("new_string"))

elif tool_name in ("mcp__google-workspace__send_gmail_message",
                   "mcp__google-workspace__draft_gmail_message"):
    add("subject", inp.get("subject"))
    add("body", inp.get("body"))

elif tool_name in ("mcp__linkedin__create_post",
                   "mcp__linkedin__create_image_post",
                   "mcp__linkedin__create_document_post",
                   "mcp__linkedin__create_video_post",
                   "mcp__linkedin__update_draft",
                   "mcp__linkedin__schedule_post"):
    add("text", inp.get("text"))
    add("commentary", inp.get("commentary"))
    add("content", inp.get("content"))
    add("post_text", inp.get("post_text"))

# Bash: heredocs and redirects can otherwise bypass the blocker entirely.
# Only scan commands that write to public web paths (adapt the regex to your setup).
elif tool_name in ("Bash",):
    cmd = inp.get("command") or ""
    if cmd:
        PUBLIC_BASH_RE = re.compile(
            r"(?:>+\s*|tee\s+(?:-a\s+)?)['\"]?(?:/var/www|/srv/www)",
            re.IGNORECASE
        )
        if PUBLIC_BASH_RE.search(cmd):
            add("bash.command", cmd)

if not chunks:
    sys.exit(0)

# Find em-dash (U+2014) or en-dash (U+2013)
EM = "—"
EN = "–"

hits = []
for label, text in chunks:
    lines = text.split("\n")
    for ln_idx, line in enumerate(lines, start=1):
        for ch_idx, ch in enumerate(line, start=1):
            if ch == EM or ch == EN:
                start = max(0, ch_idx - 21)
                end = min(len(line), ch_idx + 20)
                snippet = line[start:end]
                kind = "em-dash (U+2014)" if ch == EM else "en-dash (U+2013)"
                hits.append({
                    "field": label,
                    "line": ln_idx,
                    "col": ch_idx,
                    "kind": kind,
                    "snippet": snippet,
                })
                if len(hits) >= 5:
                    break
        if len(hits) >= 5:
            break
    if len(hits) >= 5:
        break

if not hits:
    sys.exit(0)

print(f"TOOL:{tool_name}")
for h in hits:
    print(f"  - {h['field']} line {h['line']} col {h['col']} [{h['kind']}]")
    print(f"    ...{h['snippet']}...")
PY
)

if [ -n "$REPORT" ]; then
    {
        printf '[%s] BLOCKED dash-blocker\n%s\n---\n' \
            "$(date -Iseconds)" "$REPORT"
    } >> "$LOG_FILE" 2>/dev/null || true

    cat >&2 <<EOF
BLOCKED by dash-blocker.sh

Em-dash or en-dash found in text to be written/sent:

$REPORT

REPLACE WITH:
  - Comma (,)            for pauses in sentences
  - Colon (:)            for explanations
  - Period (.)           to end sentences
  - Plain hyphen (-)     for compound words
  - Parentheses ()       for asides

WHY:
  Em/en-dash often signals AI-generated text.
  Keep external text dash-free.

EXCEPTIONS (dashes allowed):
  - Internal files: /.claude/, /notes/, /memory/, /_archive/, /_handovers/
  - Code comments, README, code blocks
  - Quotes from external sources

BLOCKED (external-facing, dash forbidden):
  - Email (Gmail send/draft) and LinkedIn posts
  - Files in /var/www/, /srv/www/ (websites)
  - Bash commands writing to public paths

OVERRIDE (file-based, with expiry):
  Add to ~/.claude/state/hook-overrides.json:
  {"hook":"dash-allow","expires":"<ISO-UTC>","reason":"...","created_by":"you","created_at":"<ISO-UTC>"}

Master kill-switch (all hooks off):
  touch ~/.claude/state/HOOKS_DISABLED
EOF
    exit 2
fi

exit 0
