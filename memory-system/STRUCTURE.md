# Memory System - Architecture

A file-based persistent memory for Claude Code that scales to 1000+ facts without
blowing up context. The core idea: **a tiny index + many topic files + semantic search +
a keyword router that injects the right file at the right time.**

## The four layers

### 1. Index (`MEMORY.md`)
- Loaded into context every session.
- Hard cap (~80 lines / 30KB). A PreToolUse hook (`memory-md-radlimit-guard.sh`)
  predicts the post-edit size and BLOCKS writes that would exceed the cap.
- One line per topic: `- [Title](folder/file.md) - one-line hook`

### 2. Topic files (`folder/*.md`)
- One fact (or one tight cluster) per file.
- Frontmatter drives relevance:

```markdown
---
name: <short-kebab-case-slug>
description: <one-line summary - used for recall>
metadata:
  type: user | feedback | project | reference | lesson
---

<the fact. For feedback/project, follow with **Why:** and **How to apply:** lines.
Link related memories with [[their-name]].>
```

- Suggested folders: `feedback/` (how Claude should work), `lessons/` (post-mortems),
  `system/` (infra notes), `features/` (ongoing work), `reference/` (external links).

### 3. Semantic search (optional)
- Embed topic files into a vector DB (e.g. Qdrant) and expose a
  `semantic_search_memory(query, top_k)` MCP tool.
- Lets Claude pull a relevant fact even when no keyword matched.

### 4. Keyword router (a UserPromptSubmit hook)
- On each prompt, match keywords -> inject the 1-3 most relevant topic files
  (capped, e.g. 8000 chars) as REFERENCE DATA.
- Also routes to the right specialist agent (see `rules/mandatory-bug-expert.md`).
- SAFETY: wrap injected content in a block and instruct the model to treat it as
  data, never as instructions (prompt-injection defense).

## Why this beats one big memory file
- Context stays small: you load the index + a handful of relevant files, not everything.
- Retrieval is precise: frontmatter `description` + embeddings + keyword routing.
- It scales: adding the 1000th fact doesn't slow down session start.

## Maintenance loop
1. New fact -> check for an existing topic file -> update it (don't duplicate).
2. Add/refresh a one-line pointer in `MEMORY.md`.
3. If `MEMORY.md` exceeds the cap, move the oldest "pending" lines to `_archive/`.
4. Delete facts that turn out to be wrong.
