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


## RV-043 F-1 and F-8: evidence the delegate cannot reach, and refusals that have a home

F-1 defeated the original claim: the run directory was bound into the child, so
the delegate held a writable handle to its own audit. `O_APPEND` and fsync
protect a writer, not a path — a same-uid child can truncate, unlink or replace
the file and the server's next append still succeeds (reproduced).

Corrected model:

- **Child-visible writable set**: the *active session directory only*
  (`<PI_MCP_SESSION_HOME>/<session-id>/`). Not the session home, not the run dir,
  not the evidence store.
- **Server-owned evidence**: `events.jsonl`, `stderr.log`, `transcript.md`,
  `status.json`, `audit.jsonl` live in a directory no child has a bind to.
- **Static mode cannot do this** in a single-uid jail: the server's writable view
  is the child's. There, evidence is buffered in memory and flushed after the
  child exits, the policy may declare a single session, and the residual
  (a co-resident child can write anything the server can) is stated in sec-3
  rather than wished away.
- **Refusals** (F-8) go to a server-level `attempts.jsonl` in the state directory:
  no child, no run dir, and a policy digest recorded only when one was readable.
  If that sink is unwritable the refusal is still returned in-band and on stderr,
  and the no-child-without-logging rule holds. Recursion is excluded because the
  attempt log never requires a run directory.
