# Notes SL-025: Patch lanes end to end: self-edit and tick jobs through the runner, scoped per mode

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## Harvest
<!-- single-copy: updated in place each harvest; ids only, never restated content -->
fresh-as-of: 2026-10-19 · ready (plan materialised, PHASE-01 next) · b86b698

### Produced
- scope + research round (research/research.md, raw/{governance,code-map}.md; gitignored) — fceaf2c; baseline restamped after CHR-017 row correction — 2ac7137
- design run locked (rev 35): design.md §1-7; DEC-068, DEC-069 — 7a1b653
- RV-031 (GPT gpt-6-sol design review): 7 findings fix-now, integrated; pass concluded; findings answered, not raiser-verified — 5e3606d, 7a1b653
- plan.toml/plan.md, 5 phases; phase sheets materialised — 2ac7137, 0bf2ce0, f8049d9
- minted: IMP-044, RSK-019 (accepted), IDE-011
- ISS-046 body written — 000d889, e6ab173

### Learned
- mem.fact.doctrine.governance-edges-invalidate-confirmation — slice links during a design run void governance-confirmed
- mem.fact.doctrine.review-amend-replaces-response — b86b698
- runner is a store build (CHR-017 done): malebolge code and runner.nix deploy together at one home switch (design §4.6, RV-031 F-1)
- room base carries git/bash/coreutils (oubliette vm/room.nix:7-9) → satan-corpus toolsPackage null

### Open
- mem.fact.satan.patch-job-contract — stale; corrected in PHASE-02 (EX-4)
- SPEC-004 + ADR-017 ledger rows 1, 9 — via a REV at SL-025 reconcile, after SL-023's REV-007
- ISS-028 — harness jail reach-around for self-edit-mech; risk only
- ISS-046 — closes at SL-025 close

## PHASE-01 — runner mode scope (VA-1)

M = `/home/david/dev/malebolge`, base `13500bd`, uncommitted delta (orchestrator commits).
`just check` in M, 2026-10-19: format clean, `eslint . --max-warnings 0` zero warnings,
48 test files / 1276 tests passed (was 1246), lines 98% (2210/2255; gate 85%), exit 0.
`policy.ts` unchanged (`git diff --stat` empty); `grep knownMode src test` empty.
A1 applied: `"*"` as a list member is refused on both `repos` and `allowed_paths`.
