#!/usr/bin/env bash
# Generic Claude Code hook. Adapt paths to your setup. See README.
#
# danger-guard.sh - blocks destructive commands (PreToolUse: Bash).
# Covers:
#   - rm -rf and --recursive --force, find -delete, shred, truncate, dd of=/dev
#   - git push --force, -f, and refspec +branch (force via plus)
#   - curl/wget pipe to any interpreter (bash/sh/zsh/fish/dash/ksh/python/node/perl/ruby/php/env)
#   - DROP DATABASE/TABLE/SCHEMA/INDEX, TRUNCATE TABLE, DELETE FROM without WHERE

set -euo pipefail

# (optional: add your own logging here)
IFS=$'\n\t'
LC_ALL=C.UTF-8

# Fail-open on missing dependencies
command -v jq >/dev/null 2>&1 || exit 0

input=$(timeout 4 head -c 1048576) || exit 0
command=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || true)

if [ -z "$command" ]; then
    exit 0
fi

block() {
    printf '{"decision":"block","reason":"%s"}\n' "$1"
    exit 2
}

# --- 1. Destructive file deletion ---
if printf '%s' "$command" | grep -qE '\brm\b[[:space:]]+(-[a-zA-Z]*[rR][a-zA-Z]*[[:space:]]+|--recursive[[:space:]]+)'; then
    if printf '%s' "$command" | grep -qE '(/|~|\$HOME|\$\{HOME\}|\.\./|/home|/root|/var|/etc|/mnt|/usr|/opt|/srv|/tmp|/dev|/sys|/proc|/boot|/lib|/sbin|/bin)'; then
        block "Blocked: rm -r/--recursive on a system directory. Specify an exact path or confirm manually."
    fi
fi

if printf '%s' "$command" | grep -qE '\brm\b[[:space:]]+(-[a-zA-Z]*[fF][a-zA-Z]*[[:space:]]+|--force[[:space:]]+)' \
   && ! printf '%s' "$command" | grep -qE '\brm\b[[:space:]]+-[a-zA-Z]*[rR]'; then
    if printf '%s' "$command" | grep -qE '\brm\b[[:space:]]+(-[fF][[:space:]]+|--force[[:space:]]+)[^|;&]*[*?]'; then
        block "Blocked: rm -f with wildcard (* or ?). Specify an exact path."
    fi
    if printf '%s' "$command" | grep -qE '\brm\b[[:space:]]+(-[fF][[:space:]]+|--force[[:space:]]+)(/|/home|/etc|/var|/usr|/root|/boot|/lib|/sbin|/bin|/opt|/srv|/dev|/sys|/proc)([[:space:]]|$|;|&|\|)'; then
        block "Blocked: rm -f against a system root. Specify a path under a subdirectory."
    fi
fi

if printf '%s' "$command" | grep -qE '\brm\b[[:space:]]+(-[a-zA-Z]*[rRfF][a-zA-Z]*[[:space:]]+|--recursive[[:space:]]+)(\*|\.|\.\.)'; then
    block "Blocked: rm -rf on * or . or .. is too broad. Specify exact files."
fi

if printf '%s' "$command" | grep -qE '\b(find|fd)\b[[:space:]].*-delete\b'; then
    if printf '%s' "$command" | grep -qE '\bfind\b[[:space:]]+(/|/home|/etc|/var|/usr|/root|~)[[:space:]]'; then
        block "Blocked: find -delete against a broad root path. Specify a subdirectory."
    fi
    if ! printf '%s' "$command" | grep -qE '\-(maxdepth|name|iname|path|type|mtime|newer|size)\b'; then
        block "Blocked: find -delete without a -name/-type/-maxdepth filter. Add a filter or use a specific rm."
    fi
fi

if printf '%s' "$command" | grep -qE '\bshred\b.*(-u|--remove)'; then
    block "Blocked: shred -u deletes files irrecoverably. Confirm manually."
