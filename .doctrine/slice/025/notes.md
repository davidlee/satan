# Notes SL-025: Patch lanes end to end: self-edit and tick jobs through the runner, scoped per mode

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## Harvest
<!-- single-copy: updated in place each harvest; ids only, never restated content -->
fresh-as-of: 2026-10-19 · design/drafting (run rev 18) · 3017d99

### Produced
- scope + research round (research/research.md, raw/{governance,code-map}.md; gitignored) — fceaf2c
- design run inquiring complete: 8 inquiries resolved; DEC-068, DEC-069 (amended on an informal GPT gpt-6-sol second opinion, adjudicated with the user) — 3017d99
- minted: IMP-044 — one-source runner repo entries; RSK-019 — any MCP client submits unbounded interactive (accepted); IDE-011 — runner list-repos op
- ISS-046 body written (three layers, lanes, rulings) — 000d889, e6ab173

### Learned
- mem.fact.doctrine.governance-edges-invalidate-confirmation — slice links during a design run void governance-confirmed
- room base already carries git/bash/coreutils (oubliette vm/room.nix:7-9) → satan-corpus target needs no tool set (research Thread 2 fact 7)

### Open
- inq-4/5/6/8 answers are run-held configuration detail (`doctrine design show 25`); drafting must carry them into design.md
- mem.fact.satan.patch-job-contract — stale (absolute repo path, deleted worktree module); correct in the slice (inq-7)
- SPEC-004 + ADR-017 ledger rows 1, 9 — via a REV at SL-025 reconcile, after SL-023's REV-007
- ISS-028 — harness jail reach-around for self-edit-mech; risk only
- runner is a store build (CHR-017 done): malebolge code and runner.nix deploy together at one home switch (design §4.6; research Thread 1 row is stale)
