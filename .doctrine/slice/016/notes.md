# Notes SL-016: goad as SATAN's elicitation surface

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## Harvest

**fresh-as-of:** stage `design`, run `dr-01a0c179` at `reviewing` (revision 40),
head `041ba2f`, 2026-09-23. design.md revised twice today and materialised.
Nothing implemented.

### Produced

- **RV-007 round 1 (Claude raiser, 2026-09-23)** — F-1..F-19: 16 verified, F-6/
  F-9/F-10 contested; F-20..F-27 raised (F-20 blocker: goad-minted handles can
  never correlate the ask that creates them). All 11 answered `fixed`, user
  accepted every disposition; design revision 39 (`041ba2f`). Amendments
  appended to `DEC-004`, `DEC-011`, `DEC-012`. Memory
  [[mem.fact.satan.bough-deprecated]].

- **Drift revision, 2026-09-23** (run revision 37, materialised 38), against
  HEAD `1fbdc67` — 55 commits after the RV-007 rebuild. SL-017's record/project
  split (ask records → projects → rewrites queue; `undelivered` verdict on
  failure, writer moved to `satan-intervention.el`); a kind-`"ask"` branch in
  `classify-negative` so non-engagement has a writer (the rebuild named none —
  it fell through to the focus path); quiet window via `satan-tick-quiet-p`
  window arg; SL-018 `defer` gates producer enablement. Amendments appended to
  `DEC-005`, `DEC-006`, `DEC-013`. goad advanced 28 commits (slice 010, exit
  codes) — no ingress or backend-contract change. All ten sections now
  outstanding review; RV-007 awaits its raiser.

- **design.md** — ten sections, 816 lines, materialised from the run's runtime
  sections. Committed.
- **Eleven durable records.** `DEC-004` PERCEIVE route (forced, not a
  tradeoff) · `DEC-005` no new stateful layer · `DEC-006` autonomous producer in
  v1 via tick-pulse · `DEC-007` correlate by construction · `DEC-008` POL-001 No
  branch, no trigger · `DEC-009` day record becomes JSON · `DEC-010` one queue
  file · `DEC-011` answer lands in three roles · `DEC-012` both observer legs ·
  `EVD-002` refusal reaches SATAN through the ledgered tier · `ASM-001`
  backend.py can echo `intervention_id` (unvalidated, with a plan).
- **Selectors corrected** and doctor-clean: dropped `test/**` (never existed)
  and `satan/satan-sensor-*.el` (targets the probe route `DEC-004` did not
  take); added `satan-memory-{canon,evidence}.el`,
  `satan-observer-classify.el`, `satan-tick.el` as design targets.
- **Doctrine pin moved 0.25.3 → 0.44.3** (`flake.lock`). The old pin had no
  `doctrine design` run machine, which is why the research round was
  hand-stamped.
- **Research baseline re-stamped** by the CLI. The hand-stamped one had
  `slice = 16` as an integer and was unparseable to the 0.44.3 verb.

### Learned (durable sinks)

- [[mem.fact.satan.intervention-classification-gate]] — **corrected this
  round.** Three additions: the correlator reads `bundle.json` and never the
  `cue_handles` column, so `:cue-handles` is not the hook it looks like;
  `satan-motive--admitted-namespaces` is a closed allowlist so a new handle
  namespace cannot be cued on; and `:ignored` today means the keeper was
  *absent*, not that they ignored anything.
- **Five research claims corrected at point of use**, each now carried by a
  record rather than by this file: X4's stderr-discard premise (`EVD-002` —
  `call-process` with DESTINATION `t` mixes stderr in); X3's three-way cost
  framing (`DEC-004` — only the evidence route emits handles); delta 9's
  tick-pulse capabilities (`DEC-006` — it cited `self-edit-mech`'s spec);
  delta 8's fixed-TOML premise (`DEC-009` — the format is `backend.py`'s own);
  delta 7's assumption that `save()` is atomic (it uses `write_text`).
- Not yet sunk, still only here — harvest at close if they survive contact
  with implementation:
  - `satan-tick-quiet-hours` is `nil` (`satan/satan-tick.el:24`, *"was '(22 . 7);
    disabled while iterating"*) and the tick fires ~30min around the clock. Safe
    only while every tick surface is ambient.
  - `satan/satan-tools-*.el` does **not** match `satan-tools.el` — the glob
    requires the hyphen. Bit the selector list.

### Open

- **The design is unlocked.** Review policy `adversarial-only`; the lock gate
  needs `section-reviewed` (adversarial lane), `review-disposed` and
  `design-accepted`. `design-accepted` is a user act regardless of policy.
- **RV-007 round 2 done** (Claude raiser, at `041ba2f`): all 11 answers
  verified. **Five new findings open, awaiting responder:** F-28 major (goad
  handles still count in motive ranking — can outrank the subject motive, F-5
  returns), F-29 major (which day file the unbounded goad read uses — midnight
  crossing; goad quiet-hours default unstated), F-30 minor (`presented_at` first
  vs latest render), F-31 minor (answer after window has no precedence row),
  F-32 nit (stale text at design.md ~:736, ~:469, ~:562). Adjudicate via
  `/feedback`; details on the ledger.
- **Lock disposition plan (not yet user-agreed):** the run's pass ledger RV-006
  is empty and STALE; the adversarial history is RV-007. Proposed:
  `review-disposed` as `waived`, reason citing RV-007 — needs the user's
  assent, then `design-accepted` + adversarial attestations for all 10 sections.
- **User may overrule one call:** presented-then-bulk-`Enough` classifies
  `:ignored :medium` `dismissed` (design sec-5); alternative `:unknown :low`.
- **Unverified, plan must check:** whether goad re-evaluates when an `engaged`
  exchange ends (design sec-4).
- **Six risks carried, not resolved** — see design §10. `ASM-001` unvalidated;
  the decorrelation race (`motive_replace` between emit and maturity, detectable
  via `related_motive_id`, home is [[IMP-002]]); suppression-alert throttle
  unspecified; quiet hours off; two-repo landing; `ISS-001` truncation cap.
  (Superseded in part: design sec-9 now carries the current risk table.)
- **Revision candidates for `/reconcile` at close** (none caused by this slice):
  POL-001's seat rationale does not contemplate a non-editor human surface;
  `.doctrine/state/boot.md` still says the protocol tech spec and authority
  ledger are *"not written yet"* when both exist; RFC-017 D1 rows G1/G2 read
  *"not written"* when both landed.
- **Scope document deliberately uncorrected.** The design supersedes it and says
  where (§9, §10); per-slice artefacts are `/reconcile`'s to write at close.

### Tooling defects hit (doctrine 0.44.3, not SATAN)

- The design runbook's `explore.research` check shells out to a top-level
  `doctrine verify`, which does not exist — the step cannot be *attested*
  however completely it is performed. Discharged `skipped` with the substance
  recorded.
- `review.passes` carries the literal reason `probe`: a placeholder submitted
  while probing whether the step was gated. It discharged rather than refusing,
  and re-discharge is refused because the runbook is complete. The correction
  is recorded in the review-policy acceptance basis.
- `adversarial-then-human` and `human-then-adversarial` are 22 bytes against a
  16-byte payload-label bound, so neither two-lane policy is submittable. Only
  `human-only` and `adversarial-only` are reachable.
- `design materialise` orders sections **lexically**, so `sec-10` renders
  second. Section bodies are assigned to lexical slots as a workaround, so the
  ids are slots rather than reading positions. Sections cannot be pruned
  (`lifecycle` is inert on a `sec-` subject), so padded ids would have left ten
  orphans.
