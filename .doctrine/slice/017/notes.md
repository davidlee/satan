# Notes SL-017: SATAN reports on SATAN: one emit seam, record before emit, persistent failures stay loud

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## Harvest
<!-- single-copy: updated in place each harvest; ids only, never restated content -->
fresh-as-of: 2026-09-23 · proposed (scoped, pre-research) · dcb4d59 + uncommitted scoping

### Produced
- SL-017 (this slice)
- ISS-017 — split from ISS-012 (loudness half)
- ISS-016 — root cause corrected (two tool-ctx builders)
- CHR-008 — stale `.doctrine/governance.md:15` gate claim

### Learned
- mem.fact.satan.op-prompts-on-session-not-read (new)
- mem.fact.satan.op-read-blocks-emacs-server (rewritten: popup now surfaced)
- mem.fact.satan.op-cache-has-no-invalidation

### Open
- slice-017.md OQ-1..OQ-4 (pre-spawn audit handle; suppress-vs-degraded emit; escalation cadence/cap + quiet hours; escalation state home)
- slice-017.md A1, A2 (assumptions)
- Contract owed to SL-018: run-outcome streak over non-`failed` outcomes (`credential_deferred`); `auth` class transport
