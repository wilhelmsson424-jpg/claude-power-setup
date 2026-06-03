#!/usr/bin/env bash
# Generic Claude Code hook. Adapt paths to your setup. See README.
#
# aao-warn-extras.sh - WARN (never block) when Bash/MCP Swedish text is missing
# the characters a-ring/a-umlaut/o-umlaut (the Swedish letters used as a demo).
#
# This is a language-correctness reminder, shown as an example of detecting
# missing accented characters. Adapt the marker words / red flags to your locale.
#
# Complements a stricter validator that blocks Write/Edit. This one covers the
# gap: the Bash tool + Google Workspace manage_event/manage_task.
#
# Design principles:
#   1. NEVER exit 2 - always exit 0. Only reminds.
#   2. systemMessage via JSON so the model sees the warning next turn (stderr is hidden).
#   3. Output allowlist: never leak substrings from the command (secret safety).
#   4. Hard input cap 50KB, timeout 2s, ReDoS guard.
#   5. Heuristic: require >=2 language markers + len>=40 (lowers false positives).
#   6. Bash precheck: skip if INPUT already has the accented chars (saves python startup).
#
# Master kill-switch: touch ~/.claude/state/HOOKS_DISABLED

# (optional: add your own logging here)
set -uo pipefail
[ -f "$HOME/.claude/state/HOOKS_DISABLED" ] && exit 0

umask 077

# Quick precheck: if INPUT already has the accented chars, skip (saves python startup)
INPUT=$(timeout 2 head -c 51200 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0
case "$INPUT" in
  *å*|*ä*|*ö*|*Å*|*Ä*|*Ö*) exit 0 ;;
esac

command -v python3 >/dev/null 2>&1 || exit 0

REPORT=$(INPUT="$INPUT" python3 2>/dev/null <<'PY'
import os, sys, json, re

try:
    raw = os.environ.get("INPUT", "")
    if len(raw) > 51200:
        sys.exit(0)
    data = json.loads(raw)
except BaseException:
    sys.exit(0)

try:
    tool_name = data.get("tool_name", "") or ""
    inp = data.get("tool_input", {}) or {}

    COVERED = {
      "Bash": ["command"],
      "mcp__google-workspace__manage_event": ["summary", "description"],
      "mcp__google-workspace__manage_task": ["title", "notes"],
    }
    if tool_name not in COVERED:
        sys.exit(0)

    chunks = []
    for field in COVERED[tool_name]:
        val = inp.get(field, "")
        if isinstance(val, str) and 40 <= len(val) <= 50000:
            chunks.append((field, val))
    if not chunks:
        sys.exit(0)

    # Language markers (Swedish demo). Adapt to your locale.
    SWEDISH_MARKERS = [
        "för", "och", "är", "som", "till", "att", "med", "vid", "inte",
        "denna", "detta", "om", "kan", "ska", "vi", "du", "jag",
        "från", "ej", "över",
    ]
    UNAMBIGUOUS_HINTS = ["lardom", "fonster", "narvarande", "atgard",
                          "behovs", "kallor", "matning"]

    # Map of common ASCII-fallback misspellings to their accented forms.
    RED_FLAGS = {
      "lardom": "lärdom",
      "lardomar": "lärdomar",
      "fonster": "fönster",
      "narvarande": "närvarande",
      "manga": "många",
      "atgard": "åtgärd",
      "atgarder": "åtgärder",
      "behovs": "behövs",
      "korning": "körning",
      "kallor": "källor",
      "lasa": "läsa",
      "matning": "mätning",
      "forst": "först",
      "forsta": "första",
      "fragor": "frågor",
      "valkommen": "välkommen",
      "gora": "göra",
      "maste": "måste",
      "behover": "behöver",
      "fore": "före",
      "narmast": "närmast",
      "atergang": "återgång",
    }

    OUTPUT_TOKEN_RE = re.compile(r"^[a-zA-ZåäöÅÄÖ]{4,30}$")
    WORD_BOUNDARIES = [re.compile(r"\b" + re.escape(w) + r"\b", re.IGNORECASE)
                       for w in RED_FLAGS.keys()]
    WORD_LIST = list(RED_FLAGS.keys())

    hits = []
    for field, text in chunks:
        text_lower = text.lower()
        marker_count = sum(1 for m in SWEDISH_MARKERS if m.lower() in text_lower)
        has_unambiguous = any(h.lower() in text_lower for h in UNAMBIGUOUS_HINTS)
        if marker_count < 2 and not has_unambiguous:
            continue
        for idx, pat in enumerate(WORD_BOUNDARIES):
            for m in pat.finditer(text):
                hit_word = m.group(0)
                if any(c in hit_word for c in "åäöÅÄÖ"):
                    continue
                if not OUTPUT_TOKEN_RE.match(hit_word):
                    continue
                base = WORD_LIST[idx]
                suggest = RED_FLAGS[base]
                hits.append({
                    "field": field,
                    "word": hit_word,
                    "suggest": suggest,
                })
                if len(hits) >= 5:
                    break
            if len(hits) >= 5:
                break
        if len(hits) >= 5:
            break

    if not hits:
        sys.exit(0)

    out = [f"TOOL:{tool_name}"]
    for h in hits:
        out.append(f"  - {h['field']}: \"{h['word']}\" -> \"{h['suggest']}\"")
    print("\n".join(out))
except BaseException:
    sys.exit(0)
PY
)

if [ -n "$REPORT" ]; then
    if command -v jq >/dev/null 2>&1; then
        MSG=$(printf "REMINDER (aao-warn-extras): missing accented characters in Swedish text. Reminder, not a block.\n\n%s" "$REPORT")
        jq -n --arg msg "$MSG" '{decision:"approve", systemMessage:$msg}' 2>/dev/null || true
    fi
fi

exit 0
