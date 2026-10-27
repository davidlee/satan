# Review RV-062 — design of SL-034

Adversarial-review ledger. Structured findings live in the sister
ledger toml; this prose companion carries the reviewer's framing.

## Brief

<!-- Pre-reading + lines of attack: what this review is probing, the invariants
     it must hold the subject to, and where the bodies are likely buried. Seeded
     at `review new`; the reviewer fills it before raising findings. -->

Raiser: `codex`. Adversarial design pass over all 13 sections of SL-034's
design, against the current accepted DEC-127 through DEC-139 (including the
GPT sense-check amendments), scope, ADR-017 and its authority ledger,
ADR-018, POL-001, CON-005 and REQ-013. Theme: cheapest, simplest approach
that works; settled v0 tradeoffs are constraints, not fresh objections.

Lines of attack: occurrence identity and the atomic next-sleep checkpoint;
startup dependency binding; cancellation versus durable input admission;
heartbeat recovery and uniqueness across restart; actual tool/runtime API
and MCP wire representations; policy arithmetic, quiet windows and jail time
zone; authority ownership, switch semantics and verification coverage.

Evidence: current malebolge source and its 1.4.0 dependency, local pi-durable
source/spec, satan-mcp source, flake launcher options/probes, and the retained
SL-034 research/spike. Additional probes ran as Node stdin programs over
MemoryStorage and a faux model, without files or external services. Findings
distinguish observed runtime behavior from prospective implementation risks.

## Pass evidence and assessment

Revision required: F-1 through F-5 are major; F-6 is minor. The use of
pi-durable tasks, its timer and stable occurrence request IDs is appropriate;
no second scheduler, database table or stronger v0 limits are proposed.

Positive checks: the occurrence replay probe admitted one input, closed and
reopened storage, deferred with the same `n`, then replayed admission. Model
call count stayed 1. The committed next sleep contained both `until:3000`
and checkpoint `{phase:fire,at:3000,n:1}`; advancing to 3000 produced a second
turn and `{until:4000,checkpoint:{phase:fire,at:4000,n:2}}`. This agrees with
`submissions.ts:210-216` and `scheduler.ts:2182-2186` in pi-durable. Another
probe observed zero extra phase entries and `scheduling:paused` through
open/root/configure/commits before resume. The tool API really lacks global
inspection and task-abort operations; the Harness dependency is justified
(`src/harness/types.ts:209-259`).

The stated schedule arithmetic re-clamps after jitter. Quiet-window wrapping
and local-zone verification remain implementation obligations, explicitly
listed in the design; no live jail time-zone behavior was verified here.
The planned owner token, rows 7b/6d/4d, row 3b evidence, process-private store,
and no second schema/migration owner fit the stated governance. The accepted
no-limits v0, admission-only switch, shared interactive allowlist,
admission-time quiet check, and `afterFailedRun:keep` were treated as settled.

Limits of evidence: the new wake implementation does not exist. The runtime
probes exercised installed pi-durable 1.4.0 with MemoryStorage/faux responses
and controlled interleavings, not a deployed room daemon or an actual process
kill/SQLite power-loss test. MCP encoding was checked in source, not through
the user's live editor. No builds, deployment, external messages, other RVs,
or source/design/governance edits were performed by this pass.

## Verify round — codex, 2026-10-27

Checked all six fix-now responses against the rematerialised design, current
DEC-127/130/131/139 including their RV-062 amendments, reconciled scope, and
the actual pi-durable/MCP APIs. Verified F-1, F-2, F-4, F-5 and F-6 as design
repairs. Contested F-3: the example uses `task.state.phase`, which is absent
on the received pi-durable record; the phase is in `task.state.checkpoint`.
Raised F-7 (major), first admission bypassing the off/quiet gate after restart
from a prepared submit checkpoint, and F-8 (minor), the scope's stale
one-ceiling recovery promise. Revision remains required.

Additional Node-stdin probes used only MemoryStorage and faux models:

- Exact revised two-phase abort expression: a queued `wake:10:0` survived
  abort, but the handler returned `{fired:false}` because `state.phase` was
  undefined; releasing the foreground response ran the wake (2 model calls).
- Close after checkpointing `submit`, before any input admission: the stored
  state had no submissions and 0 model calls. Reopening with wakes disabled
  ran the submit phase and produced 1 model call.
- Bounded heartbeat wait with reopen behind a failed foreground run: timeout
  produced sleeping `fire` at `n:1` while the old input remained queued;
  the fresh next occurrence released queued work and reached `n:2`.
  Timeout itself was not recovery. This probe used a short runtime timer;
  authored ceiling arithmetic, rather than production latency, establishes
  the timing discrepancy in F-8.
