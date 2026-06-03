# The TRIO Review Pattern

> Three agents, run in parallel, before anything ships.

## The problem

A single AI pass misses things. It is confident, fast, and blind to its own gaps -
especially security issues and mistakes it has made before in the same codebase.

## The pattern

On every new piece of code, config, workflow, or integration, dispatch three agents
**at the same time** (not sequentially - they are independent):

| Agent | Job | Why it's separate |
|---|---|---|
| `memory-keeper` | Reads past lessons + the team's hard rules BEFORE the build | History the other two don't have |
| `code-reviewer` | Quality, correctness, edge cases | Present-tense code quality |
| `security-reviewer` | Secrets, injection, auth, tenant isolation, OWASP | A different threat lens |

The key insight: **`memory-keeper` runs first or in parallel, not after.** It feeds
historical wisdom INTO the build, so you don't re-make a mistake the review would
later catch. Reviewing after the fact is slower than not making the mistake.

## Escalation (PENTA)

For system-critical or public-facing work, expand to five:
add a `threat-modeller` (maps attack surfaces before the hunt) and an
`adversarial-prober` (tries to break it like a curious/hostile user).

## How to wire it

A `UserPromptSubmit` keyword router detects "build / implement / new code / workflow"
and reminds the main loop to fan out. In Claude Code, dispatch all three in a single
message with multiple tool uses so they run concurrently.

```
Build something new?
  -> memory-keeper + code-reviewer + security-reviewer (parallel)
  -> fix CRITICAL/HIGH findings
  -> if large changes after fix, re-run the review
```

## Why parallel matters

If you run them in sequence you pay the sum of their latencies and the fast ones sit
idle. In parallel, wall-clock is the slowest single agent. With independent lenses
there is no reason to serialize.

See [`../rules/mandatory-bug-expert.md`](../rules/mandatory-bug-expert.md) for the
full rule, severity model, and exceptions.
