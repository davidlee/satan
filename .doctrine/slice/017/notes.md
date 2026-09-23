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

## PHASE-03 executed (2026-09-23) — GREEN

Capsule worker (sonnet — keeper's model choice for PHASE-01..03; PHASE-03 is
two small, independent, fully-specified changes (design sec-7, T1-T10), no
new design judgement). In-tree, no worktree isolation.

- **`satan-run.el`:** `failure-reason` slot appended last on `cl-defstruct
  satan-run` (EX-1). Requires unchanged.
- **`satan-broker.el`:** new pure `satan-broker--error-class OBJ` (parses
  `:error` as JSON, returns `:class` string or `"unknown"`, guarded with
  `ignore-errors` for non-JSON input) placed next to `--on-error`.
  `--on-error` writes the slot via `unless` (first write wins). `--crash-
  context` gained `:failure_reason`. `--finalize` synthesises `(:status
  "invalid" :reason FAILURE-REASON)` for `satan-audit-close` via a new
  `final-for-audit` local, only when `final` is nil and the slot is set —
  the earlier output-handler/partition use of the raw `final` is untouched.
  `--failure-reason` gained the middle precedence clause (final's `:reason`
  → `failure-reason` slot → status name).
- **Harness (`satan/harness/runloop.py`, `satan/harness/test_gptel_harness.py`):**
  `classify_error` rewritten to design's target — `status_code` first (401
  auth, 402 credits, 429 rate_limit, ≥500 server), then word-boundary regex
  fallback; 403 has no status-code branch (falls through to the text match,
  so a 403 with auth wording still reads `auth`; a moderation 403 reads
  `unknown`). Added `import re` (was missing). Test file:
  `test_classify_auth_403` renamed to `test_classify_403_moderation_is_
  unknown` and its assertion flipped to `"unknown"` (A3 — EX-3 and VT-2
  name the same single change two ways); added `test_classify_by_status_
  code` (401/402/429/500/503 via a `.status_code`-bearing exception) and
  `test_classify_no_substring_false_positives` ("generate", "author",
  "4013 tokens" all → `"unknown"`).
- **`satan-broker-test.el`:** three new VT-1 tests —
  `satan-broker/error-class-parsed-from-harness-json`,
  `satan-broker/error-class-unknown-for-plain-string`,
  `satan-broker/failed-run-final-carries-failure-reason`. The third also
  exercises first-write-wins (a second `--on-error` call does not overwrite
  the slot) and the T6 precedence risk named in the sheet (an explicit
  final `:reason` still beats the slot) — folded into the one fixture
  rather than named as separate tests, since the sheet named exactly these
  three.
- **TDD:** harness tests written and run red first (3 failures: two
  assertion flips, one `AssertionError`) before the `classify_error`
  rewrite, then green (54/54). Elisp tests written and run red first (2
  `void-function`, 1 failed `should`) via a standalone `satan-broker-test.el`
  load before the broker edits, then green (31/31 in that file).
- **Gate (elisp):** `SATAN_DB_HOST=/run/postgresql/ just check` → `Ran 1063
  tests, 1059 results as expected, 1 unexpected, 3 skipped` (1060/1056/1/3
  baseline + 3 new tests; the 1 unexpected is the pre-existing
  `satan-db/test-db-available-p-probes-test-host`). `just lint`: all
  `{"ok":true}`.
- **Gate (harness):** `cd satan/harness && python -m unittest
  test_gptel_harness` → `Ran 54 tests ... OK` (52 baseline − 0 removed +
  2 new; the 403 case was renamed in place, not added).
- **Byte-compile** (scratch copy, `-L satan`): `satan-run.el` and
  `satan-broker.el` each carry one pre-existing warning at HEAD
  (`satan-run-mint-id`'s dynamic-variable shadow;
  `_probe-snapshots` not left unused in `satan-broker.el`) — confirmed by
  byte-compiling the unmodified HEAD versions of both files in the same
  scratch copy; no new warnings. No `.elc` left in the tree.
- **Harness deploy (R13):** only `satan/harness/runloop.py` and
  `satan/harness/test_gptel_harness.py` changed under `satan/harness/`.
  The keeper still needs to decide whether to pull the harness push/flake-
  update/home-switch forward to just after this phase, per R13 — the jail
  runs the harness from the GitHub flake input, not this working tree, so
  the new classifier is inert in the live jail until that deploy step runs.
