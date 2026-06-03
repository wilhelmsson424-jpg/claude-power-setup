<!-- Generic best-practice rule. Adapt paths and project names to your setup. -->
# Trusted-Boundary Policy: structural credential handling

**Status:** PRODUCTION (created after two real secret-leak incidents: a `/proc/PID/environ` leak and a config-dump leak that exposed all env vars in cleartext).
**Principle:** Define which channels are "trusted" for credentials. Anything outside the trusted zone must NEVER see cleartext values.

---

## Trusted-boundaries (4 levels)

### LEVEL 1: Application runtime memory (TRUSTED)
Process RAM after a service has read a secret from the vault. Never serialized to disk or stdout.
- A workflow Code-node using an injected credential reference
- An app reading a secret from `process.env` at startup
- A decryption routine holding a data-encryption-key in a variable during a request

### LEVEL 2: Vault + encrypted transport (TRUSTED)
- A vault-get call with 2FA approval
- A "use-in-request" vault call (passes the secret server-side, never exposes it in the tool-result)
- HTTPS calls to an internal vault on localhost
- Symmetric decrypt directly inside a SQL query against the database

### LEVEL 3: Process metadata (UNTRUSTED, CAN LEAK)
- `/proc/PID/environ` (readable by any process with the same UID)
- `/proc/PID/cmdline` (even though args should not contain secrets)
- `docker inspect <container>` (shows env vars)
- `docker compose config` (dumps ALL env in cleartext)
- `kubectl describe pod` (shows env vars in Status)
- `ps auxe` (shows env per process)
- `env`, `printenv`, `set` in a shell when secrets are exported

### LEVEL 4: Transcript + logs + git (UNTRUSTED, PERMANENT LEAK)
- The assistant/agent transcript (may surface in context-compression or be readable by the provider)
- Shell history (`~/.bash_history`)
- Application logs (including stderr)
- Git commits + git history
- Screenshots in chat/email tools

---

## Hard rules

### 1. Never read LEVEL 3 from a shell
Use blocking hooks that reject `cat /proc/*/environ`, `cat /proc/*/cmdline`, redirects from environ, and `docker compose config` without an explicit sentinel.

Alternatives for debugging:
```bash
# RIGHT: verify a secret exists without reading the value
docker exec <ctr> sh -c '[ -n "$MY_VAR" ] && echo "set" || echo "missing"'

# RIGHT: get env-var NAMES (not values)
docker exec <ctr> sh -c 'env | cut -d= -f1' | sort

# WRONG: dump everything
docker exec <ctr> env
docker compose config
```

### 2. DB-adapter pattern instead of env-vars for long-lived tokens
A pattern proven to work:
- Tokens stored encrypted in a database table (symmetric encrypt with a master key)
- An adapter reads them via decrypt per call
- The master key lives in the vault, fetched at startup, only ever in RAM
- Tokens NEVER end up in process-env (protected from LEVEL 3 leakage)

Apply this to every service with long-lived tokens (OAuth refresh tokens, third-party API tokens, etc.).

### 3. Short-lived OK for secrets required at startup
Some secrets MUST be in env at container startup (encryption keys, database passwords). Accept this if:
- The container runs isolated (own namespace, not shared host-UID)
- The proc-environ blocker is active in the shell environment
- No interactive shells run in the container during production

### 4. Prefer non-echoing vault calls
A vault call that returns the cleartext value risks a tool-result leak. Prefer:
- A "use-in-request" call (server-side substitution, cleartext never in the tool-result)
- The DB-adapter pattern for long-lived tokens
- A direct vault-get + immediate use in the SAME command (do not store in a variable)

### 5. Rotation after a LEVEL 3 or LEVEL 4 leak
A rotated credential counts as "clean" only when:
1. The old key is revoked at the provider
2. The new key is written to the vault + an audit row exists
3. All services using it have reloaded (verified via healthcheck)
4. A 24h grace period has passed with no unexpected failed-auth

### 6. Encryption-key class (never-rotate-without-a-plan)
Some secrets decrypt historical data (master encryption keys, consent/HMAC secrets). Rotation requires:
- A dual-key period (old key kept for decrypt, new key for encrypt)
- A re-encrypt batch of all old data
- Verify 0 decryption-failures before deleting the old key
- If the incident is contained (e.g. transcript-only LEVEL 4 exposure), consider accepting it instead of rotating. Document the decision.

---

## Threat model

| Threat | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Process on same UID reads /proc/PID/environ | HIGH (blocker mitigates shell) | CRIT (all secrets) | Hook + DB-adapter |
| `docker compose config` dumped into transcript | MEDIUM | CRIT | config-dump blocker hook |
| Tool-result with an echoing vault call exposes cleartext | HIGH (every use) | CRIT | Migrate to use-in-request |
| Provider data breach leaks transcript | LOW | MEDIUM (old secrets) | Rotation routines + accept encryption-key class |
| Git commit with .env | MEDIUM | CRIT | .gitignore + pre-commit hook |
| Shell-history readout | LOW | HIGH | HISTFILE=/dev/null for sensitive sessions |

---

## Practical checklist (for every credential task)

- Am I using a LEVEL 2 channel (vault) for reading?
- Does my command trigger LEVEL 3 (proc/env/docker)? -> STOP
- Does the value land in tool-result/transcript (LEVEL 4)? -> STOP
- Is the credential long-lived (>1 day)? -> DB-adapter instead of env
- Has a rotation plan been documented in case of a leak?
- Is the proc-environ blocker active in the session?
