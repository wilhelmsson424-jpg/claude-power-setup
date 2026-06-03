#!/usr/bin/env bash
# Generic Claude Code hook. Adapt paths to your setup. See README.
#
# proc-environ-blocker.sh - PreToolUse: Bash + ssh_exec
# Blocks dumping /proc/PID/environ and cmdline, and bare `env`/`printenv` dumps
# via docker/kubectl/ssh exec, which can leak secrets in environment variables
# into the tool-result and transcript.
set -uo pipefail
umask 077

[ -f "$HOME/.claude/state/HOOKS_DISABLED" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0
# (optional: add your own logging here)

INPUT=$(timeout 1 cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0

TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

CMD=""
case "$TOOL" in
    Bash)
        CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
        ;;
    mcp__server-ssh__ssh_exec)
        CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
        ;;
    *) exit 0 ;;
esac

[ -z "$CMD" ] && exit 0

# Dump patterns against /proc/PID/environ or /proc/PID/cmdline
ENVIRON_DUMP='\b(cat|head|tail|less|more|strings|xxd|hexdump|od|awk|sed|grep|tr|xargs)\b[^|;]{0,200}/proc/[0-9*][^[:space:]]*/(environ|cmdline)'

# Reverse: redirect FROM environ into a tool
REDIRECT_DUMP='</proc/[0-9*][^[:space:]]*/(environ|cmdline)'

# docker/k8s/ssh exec ... env piped/grepped with secret keywords
EXEC_ENV_LEAK='(docker[[:space:]]+exec|kubectl[[:space:]]+exec|ssh[[:space:]][^|;]{0,100})[[:space:]][^|;]{0,300}\b(env|printenv|set)\b[[:space:]]*(\||[^a-zA-Z]|$)'

# BARE exec env without a secret keyword (still dumps ALL env vars)
EXEC_ENV_BARE='(docker[[:space:]]+exec[[:space:]]+[a-zA-Z0-9_-]+([[:space:]]+--?[a-zA-Z]+)*[[:space:]]+(env|printenv)([[:space:]]|$)|kubectl[[:space:]]+exec[[:space:]]+[^[:space:]]+[[:space:]]+--[[:space:]]+(env|printenv)([[:space:]]|$)|ssh[[:space:]]+[^[:space:]]+[[:space:]]+(env|printenv)([[:space:]]|$))'

# Safe-filter exception: env piped to cut -d= -f1 shows only KEYS, no values
SAFE_FILTER_PATTERN='(env|printenv)[[:space:]]*\|[[:space:]]*cut[[:space:]]+-d=([[:space:]]+-f1)?([[:space:]]|$|\||;|&&)'

# Secret keywords that trigger a block when combined with an exec env dump
SECRET_KEYWORDS='(token|secret|password|api[_-]?key|\bapi\b|client[_-]?secret|webhook[_-]?secret|bearer|auth|credential|key)'

LEAK_TYPE=""
SAFE_FILTER=N
echo "$CMD" | grep -qE "$SAFE_FILTER_PATTERN" && SAFE_FILTER=Y

if echo "$CMD" | grep -qE "$ENVIRON_DUMP" || echo "$CMD" | grep -qE "$REDIRECT_DUMP"; then
    LEAK_TYPE="proc-environ"
elif echo "$CMD" | grep -qiE "$EXEC_ENV_LEAK" && echo "$CMD" | grep -qiE "$SECRET_KEYWORDS" && [ "$SAFE_FILTER" = "N" ]; then
    LEAK_TYPE="exec-env-dump"
elif echo "$CMD" | grep -qE "$EXEC_ENV_BARE" && [ "$SAFE_FILTER" = "N" ]; then
    LEAK_TYPE="bare-exec-env"
fi

if [ -n "$LEAK_TYPE" ]; then
    cat <<HOOKEOF >&2
BLOCKED by proc-environ-blocker.sh (type: $LEAK_TYPE)

You are trying to dump env vars that may contain secrets:
  Command: $(echo "$CMD" | head -c 200)

This can expose credentials (TOKEN, API_KEY, WEBHOOK_SECRET, etc.)
in cleartext to the tool-result and the Claude Code transcript.

ALLOWED tools for inspection (metadata only):
  ls /proc/PID/environ              # existence + perms only
  wc -c /proc/PID/environ           # byte count
  stat /proc/PID/environ            # file metadata

NEVER (leaks to transcript):
  cat /proc/*/environ
  strings /proc/*/environ
  docker exec CTR env
  docker exec CTR sh -c 'env | grep TOKEN'
  kubectl exec POD -- env
  ssh server 'env | grep'

Alternative: ask the process to report only KEYS (not values):
  docker exec CTR sh -c 'env | cut -d= -f1 | sort'             # names only
  docker exec CTR sh -c '[ -n "\$MY_VAR" ] && echo set'        # existence
  docker inspect CTR --format '{{range .Config.Env}}{{println .}}{{end}}' | cut -d= -f1

OVERRIDE: add to ~/.claude/state/hook-overrides.json:
  {"hook":"proc-environ","expires":"<ISO-UTC>","reason":"...","created_by":"you","created_at":"<ISO-UTC>"}
HOOKEOF
    exit 1
fi

exit 0
