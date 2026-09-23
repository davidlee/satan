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

## PHASE-01 executed (2026-09-23) — GREEN

Capsule worker (sonnet — keeper's model choice for PHASE-01..03, mechanical
seam introduction against a T1-T11 sheet, design judgement locked at
dr-01a0cc0b). In-tree, no worktree isolation.

- **New:** `satan/satan-announce.el` (seam: `satan-notify-app` moved,
  `-sink`, `-deliver`, `-record`, `-recorded`, `-with-recorder`; requires only
  `cl-lib` + `satan-custom`). `satan/test/satan-announce-test.el` (VT-1 five
  cases + VT-2 self-check).
- **Routed through the seam:** `satan-broker--announce-failure` (kept 4-arg,
  streak==1 gate, per-A1), `satan-tool/notify-send`, both listeners'
  `--report-death`. `dev/satan-test.el` let-binds `satan-announce-sink` to
  the recorder around `satan-test-run-batch`'s whole load+run.
- **T7 (6 sites) de-stubbed**, all via `satan-announce-with-recorder` or a
  direct `satan-announce-sink` let-bind, none via `notifications-notify`:
  `satan-broker-test.el` (2, rewritten to assert on the recorded plist's
  `:journal`/`:title` presence, not call counts — R8), `satan-tools-notify-
  test.el` (2 — `dispatch-ok`'s literal `42` moved to the recorder's fake id
  and captured plist per A2; `handler-error-propagates` induces failure by
  let-binding `satan-announce-sink` to a signalling lambda, A3 option (a)),
  `satan-patch-listener-test.el` (2), `satan-sensor-alerts-test.el` (2 —
  `--silence-notify`'s counter now increments on `:title`-bearing recorder
  entries), `satan-tools-test.el` (1 — asserts `(null satan-announce-recorded)`).
- **T8 new:** `satan-broker/budget-denied-run-is-recorded-not-delivered` —
  the ISS-015 leak, now caught structurally with no per-test stub.
- **Additional scope (driver decision):** two tests mirroring
  `satan-patch-listener`'s `report-death-*` pair, added for
  `satan-attribute-listener--report-death` (previously untested), asserting
  via the recorder.
- **satan-announce-test.el's 4 delivery tests call `satan-announce-deliver`
  directly**, not `satan-announce` — inside the full suite the harness binds
  `satan-announce-sink` to the recorder, so going through the seam entry
  point would hit the recorder instead of the local `notifications-notify`/
  `call-process` stubs. This is the "own unit tests" exception's actual
  mechanics; worth remembering for any future seam-adjacent test.
