#!/usr/bin/env bash
# Generic Claude Code hook. Adapt paths to your setup. See README.
#
# emoji-blocker.sh - PreToolUse: Edit/Write/Gmail/LinkedIn
# Blocks emojis in external-facing material (HTML, email, LinkedIn).
# Rationale: emojis lower the "premium" feel of public copy.
# Skip: internal dirs (memory/notes/archive/.claude), internal report docs.
set -uo pipefail

# (optional: add your own logging here)
umask 077

[ -f "$HOME/.claude/state/HOOKS_DISABLED" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

INPUT=$(timeout 1 cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0

OVERRIDE_FILE="$HOME/.claude/state/hook-overrides.json"
if [ -f "$OVERRIDE_FILE" ]; then
    NOW_UTC=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    if jq -e --arg hook "emoji-allow" --arg now "$NOW_UTC" \
        '.active_overrides[]? | select(.hook == $hook and .expires > $now)' \
        "$OVERRIDE_FILE" >/dev/null 2>&1; then
        exit 0
    fi
fi

RESULT=$(INPUT="$INPUT" python3 <<'PY' 2>/dev/null
import os, sys, json, re

raw = os.environ.get("INPUT", "")
try:
    inp = json.loads(raw)
except Exception:
    sys.exit(0)

tool = inp.get("tool_name", "")
ti = inp.get("tool_input", {}) or {}

# Path-based skip for file tools. Adapt these to your own internal dirs.
SKIP_PATHS = [
    "/notes/", "/_archive/", "/memory/",
    "/.claude/hooks/", "/.claude/rules/", "/.claude/scripts/",
    "/.claude/agents/", "/.claude/skills/",
    "/.claude/state/", "/.claude/projects/",
]

REPORT_RE = re.compile(
    r"^(report|summary|status|health|audit)-\d{4}-?\d{2}-?\d{2}([-_].*)?\.(md|html|txt)$",
    re.IGNORECASE
)

# Public-facing tools (always scanned, regardless of path)
ALWAYS_SCAN_TOOLS = {
    "mcp__google-workspace__send_gmail_message",
    "mcp__google-workspace__draft_gmail_message",
    "mcp__linkedin__create_post",
    "mcp__linkedin__create_image_post",
    "mcp__linkedin__create_document_post",
    "mcp__linkedin__create_video_post",
    "mcp__linkedin__create_poll",
    "mcp__linkedin__update_draft",
    "mcp__linkedin__edit_post",
    "mcp__linkedin__schedule_post",
}

# Optional: a directory where internal report docs live (adapt or leave blank).
DOWNLOADS_ROOT = os.environ.get("HOOK_DOWNLOADS_ROOT", "").lower()

if tool in ("Edit", "Write", "MultiEdit"):
    fp_raw = ti.get("file_path") or ""
    fp = fp_raw.lower()
    for x in SKIP_PATHS:
        if x.lower() in fp:
            sys.exit(0)
    # Skip internal report docs under a configured downloads root
    if DOWNLOADS_ROOT:
        try:
            import os.path
            canonical = os.path.realpath(fp_raw).lower()
            if canonical.startswith(DOWNLOADS_ROOT):
                basename = os.path.basename(canonical)
                if REPORT_RE.match(basename):
                    sys.exit(0)
        except Exception:
            pass
    # Only external-facing formats
    if not any(fp.endswith(ext) for ext in (".html", ".htm", ".md", ".mdx", ".txt", ".eml", ".eta", ".j2", ".jinja", ".jinja2", ".hbs", ".liquid")):
        sys.exit(0)
elif tool in ALWAYS_SCAN_TOOLS:
    pass
else:
    sys.exit(0)

# Collect all strings to scan
def collect_strings(obj, out, depth=0):
    if depth > 10:
        return
    if isinstance(obj, str):
        out.append(obj)
    elif isinstance(obj, dict):
        for v in obj.values():
            collect_strings(v, out, depth+1)
    elif isinstance(obj, list):
        for v in obj:
            collect_strings(v, out, depth+1)

texts = []
if tool in ("Edit", "Write", "MultiEdit"):
    if ti.get("new_string"):
        texts.append(("new_string", ti["new_string"]))
    if ti.get("content"):
        texts.append(("content", ti["content"]))
    for i, e in enumerate(ti.get("edits") or []):
        if e.get("new_string"):
            texts.append((f"edits[{i}].new_string", e["new_string"]))
else:
    for k in ("body", "subject", "text", "commentary", "title", "comment"):
        v = ti.get(k)
        if isinstance(v, str):
            texts.append((k, v))
    for nested_key in ("post", "draft", "content"):
        nested = ti.get(nested_key)
        if isinstance(nested, dict):
            for k, v in nested.items():
                if isinstance(v, str):
                    texts.append((f"{nested_key}.{k}", v))

# Emoji detection via Unicode ranges (incl. ZWJ sequences, tone modifiers)
EMOJI_RE = re.compile(
    "["
    "\U0001F300-\U0001F5FF"  # Misc Symbols and Pictographs
    "\U0001F600-\U0001F64F"  # Emoticons
    "\U0001F680-\U0001F6FF"  # Transport and Map
    "\U0001F700-\U0001F77F"  # Alchemical
    "\U0001F780-\U0001F7FF"  # Geometric Shapes Ext
    "\U0001F800-\U0001F8FF"  # Supplemental Arrows-C
    "\U0001F900-\U0001F9FF"  # Supplemental Symbols and Pictographs
    "\U0001FA00-\U0001FA6F"  # Chess Symbols
    "\U0001FA70-\U0001FAFF"  # Symbols and Pictographs Ext-A
    "\U00002600-\U000026FF"  # Misc Symbols (sun, star, etc.)
    "\U00002700-\U000027BF"  # Dingbats (incl checkmark, cross)
    "]+",
    flags=re.UNICODE
)

# Whitelist: Unicode geometric shapes are allowed
WHITELIST = set("X")

found = []
for label, text in texts:
    for m in EMOJI_RE.finditer(text):
        emoji = m.group(0)
        if all(c in WHITELIST for c in emoji):
            continue
        s = max(0, m.start() - 20)
        e = min(len(text), m.end() + 20)
        ctx = text[s:e].replace("\n", "\\n")
        codepoints = " ".join(f"U+{ord(c):04X}" for c in emoji)
        found.append((label, emoji, codepoints, ctx))
        if len(found) >= 5:
            break
    if len(found) >= 5:
        break

if found:
    print("EMOJI_FOUND")
    print(f"TOOL:{tool}")
    for label, emoji, cps, ctx in found:
        print(f"  [{label}] '{emoji}' ({cps})")
        print(f"    ...{ctx}...")
PY
)

if echo "$RESULT" | grep -q "^EMOJI_FOUND"; then
    cat >&2 <<EOF
BLOCKED by emoji-blocker.sh

Emoji found in external-facing content:

$RESULT

RULE:
  No emojis in HTML, email, LinkedIn, PDF, slides, copy.
  Emojis lower the premium feel of public copy.

USE INSTEAD:
  - Geometric SVG icons / whitelisted Unicode shapes
  - CSS ::before with a colored circle/dash
  - Large numbers or gradient text as an accent
  - Status words (OK, FAIL, DONE) for automated messages

EXCEPTIONS:
  - Internal dirs (notes/memory/_archive/.claude)
  - Internal report docs (report-*, summary-*, etc.)

OVERRIDE (if intentional):
  ~/.claude/state/hook-overrides.json:
  {"hook":"emoji-allow","expires":"<ISO-UTC>","reason":"...","created_by":"you","created_at":"<ISO-UTC>"}
EOF
    exit 2
fi
exit 0
