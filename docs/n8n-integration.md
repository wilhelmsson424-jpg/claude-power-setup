<!--
NOTE: These are generic n8n lessons distilled from running n8n in production
with Claude Code as the design/debug partner. They are deliberately
context-free. Adapt every example to your own setup (node versions, table
names, credential names, and infra all differ). Verify current behavior
against your installed n8n version before relying on any single item.
-->

# Pairing Claude Code with n8n

Claude Code and n8n are a strong pairing because they split the work along
their strengths. Claude is good at designing a workflow, reasoning about edge
cases, reading execution data, and debugging silent failures. n8n is good at
executing that workflow on a schedule or webhook, holding credentials, and
running for months without supervision. You think and design in Claude, then
let n8n run it.

The n8n MCP server is what makes this practical: Claude can read a live
workflow, patch a single node, validate the result, and inspect executions
without you copy-pasting JSON back and forth.

## The MCP-first workflow

When Claude touches an n8n workflow, the tools should be used in a fixed order.
Each step exists to prevent a specific class of mistake.

1. `tools_documentation` (or `get_node`) - check the current node syntax and
   parameter shape before writing anything. Node parameters drift between
   versions, and your training data may be stale. Verify, do not assume.
2. `get_workflow` - read the live workflow before changing it. You are editing
   a running system; never patch blind.
3. `update_partial_workflow` - apply a surgical change to one node or one
   connection.
4. `validate_workflow` - validate after every change, before publishing.

### Why partial update beats a raw SSH PUT (or full overwrite)

A full overwrite (pushing the entire workflow JSON, whether through an SSH PUT
to the database or a full-workflow update) replaces everything. That means:

- You can silently clobber a node someone else just changed, because you are
  writing the whole document, not a diff.
- A single typo in an unrelated node breaks the entire workflow.
- You usually skip the version-history row that n8n writes on a proper update,
  so you lose the audit trail and the ability to roll back.
- Direct database writes bypass n8n's own consistency checks entirely.

A partial update only touches the node or connection you name. It is a diff,
not a rewrite. It creates a proper history entry, it is far less likely to
corrupt unrelated state, and it leaves a clean trail of what changed and when.
Reserve full overwrites and direct DB writes for the rare case where the
partial-update API cannot express the change, and re-sync history afterward.

### Publishing is a separate step

A partial update edits the draft, not the live version. To push a change into
production you must deactivate and reactivate the workflow. This also re-registers
webhooks and schedule triggers. After publishing, confirm the active version
id matches the version id you just wrote, otherwise production is still running
the old logic.

## Hard-won gotchas

Each of these cost real debugging time. They are written as
**Symptom -> Cause -> Fix**. Versions and defaults change, so treat them as
patterns to watch for rather than eternal truths.

### 1. Code node v1 to v2 migration

**Symptom:** A Code node that worked for months suddenly behaves differently or
breaks after an n8n upgrade.
**Cause:** v1 Code nodes run in the main process; v2 runs in an isolated task
runner where `require()` is allowlisted (not global) and HTTP helpers are
restricted unless configured. v1 is legacy and will eventually be removed.
**Fix:** Standardize on Code node typeVersion 2 now and test sandbox
assumptions, rather than waiting for an upgrade to break v1 nodes.

### 2. `fetch` does not exist in the Code node sandbox

**Symptom:** A Code node crashes with `fetch is not defined`, often silently
inside a nightly job.
**Cause:** The Code node sandbox has no global `fetch()`.
**Fix:** Use the built-in HTTP helper (`this.helpers.httpRequest({...})`).
Read the response as `statusCode`, `body`, `headers`, not `status`/`ok`/`text()`.

### 3. Environment variables are blocked in nodes, not just Code nodes

**Symptom:** An IF node (or other node) crashes with an "access to env vars
denied" expression error.
**Cause:** When env access is blocked, the block applies to expressions in
many node types, not only Code nodes. HTTP Request and some app nodes that run
in the main process are exceptions.
**Fix:** Do not read secrets via env in sandboxed expressions. Resolve the
value in a node that runs in the main process, or store it as a credential and
reference the credential.

### 4. The comma-split queryReplacement trap in SQL nodes

**Symptom:** A multi-parameter SQL UPDATE/INSERT fails with "Variable $N out of
range. Parameters array length: M" even though the parameter count looks right.
**Cause:** The query-replacement field is parsed by splitting on commas between
expression blocks. If any evaluated value contains a comma (a serialized JSON
object always does, and so does free text like "Table 27, downtown"), the
result string is split again and the parameter count no longer matches the query.
**Fix:** Build all parameters in a preceding Code node so each value is a clean
scalar string with no embedded commas, then reference those fields. Or use the
node's structured insert/update operation with column mapping instead of a raw
parameterized query, which binds fields correctly.

### 5. The Gmail (and similar app) node does not propagate input fields

