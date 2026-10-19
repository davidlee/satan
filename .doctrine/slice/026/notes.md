# Notes SL-026: malebolge coding layer: project context, cwd, ripgrep grep

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## Harvest
<!-- single-copy: updated in place each harvest; ids only, never restated content -->
fresh-as-of: 2026-10-19 · design (entry, no run) · 8256d4a

### Produced
- scope + research round done; scope reshaped on research (commits d911161, 8256d4a); research artefact `research/research.md` (gitignored)
- RFC-019 D7 table corrected: pi-durable bash already has `timeout`
- minted: CHR-020 — daemon launch dir ≠ ~/notes (related, not in scope)

### Learned
- mem.pattern.doctrine.cross-corpus-id-collision — qualify foreign ids (oubliette DEC-052 ≠ satan DEC-052)
- mem.pattern.satan.research-jail-snapshot — research jail sees no sibling repos; launch over a snapshot

### Open
- ASM-006 — rg on the in-room pi-env daemon's PATH; falsify live
- design-owned (no records yet): job context storage; walk stop + caps; section order; CHR-020 ordering; the instruction-not-policy DEC; SPEC-004 REV
