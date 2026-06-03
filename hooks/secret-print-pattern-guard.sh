#!/usr/bin/env bash
# Generic Claude Code hook. Adapt paths to your setup. See README.
#
# secret-print-pattern-guard.sh - PreToolUse: Bash + Edit/Write
# Blocks generating a secret that is printed to stdout/log instead of being piped
# straight into a secret store or written to a protected file.
# Rationale: printing a freshly generated token makes it appear in the transcript,
# which forces a rotation.
set -uo pipefail

# (optional: add your own logging here)
umask 077

[ -f "$HOME/.claude/state/HOOKS_DISABLED" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(timeout 1 cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0

TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

CONTENT=""
case "$TOOL" in
    Bash)
        CONTENT=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
        ;;
    Edit|Write|MultiEdit)
        FP=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
        case "$FP" in
            *.py|*.js|*.ts|*.sh|*.bash|*.zsh|*.rb|*.go) ;;
            *) exit 0 ;;
        esac
        CONTENT=$(echo "$INPUT" | jq -r '
            (.tool_input.new_string // "") + "\n" +
            (.tool_input.content // "") + "\n" +
            ((.tool_input.edits // []) | map(.new_string // "") | join("\n"))
        ' 2>/dev/null)
        ;;
    *) exit 0 ;;
esac

[ -z "$CONTENT" ] && exit 0

# Generator patterns (Python, Node, openssl, /dev/urandom)
GENERATORS='secrets\.(token_hex|token_urlsafe|token_bytes)|crypto\.(randomBytes|randomUUID)|openssl[[:space:]]+rand|head[[:space:]]+/dev/urandom|uuid\.uuid4|base64[[:space:]]+/dev/urandom|pwgen[[:space:]]'

# Skip if no generator is used
if ! echo "$CONTENT" | grep -qE "$GENERATORS"; then
    exit 0
fi

# Is the generator output piped to a legitimate consumer?
# Adapt "secret-store" names to your own tool (pass, gpg, age, a vault CLI, etc.).
SAFE_PIPE='\|[^|]*(secret-store|vault[[:space:]]+(add|put|set|insert)|pass[[:space:]]+insert|gpg[[:space:]]+(--encrypt|-e|--symmetric)|age[[:space:]]+-(e|-encrypt))'
# Or a redirect to a protected file
SAFE_REDIRECT='>>?[[:space:]]*["'\'']?(/etc/secrets|\$HOME/\.secrets|~/\.secrets|/root/\.secrets)'

# Specific risk patterns
if echo "$CONTENT" | grep -qE "print\([^)]*secrets\.(token_hex|token_urlsafe)" \
   || echo "$CONTENT" | grep -qE "console\.log\([^)]*crypto\.randomBytes" \
   || echo "$CONTENT" | grep -qE 'echo[[:space:]]+\$\([[:space:]]*openssl[[:space:]]+rand'; then

    if echo "$CONTENT" | grep -qE "$SAFE_PIPE"; then
        exit 0
    fi
    if echo "$CONTENT" | grep -qE "$SAFE_REDIRECT"; then
        exit 0
    fi
    # Skip-comment marker
    if echo "$CONTENT" | grep -qE '#[[:space:]]*noprint-secret\b'; then
        exit 0
    fi

    cat >&2 <<'EOF'
BLOCKED by secret-print-pattern-guard.sh

You are generating a secret but printing it to stdout/log (transcript leak):
  Detected: print/console.log/echo with a secret generator and NO pipe to a secret store.

RULE:
  Never generate a secret in a separate step that prints to the transcript.
  Pipe it directly into your secret store or write it to a protected file.

WRONG (transcript leak):
  the generated value ends up in tool-result = LEAK -> rotation required

RIGHT (value never leaves the pipe buffer):
  pipe the generator straight into your-secret-store add NAME --from-stdin
  OR redirect it into a protected file, then chmod 600 that file.

OVERRIDE (if the secret is short-lived and should not be stored):
  Skip pattern: add a "# noprint-secret" comment on the same line.
  Or: ~/.claude/state/hook-overrides.json
  {"hook":"secret-print","expires":"<ISO-UTC>","reason":"...","created_by":"you","created_at":"<ISO-UTC>"}
EOF
    exit 2
fi
exit 0
