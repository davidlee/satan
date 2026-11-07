# SL-037: Signal loss (F1) — add the reason the daemon lacks, preserving the backlog until it deploys

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

`RFC-021` §5 item 1 names the routes. This slice takes route (i), the flag, as the interim
preservation and route (ii), the daemon reason, as the fix. It builds no broker-side hold
(`DEC-148`) and does **not** take O1's general machinery; see *Out of scope*.

## What changes

### A. Interim — stop the loss, no code

Set `satan-sensor-content-enabled` nil until the daemon is deployed, in the Emacs config so a
restart keeps it. From the next probe read it does nothing: no enqueue and no watermark
advance. A tick already past its read commits once. The backlog stays in `articles.jsonl`
(panopticon never prunes `content/`; `RFC-021` §5 item 1). This is an operator act on the
host, not a code change.

### B. Daemon and contract — the reason exists

`satan-attrd`: `SensorReason::ContentBacklog` with `as_str` → `"content_backlog"`, parser
mapping, a `tuning::sensor_base_deltas` row, and dispatcher tests. Confirm that
`parse_sensor_payload` accepts this payload's `sensor_type` and `metric_unit`.

Contract `docs/attributes/design-contract.md`: a `§6S.1` reason row, a `§6S.2` delta row, the
`§6S.5` evidence enumerations (`panopticon_content_backlog` / `uninspected_captures` are
missing today, so the contract already contradicts shipped code), a `§6S.2` preamble note that
this reason fires once per tick that finds captures newer than the watermark, and a `§16` change-history entry.

The row is Curiosity **+0.025**, every other attribute zero, never scaled by the capture count
(`DEC-149`). A non-zero base is required: the dispatcher skips zero-base attributes, so an
all-zero row writes no event.

### C. Broker — two small changes

- `satan-audit-attribute-sensor-reasons` gains `content_backlog`, or the broker rejects the
  daemon's `attribute.delta_applied` for the new reason (the SL-016 precedent).
- `satan-sensor-content-probe-commit` advances the watermark only when
  `satan-attribute-enqueue` returns `(ok . ID)`. Today it ignores `(error . MSG)`, so a failed
  insert consumes the evidence.

### D. Release

Daemon first, then re-enable the flag. The next probe emits the accumulated count once.

## In scope

- `satan/satan-sensor-content.el` — commit advances on `(ok . ID)` only.
- `satan/satan-audit.el` — the sensor reason literal gains `content_backlog`.
- `docs/attributes/design-contract.md` — `§6S.1`, `§6S.2` (row + preamble), `§6S.5`, `§16`.
- `satan-attrd` (external repo, same act): `src/types.rs`, `src/dispatcher.rs`, `src/tuning.rs`
  and their tests, plus a parse test in `src/run_loop.rs`. No migration: `reason` is
  `TEXT NOT NULL` with no CHECK (`migrations/0007_attributes.sql`), so sensor reasons are code,
  not schema — confirmed.
- Tests: every test that expects the watermark to advance stubs enqueue to return `(ok . 1)`;
  an enqueue error leaves the watermark unchanged; the audit validator accepts the new
  reason; the daemon's parse and delta for the new reason.

## Out of scope

- **A broker-side hold** — floor, gate, hold record, warning, reader, capsule line (`DEC-148`).
- **O1's general machinery** — opaque storage of *unknown* `(source, reason)` pairs, a
  dead-letter carrying the error, claim expiry, and a general broker↔daemon acknowledgement
  handshake. Future vocabulary skew stays O1's.
- **The curiosity and wpm probes' watermark advance** — the same `(ok . ID)` fix, left to O1.
- **Remapping to `segment_backlog`** — rejected in `RFC-021`: different sensor type, metric
  and watermark (`captured_at`, `DR-005` DEC-5); it would encode one evidence stream as another.
- **Stopping emission while the watermark advances** — the same loss with better manners.
- **F2's forward-compatibility contract** (a versioned reason negotiation).
- **Schema-major divergence** — a release invariant (`DEC-147`; its references to the gate
  are moot after `DEC-148`).
- Attribute *semantics* beyond one reason and its delta row; decay; caps; the daemon's
  projection.

## Affected surface

- `satan/satan-sensor-content.el`, `satan/satan-audit.el`
- `satan/test/satan-sensor-content-test.el`, the audit validator's test file
- `docs/attributes/design-contract.md` — §6S.1, §6S.2, §6S.5, §16
- `satan-attrd/src/{types,dispatcher,tuning}.rs` + tests, `src/run_loop.rs` tests (external repo)

## Risks and assumptions

- **Release order is not enforced.** Until O1 ships, a reason emitted before the daemon accepts
  it is still lost. Here the flag covers the gap; re-enabling before the deploy re-opens the loss.
- **Delta semantics.** Curiosity reached 1.000 on each of the 15 days to 2026-11-07 and is not
  decayed, so this row is effectively telemetry while it stays saturated (`DEC-149`, `ISS-066`).
- **The loss is live.** Verified 2026-11-07: the watermark tracks the latest capture and the
  journal shows rejections, so the flag is on. Part A has not yet been applied.
- **Schema divergence stays open.** `run_loop.rs` deletes on parse *and* on schema-major
  failure (`DEC-147`).

## Verification / closure

- **Interim:** with the flag nil, and allowing one in-flight tick, the watermark stops moving and
  `content_backlog` rejections stop in the journal. The flag stays nil across an Emacs restart.
- **Enqueue failure:** a test shows an `(error . MSG)` result leaves the watermark unchanged.
- **The signal lands:** after deploy and re-enable, the accumulated backlog emits once, a
  `satan_attribute_events` row exists for the reason, and the `parse_inbox_payload` failure line
  for it disappears from the journal. The check is the event row, not movement in the
  projection, which may be clamped.
- **The broker accepts it:** the run transcript has an `attribute.delta_applied` line with this
  reason, and the `satan-attrd` journal has no `broker rejected` line in that window. The event
  row exists either way.
- **Nothing else moves:** no watermark behaviour changes for any other sensor;
  `satan-sensor-content-enabled` keeps its meaning.
- `ISS-011` gets a dated closure note recording the mechanism and the fix.

## Decisions taken (design run `dr-01a1b05a`)

- `DEC-148` (2026-11-07) — no broker-side hold; supersedes `DEC-141` … `DEC-146`.
- `DEC-147` — schema-major divergence stays a release invariant for O1.
- `DEC-149` (2026-11-07) — Curiosity `+0.025`, unscaled, on measured rates; supersedes `DEC-140`.

## Relations

- `ISS-011` — the recorded loss this closes.
- `RFC-021` — F1, §5 item 1 (routes), §5 item 2 (O1, deliberately excluded).
- `SL-019` — hermetic test DB with the pinned `satan-attrd` schema; the integration test wants
  it (`after`).
- `SL-036` — its reader-parity discipline no longer applies: this slice adds no new writable artefact.
- `SL-023`/`SPEC-004` not involved: the shared database is, but the patch runner is not.
