<!-- Generic best-practice rule. Adapt paths and project names to your setup. -->
---
name: Self-Healing Autonomy
description: Diagnose, fix, verify, report instead of asking the user. Use available credentials, MCP, and SSH to solve problems autonomously. Load when hitting errors, timeouts, broken integrations, or feeling stuck.
keywords: [problem, error, manual, retry, timeout, broken, debug, diagnose, fix, escalate, self-healing, autonomous]
---

# Self-Healing & Autonomy (CRITICAL RULE)

## Principle: Solve problems YOURSELF first

When you hit a problem (error, timeout, missing data, broken integration):

1. **Diagnose** - read logs, run commands, investigate
2. **Fix** - resolve it yourself with the tools available
3. **Verify** - confirm the fix works
4. **Report** - briefly explain what happened

**NEVER** as a first step:
- "Can you check manually?"
- "You need to do X yourself"
- "I can't do this"
- Giving up after one attempt

**ALWAYS** as a first step:
- Try a different approach
- Use an alternative tool (e.g. one browser driver vs another)
- SSH into the server and investigate
- Read logs, check credentials, test endpoints

## Self-healing tool chain

| Problem | Step 1 | Step 2 | Step 3 |
|---------|--------|--------|--------|
| Browser needed | Primary browser driver | Backup browser driver | SSH + curl |
| API error | Test endpoint | Check credentials | Read server logs |
| Workflow broken | Fetch workflow via MCP | Validate | Fix + test |
| Server down | Check service status | Read container logs | Restart via SSH |
| Credentials expired | Read from secret store | Rotate if possible | Notify the user |

## Automation > Manual

- You HAVE the credentials (SSH, API, DB, MCP servers)
- You HAVE browser control
- You HAVE server access (SSH, containers, database)
- **Use it.** The user does not want to do things manually.

## Escalate ONLY when

1. Something requires physical access (USB, hardware)
2. Payment/contract is required (human decision)
3. You have tried 3+ approaches and all failed
4. A destructive action is needed (delete data, force push)
