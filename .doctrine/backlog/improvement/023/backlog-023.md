# IMP-023: Test-side tool-ctx builders hand-build plists instead of satan-run-tool-ctx

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Context

Found in SL-017 PHASE-04 (notes.md, PHASE-04 Findings). SL-017 made
`satan-run.el` the only production builder of a tool-ctx
(`satan-run-tool-ctx`, `satan-run-manual-tool-ctx`, DEC-016).

## Detail

Three test-side builders still hand-build tool-ctx plists:
`satan-observer-test--build-ctx`, `satan-intervention-test--build-ctx`,
`satan-pattern-test--build-ctx`. They can drift from the production ctx
contract, which is how ISS-016 arose.

## Wanted

Build test ctxs through `satan-run-tool-ctx` / `satan-run-manual-tool-ctx`, or
through the shared fixtures SL-017 PHASE-06 added
(`satan-tools-notify-test--with-run` / `--ctx`,
`satan-intervention-test--with-ctx`). Delete the hand-built plists.
