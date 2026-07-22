
# Extract memory substrate to satan-memoryd daemon

Extraction candidate under [[POL-001]]. **Biggest editor-mismatch in the
codebase.**

Modules in scope: `dl-satan-memory-{canon,store,migrate,grammar,evidence}.el`.
Elisp keeps the tool handlers (`dl-satan-tools-memory.el`) as thin RPC shims;
daemon owns the connection pool + canonicalizer + migration runner.

Fit failure: SQL access (psql subprocess per call), JSON shaping, pure
deterministic transforms. The canonicalizer is the cleanest pure function in
the codebase yet requires ert + Emacs to test; the `json-serialize` arrays
gotcha is paid here repeatedly.

Care: the canonicalizer is deterministic and grammar-versioned. A port must
preserve byte-for-byte equivalence on the test corpus — existing ert becomes a
port-acceptance fixture, not an ongoing test surface.

**Blocked / trigger:** act per POL-001 §Verification (surface growth, recurring
fit-bug, ert CI cost). Likely the same Rust workspace as `satan-attrd`.
