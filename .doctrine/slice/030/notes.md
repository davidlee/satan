# Notes SL-030: malebolge daemon: many conversations — thread the conversation through the interactive daemon

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## Harvest
<!-- single-copy: updated in place each harvest; ids only, never restated content -->
fresh-as-of: 2026-10-20 · design (research done, no design run) · d30cd83

### Produced
- scope authored (173f682); research round done: `research/research.md`, gitignored working evidence (baseline stamped)
- malebolge RFC-002 — topics/conversations policy deliberation (malebolge c082433)
- minted: ISS-053 — SPEC-002 transport row missing for the interactive daemon socket

### Learned
- mem.fact.pi-durable.agent-defaults-and-ids — no default model; root({agent}) ignored on an existing root; ConversationId has no parser

### Open
- D-A..D-D (slice-030.md objectives 6–9) — design decisions for `/design`; options in research.md X-1..X-3
- candidate QUE — who may attach to which conversation (precedent QUE-001); decide at design whether to file
- governing refs to cite at design: DEC-074, DEC-087, DEC-078, DEC-079, CON-005
