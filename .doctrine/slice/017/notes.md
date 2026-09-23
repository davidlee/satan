# Notes SL-017: SATAN reports on SATAN: one emit seam, record before emit, persistent failures stay loud

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## Design triage (2026-09-23, run dr-01a0cc0b)

Evidence: `research/research.md` (runtime tier; ✓ = re-verified).

**Constraining governance.**
- SPEC-001 REQ-003: record the alert before it is sent.
- REQ-009: one ctx contract and one inhibit point.
- REQ-011: every surface.
- REQ-005: kill switches survive.
- ADR-017 ledger row 4: `satan-audit-record` is the one writer, with no third writer. Row 7: quiet hours owned by `satan-tick-quiet-p`.
- DEC-001: `satan-run.el` owns tool-ctx and run discovery. It stays a leaf, so it cannot host the announcer.
- ADR-018 D5: no new elisp state layer.

**Shaping facts (✓).**
- OQ-1 collapses. The live audit handle is in scope at the sensor-alerts call (`satan-broker.el:612-636`), so one builder needs no relaxing of `--ctx-required`.
- OQ-2 splits. `satan-intervention-create` appends to audit (the canonical record) before the psql projection, so "record" = the append.
- Streak defects:
  - It is global across modes and keys only on the dir suffix.
  - A `session_blocked` run *resets* it, contrary to the DEC-8 comment.
  - It must become outcome-aware and per mode for SL-018.
- Class:
  - `class` is double-encoded in `error`, and the init path has none (`runloop.py:178`).
  - It never reaches the run record.
  - `runloop.py` changes deploy only via push + flake lock + home-switch.
- Test leaks come from unstubbed budget-denied tests. The slice claim that the `logger` call can't be stubbed is wrong.
- Timeline: the last failure notify was 2026-09-22 09:16, not 07:47.
- ISS-016 costs more than stated: alerts re-fire every run (221 unarmed dispatches).

**Risks.**
- R1: resolved by OQ-2's split.
- R2: nagging. `budget-exceeded` under re-announce would fire every tick until midnight.
- R3 (new): unrecorded out-of-run emits, i.e. listener deaths. Recording them would need a third writer.
- R4 (new): intervention id shape changes to `<run-id>.ivNNN`. It must still pass the observer and IMP-001/IMP-002 checks.

**Assumptions.**
- A1: holds for 401 only. Init-path missing-key failures are unclassified.
- A2: confirmed and stronger than stated.

## Review passes (2026-09-23, after RV-009 integration)

RV-009 is an adversarial subagent pass that raised 14 findings. All are
disposed: 13 fixed and F-12 tolerated.

The integration widened scope in three places:
- F-4: a spawn failure is now finalised as `spawn_failed`.
- F-9: all five tool-ctx builders move into `satan-run.el`.
- F-5: `runloop.py` changes.

A further focused pass should probe these, all in the design:
- **sec-4, spawn handling.** Does the `condition-case` around the rest of
  `--spawn` interact correctly with the soft-failing stages and with the
  probe commits? Is finalize safe when the error lands before
  `make-process`, given the stderr buffer and the timeout timer?
- **sec-4, the observer change.** `satan-observer-process` now takes a
  tool-ctx instead of `prepare`. Check its ten test references and the `opts`
  path.
- **sec-5, the undelivered path.** Classifying `unknown` right after creation:
  does the classify API accept that timing (maturity guard, `:classified-at`)?
- **sec-3, the same-cause predicate.** Is the newest outcome read from the
  renamed dir on both announce call sites?

The keeper decides at the next session: run the second pass, or discharge
`review.passes` with this note as the reason.

## Harvest
<!-- single-copy: updated in place each harvest; ids only, never restated content -->
fresh-as-of: 2026-09-23 · design reviewing (dr-01a0cc0b, rev 34) · RV-009 disposed

### Produced
- SL-017 (this slice)
- ISS-017 — split from ISS-012 (loudness half)
- ISS-016 — root cause corrected (two tool-ctx builders)
- CHR-008 — stale `.doctrine/governance.md:15` gate claim

- DEC-014 through DEC-019 (DEC-015 to DEC-019 amended after RV-009); RV-008 (auto-opened by the run); RV-009 (adversarial pass, 14 findings)
- research/research.md (runtime tier, gitignored)

### Learned
- mem.fact.satan.op-prompts-on-session-not-read (new)
- mem.fact.satan.op-read-blocks-emacs-server (rewritten: popup now surfaced)
- mem.fact.satan.op-cache-has-no-invalidation

### Open
- design run: `review.passes` (second pass, or discharge), then the user's section review and `design-accepted`; then the `review-disposed` act and lock
- RV-009: the raiser must verify or contest the 14 answered findings (await=raiser)
- backlog to file: record before side effect for sway, inbox, proposal and patch (design sec-5)
- REVs: the ledger row 4 standing note (operational alarms); optionally a REQ-003 acceptance criterion
- memory mem_eb8e5cff794c48bd86597f94fa50b0ac: correct its session_blocked streak claim (after landing)
