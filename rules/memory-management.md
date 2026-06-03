<!-- Generic best-practice rule. Adapt paths and project names to your setup. -->
---
name: Memory Management
description: MEMORY.md is a compact index, topic-files hold the detail. Load when adding/updating memory, lessons learned, or organizing topic-files.
paths: ["**/memory/**", "**/MEMORY.md", "**/.claude/projects/**"]
keywords: [memory, MEMORY.md, topic-file, forget, lesson, index, knowledge graph]
---

# Memory Management Rule

## Structure: Index + Topic-files

**MEMORY.md** = compact index, max ~80 lines
- Only short 1-2 line summaries per topic
- Point to a topic-file for detail
- System status, quick references, critical rules

**Topic-files** = all detailed information
- One file per domain: `server-architecture.md`, `workflows.md`, `patterns.md`, etc.
- IDs, code snippets, long lessons go here, NOT in MEMORY.md

## Rules

1. **New lesson** -> check if a topic-file exists -> add it there -> one line in MEMORY.md if relevant
2. **MEMORY.md > 80 lines** -> move sections to topic-files immediately
3. **Never duplicate** info between MEMORY.md and topic-files
4. **Search topic-files** with Grep at session start when something specific is needed

## Example

```
# MEMORY.md (correct)
## Publishing
Social publishing works. Details: `publishing-fixes.md`

# publishing-fixes.md (correct)
## API credential
- authentication: none + queryParam key=$env.API_KEY
- Strip markdown before JSON.parse: text.replace(/^```json\s*/i,'')...
```
