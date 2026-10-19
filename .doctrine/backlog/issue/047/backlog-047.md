# ISS-047: Runner rejoin wedges the one seat when a held job's repo has left config

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

**Origin:** SL-023 audit RV-029 F-23 (PHASE-10 batch B Open, confirmed in code).

**Observed.** `rejoinJob` (`~/dev/malebolge/src/runner/rejoin.ts`) resolves the
held job's repo with `configEntry(deps.config.repos, …)`. When a job is held in
a non-`preparing` state (`running`, `waiting_room`, …) and its repo was removed
from runner config before the restart, that throws; so do the
"conversation missing", "running segment's submission missing" and "nothing to
rejoin" guards. The scheduler logs and rests, the job keeps the one seat
(design §5.4 Scheduling), and the next restart throws again: no job on any repo
runs until the config is restored or the row is moved by hand. No test covers
it. A `preparing` row already fails like `runJob` (`endUnrun`).

**Do.** Decide the fail-closed end for an unrejoinable held job (e.g.
`collecting` with `end_reason = error` when anything ran — I12 — or `failed`
with a reason naming the guard), so the seat is released and the job is
audited; test each guard.

**Related, smaller.** `awaitRoom`/`readyRoom` backoff sleeps and the
post-collect clean ignore `RunDeps.stopping`; a stop can wait up to one backoff
delay (≤ 60 s).
