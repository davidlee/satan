
# SATAN true page-recall: write captures into memory store as traces (gated by IMPR-007)

**Origin:** DE-005 §7 / DR-005 DEC-2 named follow-up.

DE-005 delivered percept-*shaping* only: the `panopticon.content` rule emits
`content_domain:*` handles that bias *which existing* memory traces resonate, and
page bodies are reached on demand via the `content_read` tool. It deliberately
does **not** write captures into the memory store (DEC-2) — that would grow the
IMPR-007 extraction candidate (the memory substrate, "biggest editor-mismatch")
in the wrong direction under POL-001.

True page-recall — "surface a captured page by topic during reasoning" via
`memory_resonate` — needs captures written into the store as traces.

**Blocked by:** [[IMPR-007]] (memory-substrate carve). Do not implement until that
carve lands; otherwise this entrenches the substrate that IMPR-007 wants to
extract.

**Pointers:** `satan/dl-satan-memory-canon.el` (`panopticon.content` defrule),
`satan/dl-satan-tools-content.el` (`get` for bodies), `docs/satan/perceptual-design.md` §S2.

