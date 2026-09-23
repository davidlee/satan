# SATAN reports on SATAN: one emit seam, record before emit, persistent failures stay loud

## Context

SATAN's scheduled `motd`/`morning` runs failed at turn 0 for ~3 weeks
(ISS-012) and nothing got through to the user. Preflight (2026-09-23) found that
the silence was not one broken path but four independent defects in how SATAN
reports on itself:

1. **A persistent failure announces once.** `satan-broker--announce-failure`
   (`satan/satan-broker.el:331`) notifies only when
   `satan-broker--failure-streak-count` is exactly 1. That streak is global
   across modes and keys only on the `.FAILED` suffix, so the last pop was
   2026-09-22 09:16 (streak 1). Every failure on 09-23 (07:47 onwards, streak ≥ 2)
   reached only the journal (ISS-017; research ✓).
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
4. **The test suite writes into the evidence base.** Emits are stubbed per
   file, and the stubs miss paths. The budget-denied tests
   (`satan/test/satan-broker-test.el:427, 481, 681`) reach `announce-failure`
   unstubbed. `just test` therefore writes plausible `satan[PID]` lines into the
   journal that SATAN's diagnostics read, and fires real D-Bus pops (ISS-015).
   (Scoping claimed `cl-letf` cannot intercept `logger`. It can
   (`satan-broker-test.el:188`); the leak is missing stubs.)

Governing requirement: **SPEC-001 REQ-003** — every enacted action and control
decision is appended to a durable, immutable audit log; authority-ledger row 4
(append-only audit, owner `emacs-client`, enforced at `satan-audit-record`).
Defect 3 is REQ-003 non-conformance; defect 4 corrupts the log REQ-003 protects.

## Scope & Objectives

1. **One emit seam (DEC-017).** Route every user-facing emit through
   `satan-announce` (new `satan/satan-announce.el`). Callers pass their `:app`,
   and the function-valued sink `satan-announce-sink` delivers.
   - In scope: the four `notifications-notify` sites (`satan-broker.el:346`,
     `satan-tools-notify.el:56`, `satan-attribute-listener.el:272`,
     `satan-patch-listener.el:109`) and the `logger` call (`satan-broker.el:339`).
   - Out of scope: `message` and `display-warning`, which are Emacs-local.
   - `satan-test-run-batch` (`dev/satan-test.el`) installs a recording sink once
     before loading tests. Tests assert on that recorder, and the per-file emit
     stubs are removed.
   - Production code never branches on `noninteractive`. (ISS-015)
2. **One tool-ctx builder (DEC-016).** `satan-broker--spawn` makes the
   `satan-run` struct right after `satan-audit-open`. Pre-spawn sensor alerts
   receive `(satan-run-tool-ctx run-ctx)` as `:tool-ctx`.
   - `satan-sensor-alerts--make-tool-ctx` is deleted.
   - `satan-intervention--ctx-required` is unchanged.
   - Pre-spawn interventions mint as `<run-id>.ivNNN`. (ISS-016)
3. **Record before emit (DEC-018).** `satan-intervention-create` splits into
   *record* (validate, then audit append) and *project* (psql). `notify_send`
   runs record → announce → project.
   - If the append fails, nothing is emitted.
   - If the projection fails, the tool returns ok with `projection_failed`.
   - The per-cause cooldown arms on the record.
   - Broker failure announces follow the run bundle, which is their record.
   - Listener-death alarms are explicitly *unrecorded operational alarms*: a
     `:journal` line only, no third audit writer. (ISS-016, REQ-003)
4. **Persistent failures stay loud (DEC-014, DEC-015).** Two parts:
   - **The streak.** `satan-run-outcome-streak MODE COUNTS-P SKIPS-P` in
     `satan-run.el` does a per-mode walk over run bundles. An outcome is the
     status plus the `final.json` reason. The failure streak steps over
     `session_blocked` and `credential_deferred`.
   - **The announce policy.** Re-announce at streak positions 1, 2, 4, 8 and
     so on.
     - `auth`-class failures always announce, at critical urgency.
     - `budget-exceeded` announces only at position 1.
     - The journal line is written for every failure.
     - D-Bus pops are suppressed while `satan-tick-quiet-p` holds.

   SL-018 consumes the same streak for `credential_deferred`.
   (ISS-017, ISS-012 loudness)
5. **Failure class becomes the recorded reason (DEC-019).**
   `satan-broker--on-error` parses the harness `class` into a new `satan-run`
   `error-class` slot.
   - An unclassified error records `unknown`.
   - The synthesised `final.json` carries `:reason <class>`, and
     `crash-context` carries `:error_class`.
   - The announce line says the class.
   - `runloop.py` is unchanged. (IMP-005, partial)

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

