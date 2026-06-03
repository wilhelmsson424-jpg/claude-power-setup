# Claude Code Power Setup

A production-grade configuration for [Claude Code](https://claude.com/claude-code):
a multi-agent review pipeline, a scalable file-based memory system, self-healing
autonomy rules, a defense-in-depth hook layer, and patterns for pairing Claude with
no-code automation (n8n).

This is a **curated, sanitized** extract of a real, daily-driven setup - generalized
so you can adapt it to your own project. Nothing here is project-specific or contains
secrets.

> Built and maintained by [Rickard Wilhelmsson](https://github.com/wilhelmsson424-jpg).
> 24 years in hospitality, building AI/automation. Available for talks and consulting.

---

## Why this is different

Most shared Claude setups are a `settings.json` and a few prompts. This one models a
**team of agents with guardrails and a memory** - the things that actually make an AI
coding assistant reliable over months of use.

### 1. Scalable memory system (`memory-system/`)
A tiny index + many topic files + semantic search + a keyword router. Scales to
1000+ facts without bloating context. A hook hard-caps the index file so it can never
grow into a context hog. See [`memory-system/STRUCTURE.md`](memory-system/STRUCTURE.md).

### 2. Three-step review (TRIO) before any delivery (`rules/mandatory-bug-expert.md`)
Every new piece of code/config runs three agents **in parallel** before it ships:
- `memory-keeper` - pulls historical lessons so you don't repeat past mistakes
- `code-reviewer` - quality and correctness
- `security-reviewer` - OWASP, secrets, injection, multi-tenant isolation

### 3. Self-learning loop (`rules/`, `agents/memory-keeper.md`)
Solved problems become written lessons; the memory-keeper reads them back before the
next build. Mistakes compound into wisdom instead of repeating.

### 4. Defense-in-depth hooks (`hooks/`)
A `PreToolUse` hook layer that blocks classes of mistakes structurally:
destructive commands, secrets printed to stdout, `/proc/<pid>/environ` dumps,
em-dashes/emojis in public output, and runaway index-file growth.

### 5. Claude + n8n pairing (`docs/n8n-integration.md`)
Claude designs and debugs; n8n executes and schedules. An MCP-first workflow plus
13 hard-won gotchas (Symptom -> Cause -> Fix) from running n8n in production.

### Bonus: trusted-boundary credential model (`rules/trusted-boundary-policy.md`)
A 4-level model for where secrets are allowed to exist - the philosophy behind the
hook layer, not just the code.

---

## Contents

| Folder | What's inside |
|---|---|
| `agents/` | 7 generic subagents: code-reviewer, security-reviewer, architect, planner, tdd-guide, memory-keeper, refactor-cleaner |
| `hooks/` | 7 `PreToolUse` guard hooks (danger-guard, secret-print-guard, proc-environ-blocker, emoji/dash-blocker, memory-radlimit-guard, aao-warn) |
| `rules/` | 6 best-practice rule files (coding-style, self-healing, memory-management, pro-tier, trusted-boundary, mandatory-bug-expert / TRIO) |
| `commands/` | 2 slash commands (ultra-think, release-notes) |
| `memory-system/` | The memory architecture + a blank index template |
| `docs/` | Deep-dive writeups: [TRIO review](docs/trio-review.md), [n8n integration](docs/n8n-integration.md) |

---

## Install

These files map onto your `~/.claude/` directory. Copy what you want:

```bash
# Agents and rules (markdown - drop-in)
cp agents/*.md   ~/.claude/agents/
cp rules/*.md    ~/.claude/rules/
cp commands/*.md ~/.claude/commands/

# Hooks (shell - register them in settings.json under "hooks")
cp hooks/*.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/*.sh
```

Then wire the hooks in `~/.claude/settings.json` (each hook documents its event and
exit-code contract at the top of the file). Adapt any paths and project names to your
own setup - every file carries an "adapt this" header.

> Hooks are sanitized to be generic. Read each one before enabling it; some block
> behaviors (like em-dashes in files) that you may or may not want.

---

## A note on safety

This repo deliberately contains **no secrets, no server details, no business data**.
The included hooks and the trusted-boundary rule exist precisely because leaking those
things is the #1 risk when sharing a Claude setup. If you fork your own real config,
run a secret scan before every push.

## License

MIT - see [LICENSE](LICENSE). Use freely, adapt freely.