- **Deviation:** none from the sheet's task list (T1-T11 all as specified,
  including A3's rename resolution).
- **STOP guards:** not tripped. `satan-broker--spawn` and `make-satan-run`
  untouched; `--announce-failure`, `--failure-streak-count` and
  `--failure-streak-count`'s callers untouched.

## PHASE-04 executed (2026-09-23) — GREEN

Capsule worker (opus — PHASE-04 restructures `satan-broker--spawn`'s `let*`,
whose ordering is load-bearing, and deletes four parallel tool-ctx builders
across broker / observer / sensor-alerts / intervention-mark / atsatan).
In-tree, no worktree isolation.

- **`satan-run.el`:** new `satan-run-manual-tool-ctx (run-id audit now)` in
  the tool-ctx section — `(:id :mode-name "manual-mark" :time-now :audit
  :capabilities ())`. Requires unchanged (I8); `satan-run-tool-ctx` key order
  unchanged.
- **`satan-intervention-mark.el` / `satan-tools-atsatan.el`:** call
  `satan-run-manual-tool-ctx`; `--build-ctx` and `--intervention-ctx`
  deleted (EX-4).
- **`satan-observer.el`:** `satan-observer-process (tool-ctx &optional
  opts)` — `satan-intervention--ctx-required` first, NOW = ctx `:time-now`,
  persist gets `:ctx tool-ctx`. Deleted: `--ctx-from-run-ctx`, the
  wall-clock fallback, the `:ctx` opt (EX-3). `persist-verdict`'s own `:ctx`
  opt kept (internal transport). A bad ctx now signals even with zero
  pending interventions (A3); the broker call is inside `condition-case`, so
  the tick still proceeds.
- **`satan-sensor-alerts.el`:** `satan-sensor-alerts-check (sensor-status
  &key tool-ctx state-file quiet-p-fn)` (O1); NOW derives from the ctx's
  `:time-now` (one source of frozen time); `--make-tool-ctx` deleted (EX-2).
  A17 rides on the run's `:capabilities` (EX-5).
- **`satan-broker.el` (`--spawn`):** `run-ctx` (same slot list) bound
  immediately after `audit`; the prepare `:audit` plist-put dropped (O2/A1);
  observer and alerts get `(satan-run-tool-ctx run-ctx)`, the alerts ctx
  built at the call site after enrich's sync; all three rebinds use
  `(prepare (setf (satan-run-prepare run-ctx) …))` (A2); inner `run-ctx`
  binding deleted. Stage order unchanged; outer `condition-case` handler
  untouched (PHASE-05). Side effect of A1: the audit handle's `run-ctx`
  (the prepare cons) no longer carries a back-reference to the handle.
- **Docs:** `satan-context.el` docstring `:audit` line removed;
  `docs/governance.md` observer row now says `TOOL-CTX`.
- **Tests:**
  - `satan-run-test.el`: VT-1 `satan-run/manual-tool-ctx-satisfies-ctx-required`
    (exact plist; negative control without `:audit` → `user-error`).
  - `satan-observer-test.el`: VT-3 `satan-observer/process-uses-run-tool-ctx`
    (DB; R0 minted via `satan-run-tool-ctx` → `R0.iv001`, processed on R1's
    tool-ctx at T0+6h → `:mature`, `outcome_classified` in R1's transcript
    only) and `satan-observer/process-rejects-ctx-without-time-now` (pure).
    Ten call sites migrated to a new `--process-ctx` helper
    (`satan-run-manual-tool-ctx` over a fresh audit); `--transcript-events`
    helper added.
  - `satan-sensor-alerts-test.el`: `--mode` replaced by `--with-run` (tmp
    dir + real audit, fixed hex run-id, counter reset) and `--ctx RUN CAPS
    TIME-NOW` (canonical `satan-run-tool-ctx` over a copy of the run).
    EX-6: `--silence-notify` and `dispatch-goes-through-tool-dispatch` now
    stub only `satan-intervention--exec-sql` (via a `--without-db` macro).
    VT-2 `pre-spawn-intervention-joins-run` (new) and
    `capability-denied-still-suppresses` (the old
    `capability-denied-when-mode-lacks-notify`, renamed in place, plus a
    no-`intervention.created` assertion). Eleven call sites migrated. R9: every
    `satan-sensor-alerts-check` call in tests sits under the exec-sql stub or
    (broker-test) stubs the check itself.
  - `satan-broker-test.el`: dec8 stub set extracted to
    `satan-broker-test--with-spawn-stubs DIR` (for PHASE-05 reuse), dec8
    rewritten on it; EX-1 test
    `satan-broker/spawn-hands-run-tool-ctx-to-observer-and-alerts` (enrich
    returns a fresh list; captures observer/alerts ctxs and the filter's
    struct).
