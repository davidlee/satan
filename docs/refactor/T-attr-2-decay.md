---
name: satan-refactor-T-attr-2
description: Daily idle-decay rule for shame/doubt/brooding/metamorphosis — daemon-side scheduler in satan-attrd
metadata:
  type: refactor-theme
  topic: satan-refactor
  status: done
  blocked_by: [T-attr-1b]
  updated_at: 2026-05-29
---

# Theme T-attr-2 — Attribute decay (idle daily tick)

**Impact:** Medium. **Effort:** S–M (daemon-side, contract amend + ~5 small PRs). **Risk:** L. **Reversibility:** Soft (extends `attribute-updates-enabled` disable switch; events still recorded with `disabled=true`).

Resolves contract §15 Q2 (decay schedule), deferred from T-attr-1 per contract §8. Surfaced as a sequencing question against T-attr-1d on 2026-05-29 — without decay, every positive-net source ratchets attributes toward their ceiling and 1d's capsule renders drift-to-saturation rather than meaningful homeostasis.

## Current shape

Contract §8 — V1 ships without automatic decay. Values move only on explicit source events. Production observation (2026-05-29) confirms the predicted failure mode:

- Doubt + Shame pinned at 0.50 from one synthetic `morning-aaaaaa` fixture outcome with no counter-event in the three days since.
- Curiosity tuned 2026-05-29 to a +0.025/day positive net (sensor `segment_backlog` +0.05, hippocampus `trace_marked` −0.025). Will ratchet to ceiling over weeks absent decay.
- T-attr-1e remaining sources (`percept` / `resonance` / `tool_error`) will compound the asymmetry when they land.

Contract §8 already names the target rule (`-0.01/day` on `shame`/`doubt`/`brooding`/`metamorphosis`) and the deferral reason (a daily decay rule is a behaviour change worth its own contract pass — baking it in pre-observation risks tuning friction toward zero on quiet days). The 2026-05-29 production data is the "observed long enough" trigger §8 stipulated.

## Why it hurts

- **1d capsule renders are misleading on saturating substrate.** First-impression UX of the attribute layer is "everything pinned at 0.5" — semantically indistinguishable from "we have no signal."
- **1e source tuning on top of monotonic accumulation is uncalibrated.** Every magnitude decision (`trace_marked` Curiosity, future percept/resonance) is set against an implicit assumption of decay. Without it, magnitudes are conservatively under-tuned to avoid early saturation, and the system under-reacts to real signal.
- **Rollback granularity is missing.** Operators can disable the whole attribute layer but cannot "reset accumulated drift" — the only path is a database-level zero.

## Target shape

Daemon-side daily idle-decay rule, implemented in `satan-attrd` per [`extraction-policy.md`](extraction-policy.md) §"Active beachhead" (daemon owns store + dispatcher + audit emission). Broker stays out — adding decay as a broker timer would grow elisp surface for non-editor work and miss ticks when emacs is down.

**Mechanism.** Daemon runs a `tokio::time::interval(1h)` task that, per attribute in `{shame, doubt, brooding, metamorphosis}`, checks `last_decay_at` and applies a single tick if `now - last_decay_at ≥ 1 day`. Single tick per check — catch-up after long absences is **one** tick, not N (see "Catch-up policy" below).

**Decay event.** `attribute.delta_applied` with `source=maintenance`, `reason=idle_decay`. Goes through the same §5 dispatcher pipeline as every other source event — caps, range_clamp, projection UPSERT, audit-event emit. Floor: `range_clamp` to `[0,1]` already covers — a `0.005` value rounds via clamp to `0` on the next tick where `new < 0`.

**Disable switch.** Honours `attribute-updates-enabled` exactly as other sources do: `nil` → emit event with `disabled=true`, skip UPSERT. Decay ticks pause when the layer is disabled; on re-enable, the next scheduled tick fires whenever the daemon next checks — no catch-up replay across the disabled gap.

**run_id semantics.** Synthetic `maintenance:<utc-day>` (e.g. `maintenance:2026-05-29`). Preserves the contract §17 `run_id NOT NULL` invariant — no schema relaxation needed. Replay determinism via `(ts, run_id, seq)` holds.

## Contract amends (T-attr-2a)

Before any code, amend the contract:

