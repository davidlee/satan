# IMP-016: Complete bough retirement: grammar-v2 plus residual-data migration

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

SL-002 removed the bough *integration* — the tool, the evidence fields, the
sensor signal, the canon rules, the observer predicate, the producer input.
What it deliberately did **not** remove is the **vocabulary** and the data
written under it. This is SL-002 design OQ-3.

## Why it was left

Removing the vocabulary in the same slice would have been a breaking change
dressed as a cleanup:

- Dropping `satan-motive--admitted-namespaces`' bough entries flips every
  persisted bough-only motive to **dormant** and rejects future writes
  (RN-2). Silent behaviour change for the keeper, no migration offered.
- Dropping the grammar namespaces makes every historical bough-attributed
  handle **ungrammatical**, so existing traces stop being readable through the
  normal path.

So the resting state is deliberate: legal-but-underivable. No bough handle is
*derived* anywhere any more, but existing ones stay readable, matchable and
copy-forwardable.

## What "complete" means

1. **Grammar v2** — reject `bough_*` at admission. Both halves:
   `satan/satan-memory-grammar.el` and
   `satan/memory/migrations/0002_grammar_v1.sql`'s successor. Version-gated,
   so old traces replay under v1.
2. **Motive vocabulary** — drop the three namespaces from
   `satan-motive--admitted-namespaces`, *with* an operator migration for any
   persisted bough-bearing motive (rewrite or retire; do not silently
   dormant-ise).
3. **Residual store disposition** — every location in SL-002 design §2.F that
   can hold a bough literal:
   - memory DB traces, including `metadata_json`
   - motives, interventions, attributes
   - `satan_patterns` (DB) and the `patterns.eld` source
   - per-run audit bundles under `runs/<run-id>/` — retention/whole-run expiry
     rather than in-place scrub (append-only artifacts)
   - `tick-trace-*.jsonl` — day-bucketed immutable telemetry; age out, do not
     rewrite
4. **Close the five fresh-introduction surfaces** — `motive_replace`,
   `memory-store-mark`, pattern sync, `intervention-create`, and explicit
   `cue.handles` on `memory_resonate` all still *accept* a caller-supplied
   `bough_*` literal today. That is intended and documented while the
   vocabulary is preserved; grammar-v2 admission is what closes it.
5. **Shorten the gate allowlist** — `satan-bough-gate-test--allowlist` in
   `satan/test/satan-bough-removal-gate-test.el` names exactly three files.
   When this lands, the allowlist empties and
   `satan-bough-removal/allowlist-entries-all-exist-and-are-used` goes red to
   tell you so. The preserved-artifact tests in that file retire with it.

## Sequencing note

The pins in `satan-memory-store-test.el`, `satan-motive-test.el`,
`satan-observer-test.el`, `satan-pattern-test.el`, `satan-attribute-test.el`,
`satan-tools-motive-test.el`, `satan-broker-test.el`,
`satan-intervention-test.el` and `satan-tools-atsatan-test.el` — all marked
`PRESERVED-BOUNDARY PIN — SL-002` — assert the behaviour this item **changes**.
They are correct today and must be rewritten, not deleted in passing, when it
lands. They are the checklist.

No trigger yet. Do this when the residual data is genuinely in the way, or when
grammar-v2 is wanted for another reason and this can ride along.
