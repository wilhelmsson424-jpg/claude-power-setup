Check the latest updates for your project's critical dependencies

---

## What to check

Fetch the latest release notes / changelogs for [your dependencies].

For each dependency:

1. Determine the currently installed/running version (via its health check, CLI, or package manifest).
2. Search the web for that dependency's changelog around the next version, e.g. "[dependency] changelog [current version + 1]".
3. Pay special attention to deprecations and breaking API changes that affect your integration.

Example dependency categories you might track:

- Workflow/automation engine
- LLM / AI model APIs (note any model migration deadlines)
- Voice / TTS APIs
- Social / Graph APIs (important for app review)
- Vector database / search (watch for breaking API or collection-format changes)

---

## Filter for what affects your project

For each update, classify the impact:
- **Breaking change** - action required now
- **Deprecation** - plan a migration
- **New feature** - evaluate whether to adopt

---

## Present it briefly

```
RELEASE NOTES - [DATE]

BREAKING (action required):
- [if any]

DEPRECATIONS (plan):
- [if any]

NEW FEATURES (interesting):
- [up to 3 items]

Everything else: no action needed.
```