fi

if printf '%s' "$command" | grep -qE '\btruncate\b[[:space:]]+-s[[:space:]]*0\b'; then
    block "Blocked: truncate -s 0 empties files. Use > /dev/null > file if intentional, or confirm manually."
fi

if printf '%s' "$command" | grep -qE '\bdd\b.*of=(/dev/sd|/dev/nvme|/dev/hd|/dev/disk|/dev/zero|/dev/null[[:space:]]+of=)'; then
    block "Blocked: dd writes to a block device and can destroy a disk. Confirm manually if intentional."
fi

if printf '%s' "$command" | grep -qE '\bmkfs(\.[a-z0-9]+)?\b'; then
    block "Blocked: mkfs formats a filesystem. Confirm manually."
fi

# --- 2. Git destructive ---
if printf '%s' "$command" | grep -qE '\bgit[[:space:]]+push\b.*(--force|--force-with-lease|-f[[:space:]])'; then
    if printf '%s' "$command" | grep -qE '\b(main|master|production|prod|release)\b'; then
        block "Blocked: git push --force/-f to main/master/production/release. Use a feature branch or confirm manually."
    fi
fi

if printf '%s' "$command" | grep -qE '\bgit[[:space:]]+push\b[[:space:]]+\S+[[:space:]]+\+(main|master|production|prod|release|HEAD)'; then
    block "Blocked: git push refspec +branch (force via plus) to a protected branch. Confirm manually."
fi

if printf '%s' "$command" | grep -qE '\bgit[[:space:]]+reset[[:space:]]+--hard[[:space:]]+(origin|upstream)/(main|master|production|prod)'; then
    block "Blocked: git reset --hard against remote main/master can lose local commits. Confirm manually."
fi

# --- 3. Pipe-to-interpreter (supply chain) ---
if printf '%s' "$command" | grep -qE '\b(curl|wget|fetch|http)\b[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(bash|sh|zsh|fish|dash|ksh|python[23]?|node|perl|ruby|php|env|tee[[:space:]]*\(.*sh)\b'; then
    block "Blocked: pipe from curl/wget to an interpreter (supply chain attack). Download the file separately and review before running."
fi

if printf '%s' "$command" | grep -qE '\btee[[:space:]]+>\([[:space:]]*(bash|sh|zsh)'; then
    block "Blocked: tee >(bash) is a supply chain risk. Confirm manually."
fi

# --- 4. SQL destructive ---
if printf '%s' "$command" | grep -qiE '\bDROP[[:space:]]+(DATABASE|TABLE|SCHEMA|INDEX)\b'; then
    block "Blocked: DROP DATABASE/TABLE/SCHEMA/INDEX requires manual confirmation. Run directly in your SQL client if intentional."
fi

if printf '%s' "$command" | grep -qiE '\bTRUNCATE[[:space:]]+(TABLE[[:space:]]+)?\w+'; then
    block "Blocked: TRUNCATE TABLE removes all data. Confirm manually."
fi

if printf '%s' "$command" | grep -qiE '\bDELETE[[:space:]]+FROM[[:space:]]+\w+(\s+;|\s*$|"\s*$)' && \
   ! printf '%s' "$command" | grep -qiE '\bWHERE\b'; then
    block "Blocked: DELETE FROM without a WHERE clause. Add WHERE or confirm manually."
fi

# --- 5. Other destructive ---
if printf '%s' "$command" | grep -qE '\bchmod\b[[:space:]]+(-R[[:space:]]+)?777[[:space:]]'; then
    block "Blocked: chmod 777 makes files world-writable. Use 644/755/750 or confirm manually."
fi

if printf '%s' "$command" | grep -qE '\bchown\b.*root.*\b(/home|/var|/tmp|/etc/passwd|/etc/shadow)\b'; then
    block "Blocked: chown to root on system files. Confirm manually."
fi

exit 0
