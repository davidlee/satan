# Notes SL-023: Patch runner for the oubliette assistant room

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## Pre-design research (2026-10-18)

Research artefact (gitignored, on disk): `.doctrine/slice/023/research/research.md`
+ `raw/` — five threads (governance, elisp runner, Go satan-patcher, oubliette
door, malebolge/pi-durable/pi-env) and an option-D spike. Leading candidate:
**option D** — a daemon runner hosting a pi-durable harness on the host, tools
in the room via pi-env; both existing runners retired (logic ported, not code).
Oubliette SL-005 consumes the same file (its X6/X7 cross-check is in it).

## Harvest
<!-- single-copy: updated in place each harvest; ids only, never restated content -->
fresh-as-of: 2026-10-18 · design (no run started) · 1c3c4de

### Produced
- SL-023 scoped, linked (IDE-007/008, RFC-018, ISS-030/038/039/041, IMP-006; governed_by POL-001, ADR-017, ADR-018) — 42b2dea
- IDE-007 gateway-key wording corrected (DEC-046/DEC-050) — 42b2dea
- research round + option-D spike against capsule slot f — artefact on disk, not committed
- slot f left running; its volume holds `~/sl023-spike` and the pi-env daemon in `~/.pi`

### Learned
- EVD-005 — pi-env drives a slot through its relay; dropped connection fails one tool call, run recovers
- mem.pattern.satan.pi-env-oubliette-gateway — recipe: pi-env via relay ProxyCommand, pi-ai via the gateway

### Open
- QUE-005 — runner glue: TypeScript beside pi-durable, or Rust core over RPC
- QUE-006 — runner behaviour while the room is down (DEC-031 stops are routine)
- ASM-005 — oubliette SL-005 pins the door as Plan F §5 sketches