- **satan-announce-test.el requires `notifications` eagerly** — otherwise
  `satan-announce-deliver`'s lazy `(require 'notifications)` reloads the real
  definition over a `cl-letf` stub mid-test (same trick already used in
  `satan-patch-listener-test.el`).
- **Gate:** `SATAN_DB_HOST=/run/postgresql/ just check` → `Ran 1053 tests,
  1049 results as expected, 1 unexpected, 3 skipped` (1044/1040/1/3 baseline
  + 9 new tests; the 1 unexpected is the pre-existing
  `satan-db/test-db-available-p-probes-test-host`). `just lint`: all
  `{"ok":true}`. Byte-compile of every new/changed file: clean (three
  pre-existing warnings elsewhere confirmed present at HEAD, untouched).
- **VA-1** (design sec-8 selectors): selector 1 hits only
  `satan-announce.el`; selector 2 (`notifications-notify` in `satan/test/`
  outside `satan-announce-test.el`) came back empty only after rewording two
  test docstrings that named the function in prose (false positives against
  the literal grep, not real stubs).
- **VA-2/V1:** `just check` bracketed with `journalctl -t satan --since/
  --until` — zero lines in the window (journalctl itself verified live via a
  wider `--since` query showing real prior entries).
- **Deviation:** none from the sheet's task list; the delivery-test dynamic-
  scope interaction (above) was not called out in the sheet and was found
  during the gate run, not before.

## PHASE-02 executed (2026-09-23) — GREEN

Capsule worker (sonnet — keeper's model choice for PHASE-01..03; PHASE-02
adds pure leaf functions with fully specified signatures (design sec-3) and a
verified sheet, its only subtlety — walk order (A3) and the no-outcome vs
non-counting distinction (A2) — spelled out in sheet A2/A3). In-tree, no
worktree isolation.

- **New in `satan/satan-run.el`:** `satan-run-id-regexp` (defconst),
  `satan-run-mode-from-id`, `satan-run-outcome`, `satan-run-outcome-streak`
  (MODE COUNTS-P &optional SKIPS-P RUNS-DIR) — inserted before the DEC-8
  lifecycle-state section. Requires unchanged: `cl-lib`, `subr-x`,
  `satan-custom` (EX-2). The streak walk visits newest-first-sorted mode dirs
  once and `nconc`s onto an accumulator in visitation order (A3) — no
  push+reverse.
- **`satan-tank--short-run`** now delegates to `satan-run-mode-from-id`,
  wrapped `(or (satan-run-mode-from-id run-id) run-id)` to keep the existing
  passthrough-on-no-match contract (T5).
- **`satan-context.el`:** `satan-context--run-id-regexp` deleted (EX-3).
  `--list-recent-runs`'s leaf filter and `--summarize-run`'s field extraction
  now build on `satan-run-id-regexp` + `satan-run--id-from-leaf` +
  `satan-run--date-bucket` + `string-suffix-p` (A5 recipe, as suggested).
- **Bug found and fixed in `--summarize-run`:** `satan-run--date-bucket`
  runs its own internal `string-match`, which clobbered the outer
  `satan-run-id-regexp` match-data before `mode` was read via `match-string`
  — caught by `satan-context/summarize-run/extracts-time-mode-summary-tools`
  going red (mode rendered as `"05"`, the month group, instead of
  `"tick-pulse"`). Fixed by capturing `mode` immediately alongside `stamp`,
  before the `date-bucket` call.
- **Test fixture fix:** `satan-tank-test.el`'s `read-run-events-fixture` used
  a non-hex run-id suffix (`fix001`), which the old ad-hoc tank regexp
  tolerated but `satan-run-id-regexp`'s strict `[0-9a-f]{6}` does not.
  Corrected to a valid hex suffix (`f19001`) — the fixture id never matched
  real minted-id shape (`%06x`) to begin with.
- **T7:** six VT-1 tests added to `satan-run-test.el`, by exact name, plus a
  local `satan-run-test--mkrun` fixture helper (real files under a temp
  root, `make-temp-file`/`unwind-protect`, matching the file's existing
  style). `streak-steps-over-skips-and-unfinished` reproduces design sec-3's
  worked example verbatim (position 2, first run `0923T0815`).
- **T9 verification sweep:** `rg -n satan-context--run-id-regexp .` → zero
  hits; `rg -n satan-run-id-regexp .` → four hits (positive control, same
  invocation style).
- **plan.toml note:** VT-3 was drafted and then withdrawn by the driver —
  `plan.toml` carries no diff for this phase. VT-2 greps only
  `satan-tank.el`; EX-3's `satan-context.el` migration is checked only by
  the sheet's T9 zero-hit `rg`, not by an authored VT entry. Flagged here
  for `/audit` + `/reconcile`.
- **Post-review fix (orchestrator round, same day):** review found
  `(satan-tank--short-run nil)` regressed — old code returned `""` for any
  non-match including nil; the new delegation called `string-match` inside
  `satan-run-mode-from-id` on a non-string and signalled. Fixed TDD
  (red/green): `satan-run-mode-from-id` now guards with `stringp` and
  returns nil for any non-string RUN-ID (new assertion in
  `satan-run/mode-from-id-handles-hyphenated-modes-and-failed-suffix`);
  `satan-tank--short-run` restores the nil→`""` contract via
  `(or (satan-run-mode-from-id run-id) run-id "")` (new test
  `satan-tank/short-run-nil-yields-empty-string`).
- **Gate (final, post-fix):** `SATAN_DB_HOST=/run/postgresql/ just check` →
  `Ran 1060 tests, 1056 results as expected, 1 unexpected, 3 skipped`
  (1053/1049/1/3 baseline + 6 VT-1 tests + 1 short-run-nil test; the 1
  unexpected is the pre-existing
  `satan-db/test-db-available-p-probes-test-host`). `just lint`: all
  `{"ok":true}`. Byte-compile of the touched files (scratch-copy,
  `-L satan`): one warning, pre-existing at HEAD and outside this phase's
  edits (`satan-run-mint-id`'s dynamic-variable shadow) — no new warnings,
  no `.elc` left in the tree.
- **Deviation:** none from the sheet's task list beyond the fixture fix, the
  match-data bug, and the post-review nil-regression fix above — none
  anticipated by the sheet, all found during gate/review runs, not before.

## Harvest
<!-- single-copy: updated in place each harvest; ids only, never restated content -->
fresh-as-of: 2026-09-23 · plan authored (8 phases), sheets materialised · slice status ready

### Produced
- SL-017 (this slice)
- ISS-017 — split from ISS-012 (loudness half)
- ISS-016 — root cause corrected (two tool-ctx builders)
- CHR-008 — stale `.doctrine/governance.md:15` gate claim
- DEC-014 through DEC-019 (DEC-015 to DEC-019 amended after RV-009; DEC-016/018/019 again after RV-010); RV-008 (run-bound, concluded empty); RV-009 (14 findings); RV-010 (focused second pass, 10 findings)
- research/research.md (runtime tier, gitignored)

### Learned
- mem.fact.satan.op-prompts-on-session-not-read (new)
- mem.fact.satan.op-read-blocks-emacs-server (rewritten: popup now surfaced)
- mem.fact.satan.op-cache-has-no-invalidation
- mem.pattern.doctrine.design-run-defects (extended: adopt_authored recipe; run-bound RV)

### Open
- next: `/phase-plan` PHASE-01, then `/execute`; deploy the harness before PHASE-07 goes live (plan.md Notes); code review at `/audit` for PHASE-05 and PHASE-06
- backlog to file: record before side effect for sway, inbox, proposal and patch (design sec-5)
- REVs: the ledger row 4 standing note (operational alarms); optionally a REQ-003 acceptance criterion
- memory mem_eb8e5cff794c48bd86597f94fa50b0ac: correct its session_blocked streak claim (after landing)
