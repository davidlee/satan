# SATAN reports on SATAN: one emit seam, record before emit, persistent failures stay loud

## Context

SATAN's scheduled `motd`/`morning` runs failed at turn 0 for ~3 weeks
(ISS-012) and nothing got through to the user. Preflight (2026-09-23) found that
the silence was not one broken path but four independent defects in how SATAN
reports on itself:

1. **A persistent failure announces once.** `satan-broker--announce-failure`
   (`satan/satan-broker.el:331`) notifies only when
   `satan-broker--failure-streak-count` is exactly 1. The first failure fired at
   07:47, possibly to an empty room; every later one reached only the journal.
2. **The failure class is dropped.** The harness classifies errors
   (`classify_error`, `satan/harness/runloop.py:115` — `auth` / `rate_limit` /
   `server` / `timeout` / `unknown`) and emits `class` in its error JSON. The
   broker never reads it, so an auth failure is announced — once — as a generic
   failure. (IMP-005, narrow part.)
3. **Alerts are emitted and not recorded.** `satan-tool/notify-send`
   (`satan/satan-tools-notify.el:56→65`) fires the D-Bus notification *before*
   `satan-intervention-create`. For pre-spawn sensor alerts the create signals
   (`satan-intervention--ctx-required`, `satan/satan-intervention.el:332`,
   demands `:audit`), so the user sees the alert, no intervention row exists,
   the cooldown never arms, and the observer is blind (ISS-016). Root cause:
   **two parallel tool-ctx builders** — `satan-run-tool-ctx`
   (`satan/satan-run.el:225`, carries `:audit`) and
   `satan-sensor-alerts--make-tool-ctx` (`satan/satan-sensor-alerts.el:297`,
   omits it). (ISS-016's own text blames docstring drift; the docstring at
   `satan-tools-notify.el:35` already lists `:audit`, so that diagnosis is stale.)
4. **The test suite writes into the evidence base.** Emits are unstubbed at
   the process level: `logger` (`satan-broker.el:339`) is an external process
   `cl-letf` cannot intercept, and per-file stubs of `notifications-notify` miss
   paths. `just test` writes plausible `satan[PID]` lines into the journal that
   SATAN's diagnostics read (ISS-015).

Governing requirement: **SPEC-001 REQ-003** — every enacted action and control
decision is appended to a durable, immutable audit log; authority-ledger row 4
(append-only audit, owner `emacs-client`, enforced at `satan-audit-record`).
Defect 3 is REQ-003 non-conformance; defect 4 corrupts the log REQ-003 protects.

## Scope & Objectives

1. **One emit seam.** Route every user-facing emit through a single announcer:
   the four `notifications-notify` sites (`satan-broker.el:346`,
   `satan-tools-notify.el:56`, `satan-attribute-listener.el:272`,
   `satan-patch-listener.el:109`) and the `logger` call (`satan-broker.el:339`).
   The seam is inhibitable once for the whole batch run, so test hermeticity is
   the harness's job, not each test file's. (ISS-015)
2. **One tool-ctx builder.** Pre-spawn and in-run contexts come from one
   constructor, so a key the write API requires cannot be present in one and
   absent in the other. (ISS-016)
3. **Record before emit.** A notification whose record fails is not sent; the
   record is the precondition of the side effect, not its aftermath. The
   per-cause cooldown arms on the record. (ISS-016, REQ-003)
4. **Persistent failures stay loud.** Replace the `streak == 1` gate with an
   escalation policy that re-announces a failure streak on a schedule rather
   than once. The policy is defined over a **run-outcome streak**, not over
   `failed` specifically, so a later "deferred N times" state (the AUTH slice's
   `vault_locked` deferral) can consume it without redesign. (ISS-012 loudness)
5. **Failure class reaches the record and the announcer.** Carry the harness's
   `class` into the failed run's record and the announcement; an `auth`-class
   failure escalates regardless of streak position. (IMP-005, partial)

## Non-Goals

