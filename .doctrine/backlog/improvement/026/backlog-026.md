# IMP-026: Split satan-goad read side from the queue write side

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Context

Raised as a standing observation in RV-016's synthesis (not a finding).
`satan-goad.el` holds both the pure read side (queue + day-record readers,
`satan-goad-slice`) and the queue write side (`satan-goad-queue-rewrite`,
which reads Postgres via `satan-intervention-open-asks`). Its header says
"the read side stays dependency-light", which is true of the functions but
not of load order:

```
satan-memory-evidence → satan-goad → satan-intervention
                                   → satan-memory-migrate / satan-attribute / satan-memory-store
```

So the percept builder (perceive leg, ADR-001) loads the whole
intervention/DB graph just to read two JSON files.

## Proposal

Move the write side (`satan-goad-queue-rewrite` and anything only it uses)
into its own module (e.g. `satan-goad-queue.el`) required by the tool and
the observer; `satan-goad.el` then requires only canon/jsonl/custom.
The design (SL-016 sec-2/3) names one module for both, so this is a
post-close refactor, not an SL-016 fix. Relevant to POL-001 if the read
side is ever extracted.
