# Notes SL-002: Remove bough integration

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## 2026-07-18 — Design inquisition

- Completed source-backed design review as RV-001: 8 terminal findings
  (3 blocker, 5 major); verdict is unsound to lock pending design
  reconciliation. The RV synthesis owns the detailed evidence and sentencing.
- Review cache/selector conformance remains unavailable because SL-002 declares
  no selectors; this is recorded as RV-001 F-8.
- Review-ledger and slice-note changes are uncommitted. No product source or
  accused design file was modified, and no code verification gate was run
  because this was a review-only task.

## 2026-07-22 — Plan authored

- Six phases (`plan.toml`); sequencing rationale in `plan.md`. Two orderings
  are forced, not stylistic: evidence (PHASE-02) precedes the tool-file
  deletion (PHASE-03) because `satan-memory-evidence.el:41` requires
  `satan-tools-bough`; and the tool surface is atomic because
  `satan-mode-check-tool-references` only passes with the tool unregistered
  *and* absent from every mode list.
- Boundary pins go first (PHASE-01), green-before / green-after. The risk here
  is not that removal breaks — it is that removal quietly takes preserved
  substrate with it and nothing notices, because bough data is dormant.

### Resurrection path

- **Pre-removal SHA: `74f82e057c823da344eb7f95e6a7ef5e5c337fc8`** (`74f82e0`,
  "governance: accept ADR-017 + ADR-018, amend POL-001 seat lists"). This is
  the last commit with the bough integration fully intact.
- Plus the SL-001 `design.md` §2/§10 ledger, retained as the authoritative seam
  map (slice §Context).

### Census at plan time (2026-07-22)

Live bough token counts, for divergence detection at audit — 67 files. Largest:
`satan-tools-bough.el` 108, `docs/memory/design.md` 95,
`satan-tools-bough-test.el` 93, `satan-memory-evidence.el` 70,
`satan-memory-evidence-test.el` 65. The design's touch-set covers all of them;
two fixture files (`test/canon-fixtures/rich_window.json` 8,
`minimal_firefox.json` 1) are not named as selectors but fall under §2.D
classification — disposition them at PHASE-05.
