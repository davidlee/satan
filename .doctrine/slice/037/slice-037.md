# SL-037: Signal loss (F1) — hold unsupported outcomes at the broker, then add the reason the daemon lacks

## Why

Every tick, `satan-sensor-content` enqueues `reason: "content_backlog"`
(`satan-sensor-content.el:122`). The daemon's `SensorReason` set has no `ContentBacklog`
(`satan-attrd/src/types.rs:309-316`), so `parse_inbox_payload` fails and
`process_outcome_row` **deletes the row** (`run_loop.rs:527-548`) — one log line, no record.
The broker then advances the content probe's watermark, because `probe-commit` advances on
*enqueue* (`satan-sensor-content.el:130-142`), so the evidence is consumed as well as
discarded. `ISS-011` records ~7/day since at least 2026-09-11, still open; `RFC-021` F1.

Two wrong states have already been tried. RFC-016's Phase 0 had the rows **blocking
startup** (a poison message); the current code **deletes them** (invisible loss). The
correct state is neither: store the signal, then handle it. That is this slice.

`RFC-021` §5 item 1 names the routes. This slice takes the one that is both deployable now
and preserving — the broker-side hold — and then the restoring fix (the daemon-side reason,
in the same act as the contract amend). It explicitly does **not** take O1's general
machinery; see *Out of scope*.

## What changes

### A. Broker — a signal cannot be destroyed by an unsupported reason

`probe-commit` becomes *gate → enqueue → advance*, where the gate asks one question: does the
deployed daemon accept this `(source, reason)` pair? If it does, behaviour is unchanged. If it
does not:

- **no enqueue** (nothing to reject, nothing to delete),
- **no watermark advance** (the evidence is not consumed),
- a **held-signal record** — reason, count, watermark, first/last held time, why it is held,
- a **visible warning** at the point of holding, not a `message` that scrolls away.

Release is automatic and requires no new code path: once the reason is accepted, the next
probe re-reads `articles.jsonl` (verified: panopticon never prunes `content/`, so the backlog
survives; `RFC-021` §5 item 1) and emits the whole accumulated count once.

The declared vocabulary is a constant in the broker, and a test asserts it matches the
contract's `§6S.1` list — so the two sides cite one list rather than each other's memory.

### B. Daemon — the reason exists, so the hold releases

`satan-attrd`: `SensorReason::ContentBacklog` with `as_str` → `"content_backlog"`, parser
mapping, a `tuning::sensor_base_deltas` row, and dispatcher tests. Contract
`docs/attributes/design-contract.md`: a `§6S.1` reason row, a `§6S.2` delta row, and a `§16`
change-history entry — the contract amend `RFC-021` requires in the same act.

Delta values are a decision, not a transcription (see *Open questions*), but the shape is
fixed by §6S.2 and by the `SegmentBacklog` precedent.

### C. The reader

The held-signal record must be readable by an agent — a read-only surface that answers "what
is held, why, since when, and how much". Same invariant as `SL-036`, applied to this slice's
own writer: no new writable artefact without a reader in the same slice.

## In scope

- `satan/satan-sensor-content.el` — the gate, the hold record, the warning.
- `satan/satan-attribute.el` — only if enqueue needs a hook to report refusal.
- A read-only reader for held signals (function, and a tool only if `/design` argues for it).
- `docs/attributes/design-contract.md` — `§6S.1`, `§6S.2`, `§16`.
- `satan-attrd` (external repo, same act): `src/types.rs`, `src/dispatcher.rs`, `src/tuning.rs`
  and their tests. No migration: sensor reasons are code, not schema — confirm in `/design`.
- Tests: the negative (unsupported reason ⇒ no enqueue, no advance), the hold record, the
  vocabulary/contract agreement, and the daemon's parse + delta for the new reason.

## Out of scope

- **O1's general machinery** — opaque storage of *unknown* `(source, reason)` pairs, a
  dead-letter carrying the error, claim expiry, and a general broker↔daemon acknowledgement
  handshake. This slice hard-codes one declared vocabulary; O1 is the invariant that makes
  the vocabulary unnecessary. Building half of O1 here would leave the worse half behind.
- **Remapping to `segment_backlog`** — rejected in `RFC-021`: different sensor type, metric
  and watermark (`captured_at`, DEC-5); it would encode one evidence stream as another.
