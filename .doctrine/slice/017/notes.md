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

## Review passes (2026-09-23)

- **RV-009.** The first adversarial pass: 14 findings, all verified by the
  raiser (F-12 tolerated).
- **RV-010.** A focused second pass on the areas RV-009 widened: the spawn
  handler and the observer change (sec-4), the undelivered path (sec-5), the
  same-cause read (sec-3), and `runloop.py` (sec-7). It raised 10 findings
  (3 major). All are answered: F-8 is tolerated (R12), and the rest are
  fixed. The major ones led to the classify record/project split, the single
  pre-child spawn handler, and `--manifest-or-stub`. The raiser re-checked
  the new material and found only two nits (F-9, F-10), both fixed.

**No third pass is needed.** RV-010's new findings shrank from major to nit on
the re-check, and the remaining risk is implementation detail, which the
named tests in sec-9 pin down. The execution phases that touch the spawn
handler (sec-4) and the classify split (sec-5) should get a code review at
their `/audit`.

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
