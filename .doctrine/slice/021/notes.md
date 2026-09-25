# Notes SL-021: Replay current_window from the desktop event series

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## Harvest
<!-- single-copy: updated in place each harvest; ids only, never restated content -->
fresh-as-of: <yyyy-mm-dd> · <PHASE-NN | stage> · <head-commit>

### Produced

### Learned

### Open

## Design triage (2026-09-26, exploring)

Evidence: `research/research.md` (round 1). G-numbers below are its Thread 1
binding constraints.

### Open questions (shape the design)

- Q1 read path — SATAN tail-reads `raw/desktop-*`, or panopticon emits a
  `segments/current-*` series. Research favours raw: segments lag ≤10 min
  (segmentize timer), re-creating the class-B defect. Departs from IMP-013's
  stated preference (not governance, G-note).
- Q2 liveness — age ceiling only, vs a panopticon producer change
  (periodic heartbeat and/or `compositor_disconnected reason:"shutdown"` on
  cancel). SIGTERM and first connect emit no lifecycle event today.
- Q3 status vocabulary — keep `ok`/`stale-Nm`/`missing`/`malformed`, add
  `disconnected`? Cause-name continuity (cooldown keyed per name; IMP-001).
- Q4 sway — fold partial events in SATAN, degrade, or niri/umbriel-only
  (no sway data exists live).
- Q5 day lookback — today's file then yesterday's only? Local date from
  parsed instant (ISS-021).
- Q6 read strategy — tail scan for the live case; full scan acceptable for
  past windows (observer)? Lenient to malformed lines?
- Q7 `activity_read` `current` scope — share the reader or leave live.

### Risks

- Cross-repo deploy ordering if Q2 takes the producer path (G8/REQ-015).
- Reader cost on the cue-only resonance path (1–4 MB/day files).
- DEC-013: compositor `app_id` transiently mislabelled; replay inherits it.

### Assumptions

- A1 niri/umbriel transitions carry full compacted state (verified
  `compositor/diff.py:26-36`), so last non-lifecycle event ≤ t is the state.
- A2 consumers (canon, tank) need only `:app_id`/`:title`/`:workspace`;
  payload keys unchanged → no consumer migration.

### Constraining governance

ADR-001 Amend §1–§2 (G1–G2), A7 frozen time (G3), ADR-018 D3/D5 (G4, G6),
SPEC-002 REQ-013/015/018 (G5, G7, G8), §S6 + DEC-016/018 (G9), POL-001 (G10).

### Documents reconcile will touch (moved from design sec-5, RV-021 F-15)

Not edited by the implementation phases; listed so reconcile finds them
(research Thread 1): ADR-001 Amendment §2 (dated amendment),
`docs/perceptual-design.md` §S6 (the "silence means broken" contract for
`current`, the threshold row, the stale examples, OQ-1),
`docs/memory/design.md` evidence-input rows, `docs/governance.md`'s
panopticon-consumption paragraph, and IMP-013's body. The corpus edit
(`~/satan-corpus/tools/activity_read.md`) is committed in its own repo with
`just commit` there, after the package change is deployed (design sec-4,
"Landing order").

### RV-021 second pass (F-6..F-15) — responder notes, 2026-09-26

- F-7 (DEC divergences) is escalated to the user, not disposed: the design
  departs from DEC-039 (module placement), DEC-038 (parser) and DEC-035
  (reconnect skipped). The design now lists them in sec-2 "Divergences from
  accepted decisions". Once the user rules, the decision text is amended with
  `doctrine knowledge edit decision DEC-0NN …` (facet fields), or the design
  changes back.
- F-10 widened the scope: `satan-memory-canon` gains `local-date` and
  `day-shift`; goad and evidence delegate to them. Selectors were added.
- 2026-09-26: the user ruled on F-7: amend DEC-039, DEC-038 and DEC-035 to
  match the design (done; each is marked as amended in its own text). F-7 is disposed as fixed.
  DEC-036's wording ("is panopticon's contract") is not amended; the user was
  asked and did not rule on it.
- 2026-09-26: the user ruled "amend DEC-036" (RV-021 F-16); choice and rationale amended to match the design. F-16 disposed as fixed.

### Planning (2026-09-26)

- Design omission found at plan time: `~/.emacs.d/lisp/dl-sleipnir-doctor.el:264-266`
  calls `satan-memory-evidence--current-window-status` (design sec-3 claimed
  no remaining caller). User ruling: plan it (PHASE-03 EX-6), keep the design
  locked, and correct sec-3 at reconcile. Its `--sensor-status->doctor` already
  maps unknown statuses (so `disconnected`) to WARN.
- The repo is public: pin-test lines are sanitised copies of live lines (PHASE-02 EX-5).
- verify-vt before implementation reports "keyword present but … not
  modified" for unmodified files even when the keyword is absent. The message
  is misleading; the gate is inert until the file changes.