- **TDD:** each red observed before green — VT-1 `void-function`; VT-3 red
  for the right reason (wall-clock NOW made the row stale → processed 0) and
  the rejects test red (no signal); sensor tests red on the old signature;
  the broker test red on `observer-ctx :id` nil.
- **Gate:** `SATAN_DB_HOST=/run/postgresql/ just check` → `Ran 1068 tests,
  1064 results as expected, 1 unexpected, 3 skipped` (baseline
  1063/1059/1/3 + 5 new; unexpected is the pre-existing
  `satan-db/test-db-available-p-probes-test-host`; skips unchanged at 3, so
  the observer DB suite ran). `just lint`: all `{"ok":true}`.
- **Byte-compile** (scratch copies of HEAD and the working tree, `-L satan
  -L dev -L satan/test`, all 11 touched `.el` files): warning sets identical
  (pre-existing: `mode-name` shadow in `satan-run.el`, `_probe-snapshots`,
  `satan-pattern-rebuild` unknown, two wide `satan-context.el` docstrings,
  `_captured` in observer tests). No `.elc` in the tree.
- **VA-1:** `rg -n 'make-tool-ctx|ctx-from-run-ctx|mark--build-ctx|atsatan--intervention-ctx|failure-streak-count|satan-context--run-id-regexp' satan/ dev/`
  → only `satan-broker--failure-streak-count` (`satan-broker.el:333, 370`;
  `satan-broker-test.el:152-176`), PHASE-07's. Positive control
  `rg -n 'satan-run-tool-ctx' satan/` hits. EX-1: `rg -n 'make-satan-run'
  satan/satan-broker.el` → one hit (`:642`), the binding after `audit`
  (a 4-line comment sits between them).
- **VA-2 (R4), discharged per sheet — IMP-001/IMP-002 cross-check code does
  not exist (both open, blocked backlog items):** (a) observer half —
  `process-uses-run-tool-ctx` processes a `<run-id>.iv001` minted through
  `satan-run-tool-ctx` and classifies it into the current run's transcript;
  (b) A16 half — `a16-one-to-one-causes-and-entries` green on a real ctx,
  and in `pre-spawn-intervention-joins-run` the fired cause's
  `:last_notified_at` is in the state file (cooldown armed). The live
  evidence is the first degraded run after load (PHASE-08 VH-1).