- **Credential acquisition** — how an unattended run obtains a key, deferral
  when the vault is locked, cache warming, `my/op-read` blocking. That is the
  AUTH slice (ISS-012 credential half + IMP-021), sequenced after this one.
- **IMP-005's full scope** — a typed, provider-agnostic exception layer that
  resilience logic branches on (retry/backoff; RSK-001's 429 handling). This
  slice only transports the class the harness already computes.
- **satan-patcher** (Rust) and its own resolve/retry path.
- **Ledger row 4's dual-write ⚠** (`satan-audit-record` vs the attribute
  bridge → `transcript.jsonl`). Adjacent, not fixed here; this slice must not
  add a third writer.
- **ISS-013** (concurrent `just check` clobbers test DBs) — same hermeticity
  family, different mechanism.
- `dl-secret.el`'s own `my/op--announce` notification (lives in `~/.emacs.d`,
  outside the package).

## Affected surface

- `satan/satan-broker.el` — `announce-failure`, failure-streak gate, failed-run
  record (class)
- `satan/satan-tools-notify.el` — emit/record ordering
- `satan/satan-sensor-alerts.el` — synthetic tool-ctx, cooldown arming
- `satan/satan-run.el` — `satan-run-tool-ctx` (the surviving builder)
- `satan/satan-intervention.el` — `--ctx-required` contract
- `satan/satan-attribute-listener.el`, `satan/satan-patch-listener.el` — emit
  sites
- `satan/harness/runloop.py` — error `class` (read, possibly widened)
- `satan/test/` + `justfile` `test` recipe — batch-wide inhibit

## Risks & assumptions

- **R1 — record-before-emit changes failure semantics.** Today a DB outage
  still lets the notification through; after, a DB outage silences alerts.
  Whether an emit-with-degraded-record fallback is needed is a design question
  (see OQ-2).
- **R2 — escalation can become nagging.** Re-announcing a streak needs a cap or
  back-off, and quiet-hours interaction (`satan-tick-quiet-p`) must be decided.
- **A1** — the harness `class` heuristic is good enough to escalate on `auth`
  without a typed layer. (String match on `auth`/`401`/`403`.)
- **A2** — pre-spawn has, or can cheaply acquire, a real audit handle (the run
  dir exists before perceive; `satan-broker-run` creates it).

## Open questions

- **OQ-1** — ISS-016's decision: does the pre-spawn ctx gain a real `:audit`
  sink, or does `satan-intervention` relax `:audit` for pre-spawn callers? With
  one builder (objective 2) this becomes "where does the pre-spawn audit handle
  come from", but it still decides what the audit trail contains.
- **OQ-2** — on record failure, suppress the emit entirely, or emit with a
  degraded marker? REQ-003 favours suppress; operability favours emit.
- **OQ-3** — escalation cadence and cap; interaction with quiet hours.
- **OQ-4** — does the escalation state live in the runs dir (derived from run
  bundles, as the streak is today) or in its own record?

## Verification / closure intent

- Batch-wide inhibit proven: a full `just test` run produces **zero** `satan`
  journal lines and zero D-Bus notifications (checked against `journalctl -t
  satan --since` bracketing the run).
- Every pre-spawn sensor alert that emits has an intervention row; a forced
  record failure produces no emit (or the OQ-2 marker).
- A synthetic failure streak of N re-announces per the OQ-3 policy; an
  `auth`-class failure announces at any streak position.
- One tool-ctx constructor: `rg` finds a single builder; the synthetic builder
  is gone.
- REQ-003 coverage recorded for the notify path at audit.

## Summary

Make every SATAN alert go through one seam that tests can silence, record
before it emits, and keep announcing a failure that persists — so that the next
three-week silent outage is impossible and the journal stays trustworthy
evidence.

## Follow-Ups

- AUTH slice (ISS-012 credential half + IMP-021) consumes objective 4's
  run-outcome escalation for its deferral state.
- IMP-005 remainder: typed exception layer for resilience branching.
