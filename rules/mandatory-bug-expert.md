<!-- Generic best-practice rule. Adapt paths and project names to your setup. -->
---
name: Mandatory Bug Expert
description: HARD RULE. Always run a bug-expert agent when new things are built. Applies to ALL domains.
alwaysApply: true
keywords: [bug, review, code, new feature, build, system, website, workflow, message, email]
---

# MANDATORY BUG EXPERT (HARD RULE)

**Principle:** Be extra careful. Everything new is reviewed by an EXPERT bug-stack BEFORE delivery. Goal: 80%+ of bugs found in the FIRST pass (vs a historical ~40%).

## TRIO -> PENTA

Default to a TRIO (3 agents) for normal code, and escalate to a PENTA (5 agents) for system-critical code:

1. `threat-modeller` - maps attack surfaces BEFORE the bug hunt
2. `code-reviewer` - static review
3. `security-reviewer` - defensive OWASP review
4. `adversarial-prober` - offensive attack mentality
5. `e2e-flow-tester` - live end-to-end test in a real browser

Optionally add a `regression-hunter` in parallel when many past lessons exist, and a `memory-keeper` afterwards to correlate against historical findings.

---

## The rule

**When something NEW is built (code, system, website, workflow, SQL, config) -> ALWAYS run a bug-expert agent.**

No exceptions. "Building new things" is interpreted broadly:
- New code (Python, JS, TS, SQL, shell, etc.)
- New workflows or large workflow changes
- New website code (HTML/CSS/JS, animation libraries)
- New database schemas or migrations
- New messages to be sent (email, DM, campaigns, contracts)
- New system configuration (nginx, docker, systemd)
- New AI prompts that run automatically
- New integrations against external APIs

---

## Which agents count as a "bug-expert"

Pick the right agent for the domain. Several can run in parallel:

| Domain | Primary agent | Secondary (parallel) |
|---|---|---|
| Code (any language) | `code-reviewer` | `security-reviewer` |
| Auth, sessions, secrets, privacy | `security-reviewer` | `code-reviewer` |
| SQL against customer data | `multitenant-debugger` | `security-reviewer` |
| Workflow automation | `workflow-expert` | `code-reviewer` |
| AI / LLM prompts | `prompt-engineer` | `llm-expert` |
| External API calls | `api-expert` | `security-reviewer` |
| Website / HTML | `web-designer` | `code-reviewer` |
| Server/docker/nginx | `system-expert` | `security-reviewer` |
| Database | `postgres-pro` | `multitenant-debugger` |

**Default when unsure:** `code-reviewer` + `security-reviewer` in parallel.

---

## When in the flow

1. **After** new code/text/workflow is written
2. **Before** it is deployed, sent, or shipped to production
3. **Not** during brainstorm/planning, only once something concrete exists to review

For iterative work on large systems: run after EVERY sub-delivery, not just at the end.

---

## Review format

The bug-expert reports findings by severity:
1. **CRITICAL** - blocks delivery, must be fixed
2. **HIGH** - should be fixed before production
3. **MEDIUM** - fix soon but not blocking
4. **LOW** - nice-to-have

On CRITICAL or HIGH: STOP, fix, re-run the review.

---

## Parallel execution

When the task is complex or spans multiple domains, run several agents at once:

```
memory-keeper + code-reviewer + security-reviewer   (DEFAULT TRIO for all new code)
memory-keeper + workflow-expert + code-reviewer + security-reviewer
memory-keeper + postgres-pro + security-reviewer    (database schema)
memory-keeper + web-designer + security-reviewer    (public website)
memory-keeper + prompt-engineer + llm-expert        (production AI prompt)
```

**Memory-keeper runs first (or in parallel)** to pull historical wisdom so the same mistakes are not repeated.

### Lock shared artifacts during review

When a bug-review runs on a specific artifact (code PR, workflow, doc), claim a lock on it so two sessions do not review the same thing in parallel.

---

## How to apply this

For every new implementation (code, workflow, message, etc.):

1. Is something NEW built or changed? -> run a bug-expert
2. Which domain? -> pick a primary + secondary agent
3. Run in parallel where possible
4. Report findings with severity
5. Fix CRITICAL + HIGH before moving on
6. On larger changes after a fix -> re-run the review

---

## Exceptions (very narrow)

1. **Trivial** - a one-line fix, typo, version bump in a README
2. **Read-only** - Read/Grep/Glob with no change
3. **The user says explicitly:** "skip the review, I just want to see it"
4. **Reuse of already-reviewed code** - copied without change

When in doubt: RUN THE AGENT. It is never wrong to be extra careful.
