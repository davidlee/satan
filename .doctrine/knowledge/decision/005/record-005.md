## Why this is not a waiver

ADR-018 D5 and POL-001's anti-candidate clause look like they conflict for SL-016, and they only conflict if the slice needs new durable state. It does not.

A pending question is an intervention of kind `"ask"`. `satan-intervention-create` (`satan/satan-intervention.el:354-395`) already persists everything that distinguishes one: `intervention_id`, `run_id`, `ts`, `mode`, `kind`, `message`, `related_motive_id`, `cue_handles`, `percept_handles`, `expected_outcome`, `outcome_window_minutes`, `severity`. There is no field of a goad question that this row cannot hold.

So the design's job is not to invent a store. It is to **project** the open-ask rows into the shape `backend.py` can merge into `pending()`, and to read the answer back out of the file goad already writes.

## Three tiers, each in its right place

| tier | holds | where | on loss |
|---|---|---|---|
| record | the ask, as an intervention row | `satan_memory` (Postgres) | the question is gone — this is the durable tier |
| projection | the open asks, as `backend.py` input | `satan-state-path` | regenerate from the rows |
| answer | the keeper's reply, per item | goad's own `data/*.toml` | goad's concern, corpus-tracked already |

The middle row is the one research delta 10 could not place. It could not be placed because it was being treated as a record. As a projection it belongs in the state root by definition, and the root's documented contract — *"discardable: nothing below it is authored or versioned"* — becomes accurate rather than an uncomfortable fit.

## The obligation this creates

`backend.py` must echo `intervention_id` through to the day file, or the answer cannot be attributed and verification-intent item 2 fails. That is a corpus-side change, already in the slice's affected surface, and it is the single point on which the whole no-new-layer argument rests. It should be tested, not assumed.

Regenerability likewise: *the projection can be rebuilt from the intervention rows* is the claim that makes the state root correct, so it earns a test rather than a sentence.

## Amendment — the backend change set is the load-bearing part (RV-007)

The no-new-layer argument stands and ADR-018 D5 is still satisfied rather than
waived. What was understated is the cost on the other side of the boundary.

"Merge the queue into `pending()` and echo `intervention_id`" turns out to be
four changes to `backend.py`, none optional, against a file with no tests, no
fixtures and no check recipe:

| # | change | finding |
|---|---|---|
| 1 | write `presented_at` when an item is actually rendered — the only real delivery proof, since goad replies `accepted` before calling the backend | F-1 |
| 2 | give SATAN asks **priority** in `pending()` — `main()` renders only `waiting[0]` and `pending()` returns `ITEMS` order behind fourteen entries | F-18 |
| 3 | record **deferral provenance** — `answer()` writes the same `deferred_at` for `later:` and `enough:`, which are opposite signals here | F-19 |
| 4 | serialize **queued items** — `save()` iterates `ITEMS` alone, so a SATAN answer would render, mutate the in-memory map and vanish on write | F-7 |

Together these carry [[DEC-013]]'s reframe. The projection-and-record split is
unchanged; the work to make the record say what the slice needs is real and
belongs in the plan as its own phase, fixtures first.