**Symptom:** A Code node after a mail node reads a field that existed upstream
and gets `undefined`, which silently falls back to an empty string.
**Cause:** The mail node replaces the item JSON with the API response (id,
threadId, subject, etc.) and does not carry forward the upstream input fields.
**Fix:** Reference the originating node explicitly
(`$('NodeName').item.json.field`) instead of relying on `$input`. Prefer a
direct parent with a 1-to-1 mapping; batch loops several nodes up can return
`undefined` for cross-node references.

### 6. An auth-header credential must match the token the caller sends

**Symptom:** A call to a protected webhook returns 403, and no execution row
appears on the target workflow at all.
**Cause:** The webhook enforces a header-auth credential before the workflow
runs. If the token the caller sends (often from an env var) was rotated on one
side but not the other, every call fails before any node executes, so it is
invisible in the execution list.
**Fix:** Keep the caller's token and the webhook credential in sync; rotate both
together. To diagnose, the absence of any execution row in the time window means
auth failed before the workflow started.

### 7. Schedule trigger goes stale after a node update

**Symptom:** After patching a node on a scheduled workflow, the workflow stays
active and workers look healthy, but no new executions appear.
**Cause:** The schedule trigger is registered in the worker when the workflow
is activated. A partial update writes the new body to the database but does not
notify the worker to reload the trigger state, so the cron tick is silently
skipped.
**Fix:** After any node patch on a workflow with a schedule trigger, always run
a deactivate then activate cycle to re-register the trigger.

### 8. IF node strict type validation crashes on numeric ids

**Symptom:** An IF node crashes with "Wrong type: '401' is a number but was
expecting a string".
**Cause:** SQL nodes return integer ids as JavaScript numbers. An IF node with
strict type validation plus a string operator (notEmpty, exists, contains)
rejects a numeric input.
**Fix:** Wrap the value with `String(...)`, or use a number operator, or
loosen type validation (but loosening can hide other silent failures, so prefer
the explicit cast).

### 9. The always-output-data trap on empty result sets

**Symptom:** A downstream IF check on `length > 0` is always true even when a
query returned zero rows, and the pipeline runs work it should have skipped.
**Cause:** A node with always-output-data enabled emits one empty item on zero
rows, so a length check sees one item.
**Fix:** Disable always-output-data, or test a specific field's existence
instead of item count. The same applies after an UPDATE ... RETURNING that
matched zero rows: add a filter that drops items without the expected id so the
pipeline stops cleanly instead of burning downstream API calls.

### 10. Renaming a form field causes silent data loss

**Symptom:** A submission returns HTTP 200 with a success message, but zero
records are saved, sometimes for days.
**Cause:** The frontend renamed a field (for example `name` split into
`firstName` and `lastName`) without updating the workflow's sanitize/set node.
The expected field becomes `undefined`, sanitizes to empty, fails validation,
and the workflow follows its error branch, which still returns success to the
caller.
**Fix:** Keep field names in sync between frontend and workflow, write the raw
payload to an audit table before sanitizing, and add a daily health check that
alerts when zero records arrive in 24 hours. A success response is not proof
that data was stored.

### 11. Webhook paths are literal, not dynamic

**Symptom:** A webhook configured with a path segment like
`/resource/:action` does not match `/resource/create`.
**Cause:** n8n treats the path as a literal string; it does not parse
path-parameter segments.
**Fix:** Use one fixed path per endpoint (one workflow per endpoint is the
cleanest), or pass the variable part in the body or query string.

### 12. Prompt-injection filters must cover role and instruction overrides

**Symptom:** A thin regex filter blocks "ignore previous instructions" but lets
through "from now on your role is ..." or "system: you are now ...".
**Cause:** The filter only matched one phrasing of an injection attempt.
**Fix:** Cover the common variants: ignore/disregard prior instructions, "from
now on", role reassignment, and `system:`/`assistant:`/`developer:` prefixes.
Sanitize user input before it reaches any LLM node, and re-test the filter
whenever you add an AI step.

### 13. Webhooks need a request boundary you control

**Symptom:** A public webhook accepts unauthenticated or cross-tenant requests
and writes data it should not.
**Cause:** The webhook trusts whatever arrives, and tenant scoping (filtering
by a tenant id) is missing from the queries it triggers.
**Fix:** Authenticate the webhook (header credential), validate the payload,
and make every database operation tenant-scoped. Never let an externally
reachable endpoint run an unscoped query.

## Run a review pass before you deploy

Treat a new or substantially changed workflow like new code, because it is.
Before activating it in production, run your review agents over it: one pass for
correctness and node-config mistakes, one for security (auth, secrets, tenant
isolation, injection surfaces). The same discipline you apply to a pull request
applies to a workflow. Most of the gotchas above are exactly the kind of thing
a focused review catches before it reaches production, not after it has been
silently dropping data for a week.
