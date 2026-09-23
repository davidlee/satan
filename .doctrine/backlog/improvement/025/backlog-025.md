# IMP-025: SATAN perceives goad checklist history (goad/data/*)

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Gap

SL-016 as designed perceives only SATAN's **own asks** that are still
outstanding: the `goad.outstanding` canon rule and the evidence `:goad` slice
read `queue.json` entries and each entry's record from its emit-date day file.
Once an ask is classified or expires it leaves the queue and SATAN's view.
The keeper's **checklist answers** (the `items` map — meds, walk, reviews, …)
are never read, and no past day file is.

SL-016's scope document (Scope item 1, PERCEIVE) promised more — per-item
`value` and `deferred_at` from `~/satan/goad/data/*`. The design narrowed it;
the scope document is to be reconciled at SL-016 close.

## Options — decision deferred (may take one, both, or neither)

1. **`goad_read` tool — on-demand history.** Reads past day files when a run
   asks for them. No per-run token cost. Precedent: `activity_read`. Design
   SL-016 sec-2 names it as an optional supplement.
2. **Compact percept contribution — e.g. today's checklist state.** Ambient,
   so motives can cue on it, but costs tokens on every run, and the evidence
   truncation cap is unenforced (ISS-001).

## Constraints

- Day files are corpus (`~/satan/goad/data/`, SATAN-owned, git-tracked), so no
  ownership question; read-only regardless.
- Record format becomes JSON in SL-016 PHASE-01 (DEC-009) — build after that
  lands; `items` map shape is `backend.py`'s own, see `~/satan/goad/README.md`.
- Option 2 lands in the perceive phase: must stay pure (ADR-001), and any
  handles must sit in `satan-motive--admitted-namespaces`.
- Distinct from SL-016's out-of-scope "reporting or analytics over data/":
  this is perception, not reporting.
