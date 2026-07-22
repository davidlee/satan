# SATAN PSQL plumbing

# SATAN psql plumbing: shared module extracted (DE-003 landed)

[[DE-003]] extracted a shared `dl-satan-db.el` replacing 4 private psql clones.

## Current state (post DE-003, 2026-05-31)

| Caller | Uses |
|--------|------|
| `dl-satan-memory-store.el` | `dl-satan-db-query(db host program sql vars)` |
| `dl-satan-patch-store.el` | `dl-satan-db-query(db host program sql vars)` |
| `dl-satan-attribute.el` | `dl-satan-db-query(db host program sql vars)` |
| `dl-satan-memory-migrate.el` | `dl-satan-db-psql(db host program extra-flags &optional input)` |
| `dl-satan-intervention.el` | `dl-satan-db-psql(...)` via `--exec-sql` and direct calls |

## Two surfaces

### `dl-satan-db-query(db host program sql variables)`
- Always passes `-q -X -A -t -F "\t" -v ON_ERROR_STOP=1`
- Variables supplied as alist `((name . value) ...)`, bound via `-v name=value`
- SQL fed on stdin with `-f -` (needed for variable substitution)
- Returns `(ok . string-trimmed-stdout)` or `(error . "psql exit N on DB: msg")`
- **Use this for the common case**: SQL + variable substitution → trimmed result

### `dl-satan-db-psql(db host program extra-flags &optional input)`
- Base args only `-h HOST -d DB --no-psqlrc -v ON_ERROR_STOP=1`
- Caller controls all other flags via `extra-flags` list
- When `input` is given, feeds via stdin (caller must include `-f -` in extra-flags)
- When `input` is nil, runs via `call-process` (caller must include `-c SQL`)
- Returns `(ok . untrimmed-stdout)` — **NOT trimmed**, matching old `--psql` semantics
- **Use this only when caller needs custom flags** (--single-transaction, -c inline SQL, custom -F)

## The `-q` gotcha (fixed)

`dl-satan-db-query` **always** passes `-q` (quiet mode), fixing a latent bug
where `dl-satan-memory-store--query` lacked `-q` and psql welcome-banner could
leak into stdout.

## Each module uses different defcustoms

Callers pass their own host/program defcustoms explicitly:

- memory-store: `dl-satan-memory-store-host` / `dl-satan-memory-store-psql-program`
- patch-store: `dl-satan-patch-store-host` / `dl-satan-patch-store-psql-program`
- attribute: `dl-satan-attribute-host` / `dl-satan-attribute-psql-program`
- memory-migrate: `dl-satan-memory-migrate-host` / `dl-satan-memory-migrate-psql-program`

## Do NOT add a new psql clone

Use `dl-satan-db-query` for the common case. Use `dl-satan-db-psql` only when
custom flags are needed. Never add a private `--query` function to a new module.

## Related

- [[DE-003]] — delta that extracted this module
- [[DR-003]] — DEC-001 covers the shared signature
- [[POL-001]] — extraction policy (these modules stay in broker)
- `satan/dl-satan-db.el` — the module itself