- **Deviations:** none of substance. `--process-ctx` builds a manual ctx
  (design's wording) — VT-3 uses the canonical builder. The sensor ctx
  helper takes a run struct (tmp audit opened once per test, since
  `satan-audit-open` truncates the transcript) rather than the sheet's
  `(caps time-now)` shape.
- **STOP guards:** not tripped — outer handler untouched, no new
  `notifications-notify`/`logger` stubs, no new `require` in
  `satan-run.el`, `satan-run-tool-ctx` key order unchanged.
- **Findings (candidate backlog, out of scope):**
  - `satan-intervention-mark--run-id-of` (`satan-intervention-mark.el:28`)
    and `satan-tools-atsatan--intervention-run-id-of`
    (`satan-tools-atsatan.el`) are a second parallel pair — both parse
    `<run-id>.ivNNN`. A `satan-run-id-from-intervention-id` beside
    `satan-run-mode-from-id` would finish the job.
  - Test-side ctx builders are still parallel: `satan-observer-test--build-ctx`,
    `satan-intervention-test--build-ctx`, `satan-pattern-test--build-ctx`
    each hand-build a tool-ctx plist; they could build through
    `satan-run-tool-ctx` / `satan-run-manual-tool-ctx`.
  - `satan-sensor-alerts-check` now signals (`date-to-time nil`) on a ctx
    without `:time-now`, rather than using the wall clock; the broker's
    `condition-case` absorbs it. The run's tool-ctx always carries it.

## PHASE-05 executed (2026-09-23) — GREEN

Capsule worker (opus — PHASE-05 is the spawn-failure path: it must tell
pre-child from post-child errors, never double-finalise, always clear the
DEC-8 lock and never leak the stderr buffer; the subtle risk is lexical
scoping of handler-visible bindings (sheet A1/A2) in the broker's most
order-sensitive function). In-tree, no worktree isolation.

- **`satan-broker.el`:**
  - `satan-broker--manifest-or-stub (mode run-id)` (`:421`) — the built
    manifest, or `(:run_id :mode (:name) :manifest_error MSG)` on `error`.
    `--write-no-child-run` uses it (I7 hole closed); `--spawn` keeps the
    strict `--build-manifest` (A6).
  - `satan-broker--percept-bundle (prepare)` (`:434`) — the one definition
    of the mirrored `(:percept …)` bundle, shared by the no-child writer and
    the audit-open failure branch.
  - `--spawn` (`:602`): `run-id`, `stderr-buf`, `run-ctx`, `proc` hoisted
    to an outer `let` around the (single, unchanged-count) `condition-case`
    and assigned with `setq` (A1): `(_run-ctx (setq run-ctx (make-satan-run
    …)))` `:676`; `(satan-trace-stage "spawn.exec" (setq proc (make-process
    …)))` `:801` (A2). The stderr-flush sentinel wrapper moved from after
    the timeout timer to immediately after `setf process` (`:816`, R-A).
    The flush is now guarded by `buffer-live-p` (see deviations). Stage
    order unchanged (R-C): audit_open → observer → enrich → alerts →
    probes → cursor → bundle → exec.
  - Handler (`:848`), in order: clear `satan-run--spawn-running`; child →
    re-signal, touch nothing else; no child → kill `stderr-buf` if live,
    `satan-broker--record-spawn-failure`, return `run-id`.
  - `satan-broker--record-spawn-failure (mode prepare dir run-ctx err)`
    (`:857`): stamps `satan-trace-outcome "spawn_failed"`; audit open →
    `spawn-failed (:error MSG)` record, percept bundle only if
    `bundle-path` is absent, `failure-reason "spawn_failed"` + status
    `'failed`, `--finalize`; no audit → `--write-no-child-run 'failed
    "spawn_failed" :event 'spawn-failed :event-payload (:error MSG) :final
    (:summary "spawn failed: MSG" :actions [] :reason "spawn_failed")
    :rename-announce t`, then clear `satan-memory-store--current-run-id`.
    No direct `--announce-failure` call (A5). Docstrings of `--spawn` and
    `--write-no-child-run` and the DEC-8 handler comment updated.
- **Tests (`satan-broker-test.el`):**
  - T1 refactor (green, count unchanged at 32): new
    `satan-broker-test--with-spawn-collaborators ROOT DIR` (tmp
    `satan-runs-dir` ROOT, DIR = ROOT/run, binds the DEC-8 flag,
    `satan-memory-store--current-run-id` and a tmp hippocampus dir under
    ROOT; stubs the soft stages, env shaping, `--update-most-recent`; also
    stubs `satan-ingest-cursor-advance` — see findings); cleanup deletes
    ROOT, so `DIR.FAILED` goes too. `--with-spawn-stubs DIR` re-expressed
    as collaborators + record-path stubs, signature unchanged; the dec8 and
    PHASE-04 tests are untouched.
  - Helpers: `--spawn-prepare`, `--run-json` (reuses
    `satan-audit--read-json`, no new `json-parse-buffer` copy),
    `--run-status`, `--broker-event`, `--spawn-failing` (runs `--spawn`
    under a `"spawned"` tick accumulator and the announce recorder),
    `--should-spawn-fail` (the shared terminal-shape assertions: run-id
    returned, lock nil, current-run-id nil, no stderr buffer, no
    `satan-<id> stderr` pipe process, outcome `spawn_failed`, status
    `failed`, final `:reason spawn_failed`, `spawn-failed` event with
    `:error`, `verify-run` t, exactly one recorded announcement whose
    `:journal` names `spawn_failed`).
  - New: `no-child-run-survives-broken-manifest` (T2),
    `spawn-error-before-child-finalizes-spawn-failed` (T4; also pins the
    finalize path via a `crash-context` record),
    `manifest-error-finalizes-spawn-failed` (T5),
    `spawn-exec-failure-keeps-context-bundle` (T8),
    `error-after-child-not-finalized-twice` (T6; `sleep 30` child killed
    in `unwind-protect`). No announce/notify/logger stubs (R8).
- **TDD:** reds observed for the right reason — T2 `unknown tool in mode
  test: no_such_tool` propagated; T4 `(error "boom")`, T5 the unknown-tool
  error, T8 `(file-missing "Doing vfork" …)` all re-signalled; T6 failed on
  the leaked stderr buffer (wrapper never installed once the timer threw).
  **A1 mutation check:** re-binding `run-ctx` inside the inner `let*` →
  T4 and T8 red (no `crash-context`: the no-child writer re-opened the
  audit); an inner `(proc nil)` binding → T6 red (`should-error` — the
  handler finalised a live run and returned).
- **Gate:** `SATAN_DB_HOST=/run/postgresql/ just check` (serial) → `Ran
  1073 tests, 1069 results as expected, 1 unexpected, 3 skipped` (baseline
  1068/1064/1/3 + 5 new incl. T8; unexpected is the pre-existing
  `satan-db/test-db-available-p-probes-test-host`; skips unchanged at 3).
  `just lint`: all `{"ok":true}`.
- **Byte-compile** (scratch copies of HEAD and the working tree, `-L satan
  -L dev -L satan/test`, `satan-broker.el` + `satan-broker-test.el`):
  warning sets identical (pre-existing `_probe-snapshots` only). No `.elc`
  in the tree.
- **EX/VT mapping:** EX-1 (I7) — T2, T4, T5, T8 each assert a `status`
  file and `verify-run` t. EX-2 — T6 (finalize count 0 after the handler,
  1 after the sentinel). EX-3 — T4, T5, T8 (lock nil, `get-buffer` nil, no
  stderr pipe process). VT-1 — T4. VT-2 — T2, T5, T6.
- **Rulings (orchestrator):** OQ-A yes (below); OQ-B yes (no-audit branch
  clears `satan-memory-store--current-run-id`); OQ-C yes (no-audit branch
  records `spawn-failed (:error MSG)`); OQ-D yes (T8 added).
- **Deviations:**
  - **R-A / OQ-A — reconcile item for design sec-4.** Design says "Always.
    The handler kills the stderr buffer". Implemented: the handler kills it
    only when there is no child; the stderr-flush sentinel wrapper moved to
    right after `make-process`, so a post-child error leaves the sentinel
    owning (flushing + killing) the buffer. Reason: `kill-buffer` on a
    `:stderr` buffer deletes the `"<name> stderr"` pipe, the live child
    gets EPIPE and the sentinel finalises a killed run. Intent ("the
    sentinel owns it", no leak) holds; the design text needs the wording
    changed at `/reconcile`.
  - The wrapper's flush is guarded by `buffer-live-p` (was an unguarded
    `with-current-buffer`). Not in the sheet. Without it a sentinel firing
    after the buffer is gone raises "Selecting deleted buffer" — under ERT
    in batch (`debug-on-error`) that aborts the whole suite (rc 255), which
    is how the proc-shadowing mutant first showed up; now it is a clean red.
  - `satan-broker--record-spawn-failure` is a named helper called from the
    handler (the handler stays four lines). Still exactly one
    `condition-case` in `--spawn`.
  - `--spawn`'s body keeps its pre-existing (mis)indentation under the new
    outer `let` — re-indenting 230 lines would bury the A1/A2 changes in
    the review diff (R-E). Candidate cosmetic follow-up.
- **STOP guards:** not tripped — no `satan-announce*`/`notifications-notify`/
  `logger` stubs added; one `condition-case`; `--finalize` contract
  unchanged.
- **Findings (candidate backlog, out of scope):**
  - Before this phase, every `--with-spawn-stubs` test (dec8, PHASE-04's)
    ran the real `satan-ingest-cursor-advance`, i.e. wrote the live
    state-root cursor file from the suite. The collaborators helper now
    stubs it. Other suites may still reach it; worth a hermeticity sweep.
  - `satan-broker-test--read-bundle` and four inline `json-parse-buffer`
    copies in `satan-broker-test.el` could go through
    `satan-broker-test--run-json`.
  - R-B (child-branch lock clear lets an MCP session open while the child
    runs) unchanged, as the design keeps it.

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
