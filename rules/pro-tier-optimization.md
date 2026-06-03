<!-- Generic best-practice rule. Adapt paths and project names to your setup. -->
---
name: Max Tier Strategy
description: Session/tool/agent strategy for high-tier plans. Full parallelization, no token-anxiety, /compact only near the context limit. Load when planning agent dispatch, parallel execution, or session management.
keywords: [tokens, cost, parallel, agent strategy, optimization, max tier, compact, clear, session]
---

# Max Tier Strategy

**Tier:** MAX - unlimited messages, large context window
**Strategy:** Use it fully. No artificial limits.

---

## 1. Session Strategy

**Target:** run sessions as long as needed, no message budgets

**Compaction:**
- /compact when context approaches the limit (technical need, not cost-saving)
- /clear only when the task is fully done + committed

---

## 2. Tool Strategy

**Everything allowed:**
- Read whole files when needed (no limit-restrictions unless the file is enormous)
- Grep without head_limit if you need all results
- Parallel tool calls, always

**Best practice (not cost-saving):**
- Read files once, then reference them
- Parallelize independent tool calls

---

## 3. Agent Strategy

**NO LIMITS:**
- Run all relevant agents per session
- Run them in parallel when independent
- Auto-trigger planning/architecture agents

**Parallel execution:**
```
planner + workflow-expert       (plan + implement)
code-reviewer + security-reviewer (always after code)
tdd-guide + architect            (feature design)
multiple domain specialists
```

---

## 4. Shared Context

Use for cross-session state and CLI-to-browser collaboration, not for token-saving.

---

## 5. Compaction

**/compact:**
- Context near limit -> /compact
- Topic change (optional)

**/clear:**
- Task done + committed
- Project switch

---

## Summary

**Max Tier Formula:** Full agents + parallel execution + unlimited sessions

**Golden Rules:**
1. Run the right agent for the right task, always
2. Parallelize everything that can be parallelized
3. No token-hunger, focus on quality
4. /compact when needed (technical), not to save tokens
5. Commit often, clear when done

**Result:** maximum productivity without limits