- `satan/satan-announce.el` (new): `satan-announce` and `satan-announce-sink`,
  with a production sink and a recording sink
- `satan/satan-broker.el`: `announce-failure` (seam, DEC-015 policy),
  `--failure-streak-count` (replaced), `--on-error` / `--crash-context` /
  `--failure-reason` / finalize (class), `--spawn` (struct hoist)
- `satan/satan-run.el`: `satan-run-outcome-streak` and the `error-class` slot
- `satan/satan-tools-notify.el`: record → announce → project
- `satan/satan-intervention.el`: `-create` split into record and project
- `satan/satan-sensor-alerts.el`: takes `:tool-ctx`; synthetic builder deleted
- `satan/satan-attribute-listener.el`, `satan/satan-patch-listener.el`: emit via
  the seam
- `dev/satan-test.el`: the recording sink
- `satan/test/**`: per-file emit stubs removed. Sensor and notify suites use
  the real record step.

## Risks & assumptions

- **R1: record-before-emit could silence alerts during a DB outage.**
  Resolved by DEC-018: the audit append gates the emit, not the psql projection.
- **R2: escalation could nag.** Resolved by DEC-015: doubling back-off, and
  `budget-exceeded` announces only at position 1.
- **R3: listener-death alarms stay unrecorded.** Recording them would need a
  third audit writer, which ledger row 4 forbids. They are documented as
  operational alarms. A REV to the row 4 standing note names them.
- **R4: intervention id shape changes.** Pre-spawn ids become
  `<run-id>.ivNNN`. Check the observer and the IMP-001/IMP-002 cross-checks at
  execution.
- **R5: DEC-015's quiet-hours suppression is inert.** It does nothing until
  `satan-tick-quiet-hours` is set again (`satan-tick.el:24`).
- **A1: holds only for provider 401/403.** The harness `class` heuristic
  catches those. Init-path failures (`KEY not set`, `runloop.py:178`) record
  `unknown` until SL-018 moves key resolution before spawn.
- **A2: confirmed, and stronger than stated.** The audit handle already exists
  at the sensor-alerts call (`satan-broker.el:612-636`).

## Open questions

All resolved by the design run on 2026-09-23:

| question | subject | resolved by |
|---|---|---|
| OQ-1 | the pre-spawn audit handle | DEC-016 |
| OQ-2 | suppress vs. emit with a marker | DEC-018 |
| OQ-3 | re-announce cadence and quiet hours | DEC-015 |
| OQ-4 | where escalation state lives | DEC-014: derived from bundles, per mode |

## Verification / closure intent

- **The recording sink is proven.** A full `just test` run under
  `SATAN_DB_HOST=/run/postgresql/`, with counts reported, adds **zero** `satan`
  journal lines (`journalctl -t satan --since` bracketing the run) and fires
  zero D-Bus pops.
- **Record before emit holds.** A pre-spawn sensor alert that emits has an
  `intervention.created` audit line and a joining `<run-id>.ivNNN` id.
  - A forced append failure emits nothing.
  - A forced projection failure still emits, and the cooldown arms.
- **The streak and the back-off behave per DEC-014 and DEC-015.** A synthetic
  per-mode streak announces at positions 1, 2, 4 and 8 only.
  - An `auth` failure announces at every position.
  - `budget-exceeded` announces only at position 1.
  - An interleaved `session_blocked` run is stepped over.
  - Other modes' runs do not reset the streak.
- **Class transport works.** A harness error carrying `class: auth` yields a
  `final.json` with `reason: "auth"` and an announce line that says `auth`.
- **Selectors.** Each is checked with `rg`:
  - `satan-sensor-alerts--make-tool-ctx` has zero hits.
  - `notifications-notify` and `"logger"` appear only in `satan-announce.el`.
- **REQ-003 coverage.** Recorded for the notify path at audit.

## Summary

Make every SATAN alert go through one seam that tests can silence, record
before it emits, and keep announcing a failure that persists — so that the next
three-week silent outage is impossible and the journal stays trustworthy
evidence.

## Follow-Ups

- SL-018 (AUTH) consumes DEC-014 (streak), DEC-015 (position rule) and
  DEC-019 (`auth` reason) for its deferral escalation and cache eviction.
- REV candidates:
  - The ledger row 4 standing note: name the non-audit emit channels (R3).
  - A SPEC-001 REQ-003 acceptance criterion: "a side effect whose record
    fails is not enacted".
- Memory mem_eb8e5cff794c48bd86597f94fa50b0ac: correct its `session_blocked`
  streak claim after this slice lands.
- IMP-005 remainder: typed exception layer for resilience branching.
