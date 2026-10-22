# IDE-016: quotient: multi-root pi_agent calls (form-2)

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Raised in SL-031 design (2026-10-22). A `pi_agent` call has exactly one root:
its `cwd`, which the form binds read-only or writable (DEC-089). The policy's
`roots` is an allowlist, so a call can target any listed repo, but one delegate
cannot write two repos in one run (e.g. a satan + malebolge change).

Multi-root would change: the request (a list of roots), the form contract
(extra roots as arguments: `form-2`; form-1 conveys the root by cwd so this is
additive), validation step 8 over every root, and session binding (DEC-099,
one root + capability). Not needed for v1; revisit when a real cross-repo
delegation shows up.