- Restart with the old heartbeat's abort mark persisted: the revised predicate
  excluded old task 7 and created replacement 8; only 8 remained viable after
  old abort completion.
- The stated presence regex mapped all four current enum values correctly,
  returned unknown for missing/isError, and ignored a fake presence word
  quoted inside a printed window title.

The five verifications accept implementable design contracts; they do not
certify unimplemented wake code or deployed startup behavior. No live editor,
room jail, builds, SQLite crash durability or deployment checks were run.
Only this RV's records were changed by the verify round.

## Verify round 2 — codex, 2026-10-27

Verified F-3, F-7 and F-8 against the rematerialised design, DEC-127's latest
choice/amendment, the scope Summary, and pi-durable 1.4.0 source/runtime.
The corrected handler reads the actual checkpoint. The submit host recheck
blocks a first admission while off, and an already-admitted run progresses
independently while its wake task defers. The recovery timing criterion now
names two ceilings from admission and qualifies gate defers/restarts.

Raised F-9 (major): the accepted DEC-127 fire-defer checkpoint recipe omits
the new `prepared` marker, contradicting the design's clear-only-on-next-n
rule. Following that recipe after a submit defer reproduces a false cancelled
answer with an admitted input still queued. The handler correction in F-3
works when it receives the marker; the new defect is marker propagation
through a later fire defer. Diagram/tool prose also needs that exception.

Focused in-memory evidence (Node stdin; no files or external services):

- No previous admission: restart off stored `{phase:fire,n:0,prepared:true}`
  with 0 model calls; on enabled retry, calls became 1 and checkpoint `n:1`
  had no marker; the next occurrence produced call 2 and `n:2`.
- Previous completed admission: the same off/on retry kept calls at 1,
  deduping occurrence 0; occurrence 1 then produced call 2. Counter advance
  committed the next sleep with no inherited marker.
- Previous unexecuted admission: used pi-durable's admission function in a
  paused harness to store a placed input and run before any model call.
  Close/reopen off resumed that admitted run to `done` while the wake task
  deferred with `prepared:true`. Enabled retry did not duplicate it, and the
  next heartbeat occurrence remained distinct.
- Previous queued admission behind a failed foreground run: submit defer
  stored `{at:2000,n:0,prepared:true}`. A second fire defer using the explicit
  DEC recipe stored `{at:3000,n:0}`. Cancel returned `{fired:false}` with the
  old input queued, and later normal input released it. Carrying the marker
  through that defer in the control probe returned `{fired:true}` instead.

The W1/W4 mechanism and intended heartbeat progression survived the prepared
defer probes. F-9 prevents acceptance of the complete current W9 contract.
These remain design/proposed-state-machine checks, not certification of
unimplemented wake code, production timing, live jail behavior, or SQLite
crash durability. Only RV-062 was changed; F-9 awaits the responder.

## Verify round 3 — codex, 2026-10-27

Verified F-9's state-preservation repair against the current design and
DEC-127, including the explicit all-fire-defers spread rule. The original
data-loss reproduction now passes through three subsequent defers and a
reopen: all checkpoints retain `prepared:true` and `n:0`, and cancellation
returns `{fired:true}` for the already-queued occurrence. A heartbeat probe
seeded with a valid surviving `n:7` checkpoint preserved that counter through
the same defers, advanced to `n:8` with the marker cleared in its next sleep,
and then advanced to `n:9` after a distinct occurrence.

Swept every authored checkpoint constructor: initial creation, early fire
re-sleep, gate/presence defer, heartbeat suppression, fire-to-submit,
submit-host-defer back to fire, heartbeat settlement/failure/timeout to the
next occurrence, and terminal outcomes. No further loss of `prepared` or `n`
was found. Entering `submit` safely carries potential admission in its phase;
entering the next occurrence intentionally drops the marker with `n+1`.

F-10 (minor) isolates the remaining prose aspect of F-9: the cancellation
diagram and Tools explanation still state an unconditional fire abort means
`{fired:false}`/cancelled, contrary to the corrected prepared-fire handler and
W9. The functional major finding is fixed; the remaining issue is document
consistency, not a reproduced defect in the corrected transition recipes.

Runtime evidence used only installed pi-durable 1.4.0, MemoryStorage and faux
responses in Node stdin programs. No source/design/decision edits, builds,
deployment, live jail/editor checks or real SQLite crash tests were performed.
Only RV-062 changed; all major findings are verified, and F-10 awaits response.