- **Stopping emission while the watermark advances** — the same loss with better manners.
- **F2's forward-compatibility contract** (a versioned reason negotiation). Named as the
  general answer, deliberately deferred.
- Attribute *semantics* beyond one reason and its delta row; decay; caps; the daemon's
  projection.

## Affected surface

- `satan/satan-sensor-content.el` — gate, hold, warning
- `satan/satan-attribute.el` — refusal reporting (if needed)
- `satan/satan-attributes-*` / reader site for held signals
- `docs/attributes/design-contract.md` — §6S.1, §6S.2, §16
- `satan-attrd/src/{types,dispatcher,tuning}.rs` + tests (external repo)
- A test asserting no unsupported reason can reach the queue

## Risks and assumptions

- **The declared table can rot.** A constant that claims what the daemon accepts is exactly
  the kind of convention `F2` says fails. Mitigation: one list, in the contract, with a test
  on each side citing it; and the hold is *visible*, so rot shows up as a warning rather than
  as silence.
- **Delta semantics.** `+0.05` of something on "you have an uninspected reading backlog" is a
  design claim. Getting it wrong is recoverable (the reason lands with a recorded delta and a
  rebuildable projection) but not free.
- **The fix may already be latent on the host.** `satan-sensor-content-enabled` defaults to
  `t` but the operator may have set it nil as the immediate mitigation (`ISS-011`). If so,
  this slice is correctness, not an incident — confirm the live value **[verify]**.
- **Two repos, one act.** A broker-only hold with no daemon reason is a *permanent* hold —
  better than loss, worse than working. If the daemon change cannot land in the same window,
  the broker half ships behind the existing disable switch and the hold is announced as such.
- Assumption: the daemon's rejection is the *only* reason these rows vanish. `run_loop.rs`
  deletes on parse *and* on schema-version failure (`:527-548`); the hold must not mask a
  schema failure as a vocabulary failure — the two need distinct reporting.

## Verification / closure

- **Loss is impossible by construction:** a test drives the probe with a reason the declared
  vocabulary lacks and asserts *no* enqueue and *no* watermark advance, plus one hold record.
- **The hold is visible:** the reader reports it with count, age and cause, without SQL.
- **The list is one list:** broker constant == contract `§6S.1` == daemon `as_str` set (two
  tests, one per repo).
- **The signal lands:** with the daemon change in place, the accumulated backlog emits once
  and `uninspected_captures` reaches the projection; the `parse_inbox_payload` failure line
  for this reason disappears from the journal.
- **Nothing else moves:** no watermark behaviour changes for any other sensor;
  `satan-sensor-content-enabled` keeps its meaning.
- `ISS-011` gets a dated closure note recording the mechanism and the fix.

## Open questions for `/design`

- **What are the delta values?** `§6S.2` needs a row: which attribute(s), what sign, what
  magnitude, and whether the magnitude scales with the backlog count (§6S.3 says sensor
  signals are binary — so presumably not, and the count stays evidence). The `SegmentBacklog`
  row is the precedent, not the answer.
- **Where does the hold record live** — the probe's state file (cheap, already read/written)
  or the trace JSONL (already per-run)? Prefer whichever gives the reader without a new
  parser.
- **Is the vocabulary declared or discovered?** A constant is simple and rots; reading the
  daemon's `as_str` set at build time is not available cross-repo; a handshake is O1. The
  design should choose and say why, rather than defaulting.
- **Does the gate belong in every sensor or only here?** Four sensor probes share the shape
  (`sensor-wpm`, `sensor-curiosity`, `sensor-alerts`, `sensor-content`); generalising is
  cheap now and is O1's first inch — but O1 is deliberately out of scope, so the design must
  decide whether the narrow gate is *scoped* to content or *written* for reuse.

## Relations

- `ISS-011` — the recorded loss this closes.
- `RFC-021` — F1, §5 item 1 (routes), §5 item 2 (O1, deliberately excluded).
- `SL-019` — hermetic test DB with the pinned `satan-attrd` schema; the integration test wants
  it (`after`).
- `SL-036` — the same reader-parity discipline, applied to a different writer.
- `SL-023`/`SPEC-004` not involved: the shared database is, but the patch runner is not.