- **§8 Decay.** Rewrite from "deferred to T-attr-2" to the normative rule: −0.01/day on the 4-attr set, daemon-applied on a daily UTC boundary, single-tick catch-up.
- **§15 Q2.** Mark resolved; cross-link to §8.
- **§17 Audit validator widening.** Add `(source=maintenance, reason=idle_decay)` to the pairing table. `evidence_json` shape for decay: `{"days_since_last": N, "tick_utc_day": "YYYY-MM-DD"}` — preserves observability of catch-up gaps. No `intervention_id` / `cue_handles` (decay is uncue'd).
- **§17 run_id reservation.** Add synthetic run_id pattern `maintenance:<utc-day>` to the reserved-prefix list; document the rebuild interaction (replay sorts naturally by `(ts, run_id, seq)`; maintenance events sort by their tick timestamp).
- **§17 Daemon design choices.** Pin disable-switch placement (daemon-side, consistent with §17.1 choice 3) and event-bus shape (no broker event — decay is daemon-originated, not broker-emitted, so PG-queue/`pg_notify` does not apply). Document the asymmetry explicitly.
- **§16 Change history row.** One entry covering all of the above.

## Schema migration (T-attr-2b)

`0011_attribute_decay.sql`:

- Add `last_decay_at TIMESTAMPTZ NULL` to `satan_attributes` (per-attribute row).
- Backfill: `UPDATE satan_attributes SET last_decay_at = NOW()` so existing rows do not immediately fire a "first tick" with N days of accumulated drift at deploy time.
- Index: none — scheduler reads all 4 decay-target rows per check, no point.

No widening of `satan_attribute_events` schema — the new `(source, reason)` pair lives in existing columns.

## Daemon scheduler (T-attr-2c)

New `crates/satan-attrd/src/decay.rs` (or extend an existing scheduler module if one lands first):

- `tokio::time::interval(Duration::from_secs(3600))` — hourly check, daily fire. Hourly cadence keeps drift on restart bounded to <1h; the per-attribute `last_decay_at` guard prevents double-fires.
- Per tick: read `last_decay_at` for the 4 decay-target attributes; for each where `now - last_decay_at ≥ 24h`, dispatch a synthetic decay event through the existing store API.
- Idempotence: `last_decay_at` is bumped only after a successful event-insert + projection-UPSERT transaction. Crash mid-tick → next hour's check re-runs the same attribute.
- Test seam: clock injection via a `Clock` trait (real impl = `Utc::now()`, test impl = injectable). Existing daemon tests already need this for any time-dependent logic — establish the pattern here.

## Decay application (T-attr-2d)

Extends `decay::DecayScheduler::tick` from the T-attr-2c skeleton. Pre-research notes — first concrete code shape for the cold-start session.

### Required code touchpoints

| File | Change |
| --- | --- |
| `~/dev/satan-attrd/src/types.rs` (or new variant) | Add a `Source::Maintenance` variant if not already there; `Reason::IdleDecay` on whichever reason enum carries non-outcome reasons (likely a new `MaintenanceReason` enum, mirroring `HippocampusReason` / `SensorReason`). |
| `~/dev/satan-attrd/src/dispatcher.rs` | Add a `dispatch_maintenance(input: &MaintenanceInput, counter: &Counter) -> Vec<EventInsert>` following the `dispatch_sensor` shape (binary, no confidence weighting, evidence is `{days_since_last, tick_utc_day}`). `MaintenanceInput` mirrors `SensorInput`: `run_id`, `ts`, `reason`, `enabled`, `snapshot`, `projection`, plus `days_since_last: i64`. |
| `~/dev/satan-attrd/src/decay.rs` | Replace `tick`'s "log + return count" body with a full apply loop. Per due row: build `Snapshot` from current projection (read `(doubt, shame)` for §6.3); build `MaintenanceInput` with `days_since_last = row.days_since_last.unwrap_or(1)` clamped to 1 per §8 single-tick rule; call `dispatch_maintenance` → `Vec<EventInsert>`; for each event, `store::insert_event` + (conditional on `!ev.disabled`) `store::upsert_attribute` + `rpc::enqueue_audit_event` (use `run_loop::build_audit_payload` — move it to `run_loop`-pub or to a shared module). On UPSERT success, `UPDATE satan_attributes SET last_decay_at = NOW() WHERE scope = $1 AND name = $2`. |
| `~/dev/satan-attrd/src/decay.rs` | Add a per-UTC-day `Counter` strategy. Two options: (1) own `Mutex<(NaiveDate, Counter)>` and swap on rollover; (2) reuse the run-loop's `LruCounterMap` keyed by `maintenance:YYYY-MM-DD` (would require sharing the map between RunLoop + DecayScheduler via `Arc<Mutex<_>>` — current design has each owning its own resources). Recommend (1) for isolation. |
| `~/dev/satan-attrd/src/store.rs` | Add a small helper `bump_last_decay_at(pool, scope, name, now) -> Result<()>` to keep the bump SQL out of `decay.rs`. |
| `~/dev/satan-attrd/tests/decay.rs` | Replace `tick_does_not_mutate_state` with `tick_applies_decay_and_bumps_last_decay_at` + the full §"Tests (T-attr-2e)" matrix split between this PR and 2e — practically 2d's PR covers golden + bump + range_clamp floor; 2e covers catch-up, disable, restart, replay-determinism. |
| `~/dev/satan-attrd/src/types.rs` test mod | Round-trip test for `Source::Maintenance` + `MaintenanceReason::IdleDecay` parses. |

### Reference: how source-event apply works today

`run_loop.rs:586-601` is the canonical pattern (loop over events from a dispatcher, insert event, conditional UPSERT, audit RPC). Decay re-uses **the same shape**, just driven from `decay.rs` rather than the LISTEN payload:

```rust
for ev in &events {
    store::insert_event(&self.pool, ev).await?;
    if !ev.disabled {
        store::upsert_attribute(&self.pool, ev.scope, ev.name,
                                ev.new_value, &ev.evidence_json, ev.ts).await?;
    }
    let audit_payload = build_audit_payload(ev);
    rpc::enqueue_audit_event(&self.pool, &audit_payload).await?;
}
```

The §17.5 contract paragraph "skip UPSERT when disabled" maps to the `if !ev.disabled` guard. The non-bump of `last_decay_at` when disabled is an additional decay-specific rule (not in the source-event loop) — implemented by gating the `bump_last_decay_at` call on the same `!ev.disabled` flag.

### Decay sees `attribute-updates-enabled` via — resolved (2026-05-29, option A)

§15 Q7 resolved → **persistent settings table.** Migration `0012_attribute_settings.sql` introduces `satan_attribute_settings(name TEXT PK, value JSONB NOT NULL, updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW())`. Broker writes `('attribute_updates_enabled', true|false)` on every `satan-attribute-updates-enabled` toggle via `add-variable-watcher`; seeded on first emacs load from the defcustom default (`t`). Daemon `DecayScheduler::tick` SELECTs the row at the start of each tick and threads the boolean into `MaintenanceInput.enabled`, which `dispatch_maintenance` stamps onto each `EventInsert.disabled`. §17.5's apply rule then handles disabled rows unchanged — event written, audit RPC sent, UPSERT skipped, `last_decay_at` NOT bumped (so next-enabled tick still fires). Normative in design-contract §17.5 "Decay path".

Rejected: (B) `pg_notify` + LISTEN cache — over-engineering for a single boolean that flips ≤ once/day; needs startup query anyway. (C) skip-disable-in-v1 — capsule "disabled" render would lie while values silently drifted downward (observability mismatch).

### Catch-up across daemon downtime

Per §8 + §17.8: single-tick. Even if `days_since_last = 5`, emit ONE event with `delta = -0.01` and `evidence_json.days_since_last = 5`. The `MaintenanceInput.days_since_last` field carries the gap for `evidence` rendering; the delta computation clamps to 1 (use `decay_threshold()` quanta, not literal `days_since_last`).

### Per-day Counter strategy

Daily run_id `maintenance:YYYY-MM-DD` (UTC). Recommended: `decay.rs` owns `Mutex<(NaiveDate, Counter)>`. On each event-emit: lock, compare current UTC day, replace with `(today, Counter::new())` if day rolled, allocate `next()`. Avoids cross-cutting the run-loop's LRU.

## Tests (T-attr-2e)

- Golden cases: decay applied to a 0.50 value yields 0.49, audit event well-formed, projection UPSERT correct.
- Catch-up: simulate 5d gap, assert single tick (not 5), assert `evidence_json.days_since_last = 5`.
- Disable switch: layer disabled at tick time, assert event written with `disabled=true`, no UPSERT, `last_decay_at` NOT bumped (so next-enable tick still fires).
- Floor: value at 0.005, one tick yields 0 via range_clamp; subsequent tick is a no-op delta (`0 → 0`, `caps_applied=["range_clamp"]`).
- Restart: daemon restart mid-day, assert hourly tick within 1h, assert no double-fire if `last_decay_at` was bumped pre-crash.
- Replay determinism: synthetic event log with mixed source events + maintenance events, replay yields byte-identical projection. Tests the `(ts, run_id, seq)` ordering with `maintenance:<utc-day>` run_ids.

**Landed (T-attr-2e, 2026-05-29, daemon `~/dev/satan-attrd`).** Five `tests/decay.rs` tests (golden + floor already shipped in 2d):

- `tick_catch_up_emits_single_event_for_multi_day_gap` — 5-day gap → one −0.01, `evidence_json.days_since_last = 5`, delta not multiplied.
- `tick_disabled_inserts_event_and_audit_but_skips_projection` — `disabled=true` event + audit row, no UPSERT, no `last_decay_at` bump; re-enable → next tick fires.
- `tick_survives_scheduler_restart_via_last_decay_at` — fresh scheduler same UTC day is a no-op (state is in `last_decay_at`, not the in-memory counter); next UTC day re-fires under a new `run_id`.
- `rebuild_clears_last_decay_at_so_decay_rearms` — §10.5 rebuild zeros `last_decay_at` → decay re-arms; second rebuild reproduces identical values.
- `tick_restart_while_disabled_same_day_collision` — **probe** (see finding below).

Scope deviation (DRY): generic rebuild skip-disabled / replay-all coverage already exists in `tests/store.rs` (`rebuild_default_skips_disabled_events`, `rebuild_replays_events_in_ts_run_seq_order`). The replay test here asserts only the decay-specific `last_decay_at`-reset + re-arm rather than restating it.

**Finding → T-attr-2f.** The restart probe confirmed a real `(run_id, seq)` collision: the per-UTC-day `seq` Counter is in-memory and resets on restart; on the disabled path `last_decay_at` is never bumped, so cold targets stay due and a same-day restart re-emits identical `(run_id, seq)` rows (the derived `id` PK trips first). 2e ships a **loud guard** — `tick()` maps the violation to `Error::DecaySeqCollision { run_id, seq }` (`tracing::error!` + abort, no projection mutated). The **structural fix** (resume the Counter from `MAX(seq)+1` for today's `run_id` on construction) is deferred to T-attr-2f. Normative wording: design-contract §17.8 "Restart-while-disabled seq collision".

## Catch-up policy (decided)

**Single tick, not N.** Daemon down 5 days, restart: one −0.01 tick fires on the next hourly check, `last_decay_at` jumps to `now`.

Rationale:
- N-tick catch-up at restart compresses 5 days of decay into one moment — operator-visible jump in attribute values that the dispatcher's audit log shows as "single event, 5d worth of delta." Misleading at every point we'd want to read it.
- Single-tick under-counts decay across genuine downtime. The asymmetry is conservative — under-decay errs toward keeping signal, which is the safer failure mode given that the layer's purpose is to bias model behaviour on accumulated wrongness.
- The `evidence_json.days_since_last` field preserves the observability — operators can see "this tick covered a 5d gap" without the projection silently jumping.

If catch-up granularity becomes a real complaint, T-attr-3 can extend to optional N-tick replay behind an operator flag.

## Considered and rejected

- **Broker-side timer.** Emacs `run-with-idle-timer` firing a decay RPC. Rejected per [`extraction-policy.md`](extraction-policy.md): decay is store + dispatcher + audit-emit work, all daemon-owned. Adding a broker timer grows elisp surface for non-editor work, misses ticks when emacs is down, and forks the dispatcher pipeline (broker-RPC path + daemon-internal path). Daemon-side keeps one dispatcher, one event bus, one rebuild story.
- **N-tick catch-up at restart.** See "Catch-up policy" above. Single-tick is conservative and preserves observability via `evidence_json.days_since_last`.
- **`run_id` nullable migration.** Contract §17 floats it as an option. Synthetic `maintenance:<utc-day>` is cheaper — no schema migration, no audit validator surgery, replay determinism preserved without special-casing nulls in the order tuple.
- **Decay on all 8 attributes.** Brief and contract §8 name 4 (negative-pole). The positive-pole attrs (Cruelty/friction, Curiosity, Suspicion, Hunger) have their own dynamics: friction is derived (not stored), and the others ratchet via sources that already have negative-net reasons (e.g. `trace_marked` on Curiosity). Adding decay to them risks zeroing out signal that is supposed to persist.
- **Decay magnitude tied to confidence weighting.** Confidence applies to source events with an evidence base. Decay has no evidence — it is the absence of evidence. Uniform −0.01/day matches brief recommendation; revisit if production shows uniform-decay over- or under-corrects vs the 4 targets' real arrival rates.
- **Decay event omitted from audit transcript.** Considered for event-volume reasons (4 attrs × 365 days = 1460 events/year just from decay). Rejected — audit-truth convention from T-attr-1a contract §17.1 is firm: every projection mutation has an event row. Compaction is a T-attr-3 concern if volume becomes a real cost.

## First concrete step

T-attr-2a contract amend PR. One commit on `~/dev/satan-attrd` companion + broker tree, no code:

- `docs/satan/attributes/design-contract.md` §8 rewritten, §15 Q2 resolved, §17 widened, §16 row added.
- This theme doc flips `metadata.status: not-started → in-progress`.
- `plan.md` status table + Cross-cutting decision text updated (the decision recorded as: T-attr-2 lands before T-attr-1d).

## Migration sketch

- T-attr-2a: one PR, contract amend + this theme doc. No code.
- T-attr-2b: one PR — `0011_attribute_decay.sql` migration + backfill.
- T-attr-2c: one PR — scheduler infra (Clock trait + `decay.rs` skeleton + interval task, no firing yet).
- T-attr-2d: one PR — decay application + audit emit + `last_decay_at` bump + integration with disable switch.
- T-attr-2e: one PR — catch-up + disable + restart + replay-determinism tests (golden + floor shipped in 2d). **Landed 2026-05-29**; surfaced the restart-while-disabled seq collision (loud guard shipped, structural fix → 2f).
- T-attr-2f (opened by 2e): resume the per-UTC-day `seq` Counter from `MAX(seq)+1` for today's `run_id`, so a mid-day restart while disabled no longer collides on `(run_id, seq)`. **Landed 2026-05-29** (daemon `b4ceee1`). Shipped as `src/decay.rs` (`acquire_day_counter` resumes on rotation, lazily on first due tick rather than in `new()`) + `store::max_seq_for_run` + `Counter::resuming_from`; the 2e probe flips to `tick_restart_while_disabled_same_day_resumes_cleanly`. Loud `Error::DecaySeqCollision` retained as defence-in-depth. See design-contract §17.8.

Order is firm 2a → 2b → 2c → 2d → 2e. Each PR independently reviewable; only 2d flips behaviour observable in the broker.

## Sequencing against T-attr-1d

**Decision (2026-05-29):** T-attr-2 lands before T-attr-1d. See [`plan.md`](plan.md) §"Cross-cutting" for the recorded rationale.

The capsule render (1d) needs a substrate whose values mean something. Decay first means:

- 1d's first-impression UX renders meaningful homeostasis, not drift-to-ceiling.
- 1e's remaining source magnitudes (percept/resonance/tool_error) are tuned against a substrate where positive nets do not silently accumulate.
- Capsule-render thresholds (bar widths, "high pressure" cutoffs) are set against realistic value distributions, not against a saturating substrate that would force re-tuning post-2.

Cost trade is small: under extraction-policy framing, T-attr-2 in Rust is comparable in effort to T-attr-1d in elisp. The "ship visible surface sooner" argument for 1d-first is outweighed by the rework cost of tuning 1d twice.

## Open questions

Carry into contract §15 as Q7+ on amend:

- **Q7. Decay magnitude per attribute.** Brief recommends uniform −0.01/day. Production may show Doubt decays "too fast" relative to Shame (which is meant to be durable wrongness memory). Defer to T-attr-3 if production data warrants.
- **Q8. Audit-event compaction.** 1460 decay events/year is small but compounds across attribute count + retention horizon. Compaction policy out of T-attr-2 scope; revisit if `satan_attribute_events` row count crosses an operationally-felt threshold.
- **Q9. UTC vs local-day boundary.** UTC chosen for determinism. If operator-visible decay timing matters (e.g. "Shame decayed during my morning standup, which felt wrong"), revisit. Out of v1 scope.

## Acceptance

When this theme is done:

- Contract §8 is normative on decay; §15 Q2 resolved.
- `satan-attrd` runs a scheduled hourly task; decay events appear in `satan_attribute_events` at daily cadence.
- Operator can disable the attribute layer; decay pauses cleanly; re-enable resumes from the next tick.
- Production observation over ≥7 days shows Doubt+Shame drifting downward from the fixture-pinned 0.50, Curiosity not ratcheting indefinitely, capsule (when 1d lands) renders meaningful homeostasis.

## PR log

- **T-attr-2a — contract amend (2026-05-29, broker commit `9c5ee77`).**
  Bundles three decisions into the design contract in one pass:
  1. §8 rewritten as normative — daily `−0.01` decay on the 4 negative-pole
     attributes, daemon-side per new §17.8, single-tick catch-up, synthetic
     `maintenance:<utc-day>` run-ids. §15 Q2 resolved. §13 "Automatic decay"
     and "Maintenance / decay events" non-inferables flipped.
  2. §10.5 — `satan-attrd rebuild` is from-zero, not replay-on-top.
     Resolves the daemon-pin question.
  3. §17.4 — JSON wire-shape requirements: `null`/`[]`/`{}` distinct, no
     `{}` substitution for the first two.
  §16 row added covering all three.

- **T-attr-2a-fix-broker-json-roundtrip — broker commit `c263444`.**
  Resolves §17.4 wire-shape requirement in code.  Investigation found the
  daemon-side constructors (`build_audit_payload`, `enqueue_audit_event`,
  `outcome_evidence`) were already correct; the offender was the broker's
  `satan-attribute-listener--claim-row` parse using
  `:array-type 'list :null-object nil`, collapsing JSON `null` + `[]` to
  elisp `nil` which `json-serialize` re-emitted as `{}`.  Fixed by
  switching to `:array-type 'array :null-object :null`.  Validator
  widened: `satan-audit--iv-require-array` accepts vectors;
  `satan-audit--validate-attribute-caps` uses `seq-doseq`.  New
  roundtrip ert proves daemon-shaped JSON survives.  Contract §17.4
  "Locus" subsection + §16 row added 2026-05-29 to record the diagnostic
  correction.

- **T-attr-2a-fix-daemon-rebuild-from-zero — daemon commit `fb2b33d`
  (`~/dev/satan-attrd`).**  Resolves §10.5 in code.  `rebuild_projection`
  now wraps in a single transaction: `UPDATE satan_attributes SET
  value=0.0, evidence_json='{}'::jsonb` first, then replay events
  ordered by `(ts, run_id, seq)`.  Both default-replay and
  `--include-disabled` modes zero first.  New
  `rebuild_is_from_zero_when_event_log_is_empty_for_scope` test proves
  the smoke-purge scenario yields zero projection without operator UPDATE.
  `REBUILD_LOCK` mutex serializes rebuild tests within the binary.
  `last_decay_at` column reset deferred to T-attr-2b when the migration
  adds the column.

- **T-attr-2c — scheduler skeleton (2026-05-29, daemon commit `d7f8b89`
  in `~/dev/satan-attrd`).**
  1. `src/clock.rs` — `Clock` trait (`fn now(&self) -> DateTime<Utc>`),
     `SystemClock` production impl, `FakeClock` test impl with
     `set` / `advance` and interior-`Arc<Mutex>` shared state.
     Unconditional (not `cfg(test)`-gated) because integration tests
     link against the lib as a separate crate.  Reads contract-pinned
     `TIMESTAMPTZ` wallclock; `tokio::time::pause` would only affect
     tokio's `Instant`.
  2. `src/decay.rs` — `DecayScheduler<C: Clock>`.  `DECAY_TARGETS =
     [Shame, Doubt, Brooding, Metamorphosis]` per §8.  Hourly
     `tokio::time::interval` with `MissedTickBehavior::Delay` so a
     runtime stall does NOT burst-catch-up (single-tick rule §8).
     `check_due()` is a pure read returning rows where `(now -
     last_decay_at) ≥ 24h OR last_decay_at IS NULL`, filtered to
     `DECAY_TARGETS` in a configurable scope (production: `"global"`,
     tests: unique scope for isolation).  `tick()` calls `check_due`,
     logs the set, returns the count — **no firing yet**.  T-attr-2d
     will extend `tick` to dispatch synthetic `(maintenance,
     idle_decay)` events + bump `last_decay_at`.
  3. `src/main.rs` `run` subcommand spawns `DecayScheduler` alongside
     `RunLoop` via `tokio::select!` — either future returning
     terminates the daemon.  Scheduler errors are logged and the loop
     continues.
  4. `tests/decay.rs` — 6 integration tests covering NULL =
     due, 25h stale = due (`days_since_last = Some(1)`), 23h stale =
     not due, non-target attributes (Curiosity at NULL) excluded,
     mixed freshness (2 stale + 2 fresh → 2 reported), and the
     skeleton-boundary guard: `tick_does_not_mutate_state` asserts
     no row value change, no `last_decay_at` bump, and zero
     `satan_attribute_events` writes — to be inverted by 2d.
  5. 93/93 daemon tests pass (62 unit + 8 dispatcher + 5 run_loop +
     12 store + 6 decay).

- **T-attr-2b — schema migration + projection field (2026-05-29, daemon
  commit `58e7bba` in `~/dev/satan-attrd`).**
  1. `migrations/0011_attribute_decay.sql` — `ALTER TABLE
     satan_attributes ADD COLUMN last_decay_at TIMESTAMPTZ NULL` +
     backfill `SET last_decay_at = NOW()` on existing rows.  Backfill
     prevents the first post-deploy hourly scheduler tick (T-attr-2c)
     from synthesising a multi-day catch-up against pre-migration
     values, per §17.8 "Catch-up across migration / rebuild".
  2. **Migration slot rename.** Contract-pinned filename was
     `0008_attribute_decay.sql` at 2a-amend time; slot 8 was already
     taken by `0008_outcome_inbox.sql` which landed between 2a and 2b.
     Migration renamed to next free slot `0011_`.  Contract §17.8 +
     this theme doc + `plan.md` filename references updated; §16
     change-history row records the slot reassignment.
  3. `src/store.rs` — `AttributeRow` gains `last_decay_at:
     Option<DateTime<Utc>>`.  `None` means "decay has never run for
     this row" (fresh insert / post-rebuild reset); `Some(ts)` is the
     wallclock of the last successful tick.  `lookup_attribute` SELECT
     extended.
  4. `rebuild_projection` §10.5 zero-step now also resets
     `last_decay_at = NULL` (the deferral from 2a's `fb2b33d` is now
     resolved — column exists).  Per §17.8: rebuild is an
     operator-triggered reset; the scheduler treats post-rebuild rows
     as "decay never ran" and fires on the next hourly check.
  5. `tests/store.rs:rebuild_is_from_zero_when_event_log_is_empty_for_scope`
     extended: seeds `last_decay_at = NOW()` on the pre-rebuild row,
     asserts NULL post-rebuild — proves the zero-step clears the
     column rather than relying on the column's default NULL.
  6. 85/85 daemon tests pass (60 unit + 8 dispatcher + 5 run_loop +
     12 store).

T-attr-2c, 2d, 2e, and 2f all landed 2026-05-29 (see CHANGELOG.md for the
per-commit record). 2d extended `DecayScheduler::tick` to dispatch
synthetic `(source=maintenance, reason=idle_decay)` events through the
dispatcher pipeline + bump `last_decay_at`; 2e added the integration
matrix and the restart-while-disabled seq-collision guard; 2f closed that
gap structurally.

**T-attr-2f landed (2026-05-29, daemon `b4ceee1`).** The per-UTC-day `seq`
Counter now resumes from the persisted `MAX(seq)+1` for that day's `run_id`
on each UTC-day rotation (`store::max_seq_for_run` + `Counter::resuming_from`),
so a mid-day restart while disabled allocates a fresh seq range instead of
colliding on `(run_id, seq)`. **Scope refinement:** resume runs lazily on the
first due tick rather than literally in `DecayScheduler::new` — equivalent for
the collision guarantee (nothing emits between construction and first tick),
keeps `new()` sync and IO-free, and covers genuine day-rolls uniformly via
`acquire_day_counter`. The loud `Error::DecaySeqCollision` guard is kept as
defence-in-depth. The 2e probe flips from "collides loudly" to "resumes
cleanly" (`tick_restart_while_disabled_same_day_resumes_cleanly`); + 2
`Counter::resuming_from` unit tests. 107 daemon tests green (69 unit + 38
integration); lint + fmt clean. See design-contract §17.8.

The theme is feature-complete; remaining open thread is the baseline `just lint`
env note (4 pre-existing `expect_used` denials in mutex locks) — **also cleared
2026-05-29** (daemon `b99d8b3`): the `FakeClock` + `day_counter_state` mutex
guards now recover from poisoning via `unwrap_or_else(into_inner)` instead of
`expect`, so `just lint` is green at baseline.
