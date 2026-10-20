# IMP-049: pi-mcp: an operator-facing policy schema and worked example outside slice notes

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

From the review of SL-029's reconcile arc (point 6). The policy schema refuses
everything over one missing or malformed field: all four `maxima` units are
required and positive, along with `mode`, `roots`, `profiles`, `forms`,
`child_binds` and `enabled`. Yet the only worked example lives in
`.doctrine/slice/029/notes.md` (§ PHASE-09 evidence). An operator on a new host
should not need a slice history to publish a policy.

Shape: a short operator doc beside the server (e.g. `docs/pi-mcp.md`, indexed
from `docs/INDEX.md`). It should cover every field with its type and refusal, a
minimal valid per-call policy, the publish rules (read-only, outside every root,
atomic write-then-rename), and the `child_binds` trap in IMP-048. Optionally,
the example policy can be checked by a test, so the doc cannot drift from
`validatePolicy`.
