# IDE-011: Runner list-repos control op so lanes discover repo names instead of probing by refusal

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Idea

A read-only `list-repos` (or `modes`) control-socket op returning each mode's
repos and allowed paths, so a lane (tick-agent especially) discovers valid
repo names instead of learning them from a refusal. SL-025 relies on the
refusal message listing the mode's scope; build this if ticks keep probing by
failure. Discovery only: enforcement stays at submit (DEC-069).
