## Decision

`pi-mcp` appends its own audit records to `<run dir>/audit.jsonl` — one JSON object per line, `O_APPEND`, fsynced per record, single writer (`pi-mcp`, new ledger row 4c). Control decisions only:

- `spawn` — profile, root, resolved tools, ceilings, child process id;
- `refuse` — the named reason (unknown profile, bad root, bwrap unavailable, switch off);
- `abort` — ceiling crossing with the usage at the moment of the gate (DEC-090);
- `timeout` — the backstop fired;
- `exit` — child status and the resulting `state`.

pi's `events.jsonl` is **not** the audit log: it is model output (tool calls, tokens), not control decisions, and the reducer summarises it. Keeping them separate is what lets the audit be read without parsing a 175 KB wire log, and lets the transcript be re-rendered without touching the audit.

## Why not the alternatives

- **The SATAN DB** is unavailable exactly when this matters: the server must hold with Emacs absent, and REQ-010 says ceilings and invariants hold with the client absent. A Postgres dependency would also put a second writer near the run audit.
- **Emacs's run audit (row 4a)** is `emacs-client`'s and needs the editor. This is a separate log, exactly as patch jobs' `job_events` (row 4b) is separate.
- **Logging only to stderr** is what the shell wrappers do today, and it is why CHR-051/ISS-293 took days to see: a control decision that is not a durable record is not evidence.

## Consequences

- Audit durability is tied to the run dir, so `PI_MCP_RUN_DIR` is part of the authority surface: readable, append-only by convention, pruned only by ops.
- An observer (satan or otherwise) can ingest `audit.jsonl` later without the server's participation; nothing in the design assumes it does.
- Retention is deliberately out of scope: run dirs accumulate until something prunes them, and the design says so rather than pretending.
