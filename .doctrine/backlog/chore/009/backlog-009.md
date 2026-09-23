# CHR-009: Reindent satan-broker--spawn body under its PHASE-05 outer let

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Context

Found in SL-017 PHASE-05 (notes.md, PHASE-05 Findings). PHASE-05 wrapped
`satan-broker--spawn`'s body in a new outer `let` (run-id, stderr-buf, run-ctx,
proc bound outside the one pre-child `condition-case`).

## Detail

The ~230-line body kept its old indentation so the review diff stayed readable.
It is now misindented relative to the new `let`.

## Wanted

A standalone, behaviour-free commit that re-indents `satan-broker--spawn`
(`indent-region`), so the whitespace change is reviewable on its own.
