---
name: resonance-payload-handover
description: handover — inline the recalled trace's payload text in the resonance block (Phase 2 cut it)
metadata:
  type: project
  topic: satan
  status: shipped
  updated_at: 2026-05-30
---

# Handover — resonance payload enrichment

> **Shipped 2026-05-30.** The open loop below is closed. Implemented exactly as
> the sketch describes: `-resonate` SELECT widened with the `traces` join + 4th
> payload column (guard `3`→`4`, `:payload` on each row); renderer emits the
> third quoted line truncated to 120c (`satan-resonance--payload-max`),
> self-suppressing on empty. Tab/newline collapse and graceful-degrade kept. A
> drive-by build fix added the missing `(require 'satan-tools-vcs)` to the
> broker test. Retained as the design rationale for the inline-payload decision.

## State: shipped, one enrichment open

**Resonance loop (S2 auto-resonance) is live.** Every tick, after the broker
builds the percept (current window + focus/browser segments + bough + git
handles → canon → `project:` / `app:` / `surface:` handles), it auto-calls
`memory_resonate` with those handles as the cue and injects the top 1–3 prior
trace matches into the prompt capsule. Removes the need for the model to ask
"what happened last time this shape occurred" on every tick.

### The gate (anti-generic-recall) — keep it

Resonance fires iff the cue carries ≥1 **sensor-observed** handle. Degraded
sensors / sparse evidence collapse the percept to handles that match almost any
past moment → useless recall. So:

- **Excluded (too generic):** `mode:*`, `day:*`, `week:*`, `project:*`
  (cwd/git-derived), `file_kind:*`.
- **Admitted (something actually happened):** `app:*`, `surface:*`,
  `surface_transition:*`, `domain_*`, `bough_event:*`, `bough_node:*`,
  `artifact:*`, hint-side `topic:*` / `phase:*` / `focal_app:*`.
- Rationale: `project:emacs.d` is as generic as `day:2026-05-22` when you always
  work in this repo. Stay silent until a sensor saw a transition.

Gate lives in `satan-resonance--admittable-p` (`satan/satan-resonance.el:47`),
excluded set in `--excluded-rule-ids` (`:35`). Do not loosen it as part of this work.

### Current render (per match)

```
# Resonance
- 20260519T171522-a8f3  score 11.2
    matched: project:emacs.d, surface_transition:terminal->browser, domain_kind:docs
```

`trace_id` + `score` + matched handles. **No payload text.**

## The open loop

The design doc's intended render has a **third line** — the trace's own payload:

```
    "after terminal error in emacs.d, user moved to docs and produced no artifact"
```

Phase 2 cut it. Today the model gets a `trace_id` it must `memory_show_trace` to
actually read — an extra round-trip against a tight tick budget (≤4–15 tool
calls). Enrichment = pull payload text **inline** so the model recognises the
recalled context without the round-trip. The data is already in hand at resonate
time: it's one column on the `traces` table the resonate query already joins
against by id.

## Implementation sketch (small, contained — single query, no migration)

The cheapest path keeps it one SQL round-trip by joining `traces` for the payload
in the resonate query itself — no change to the `memory_resonate` SQL function.

1. **Store — widen the resonate SELECT.**
   `satan-memory-store-resonate` (`satan/satan-memory-store.el:269`) runs:
   ```sql
   SELECT trace_id, score, matched_handles
   FROM memory_resonate(:'handles'::text[], %d::smallint, %s::float8, %d::int, %s)
   ```
   Add a 4th column by joining `traces` and collapsing whitespace exactly like
   `memory-store-show` already does (`:371` — `REPLACE(REPLACE(t.payload, E'\n',
   ' '), E'\t', ' ')`, which is what makes the `\t`-split / `\n`-row parsing
   safe):
   ```sql
   SELECT r.trace_id, r.score, r.matched_handles,
          REPLACE(REPLACE(t.payload, E'\n', ' '), E'\t', ' ')
   FROM memory_resonate(:'handles'::text[], %d::smallint, %s::float8, %d::int, %s) r
   JOIN traces t ON t.id = r.trace_id
   ```
   Then bump the parse guard `(= 3 (length parts))` → `4` (`:304`) and add
   `:payload (nth 3 parts)` to the row plist (`:306`). Row contract in the
   docstring (`:278`) gains `:payload`.

2. **Renderer — third line.**
   `satan-resonance-render-block` (`satan/satan-resonance.el:113`) currently
   pushes two lines per match (`- <id>  score N.N` then `    matched: …`). Add a
   third indented line when `:payload` is non-empty:
   ```
       "<payload>"
   ```
   Reuse a truncation cap (mirror `satan-percept--attention-title-max`, ~80–120c)
   so a long payload can't blow the capsule. Self-suppress the line (not the
   block) when payload is nil/empty.

3. **`satan-resonance-derive`** (`:56`) needs no logic change — it passes store
   rows through verbatim into `:matches`; the new `:payload` key rides along.

## Tests (TDD)

- `test/satan-memory-store-test.el` — resonate parse: assert a 4-field tab row
  yields `:payload`; assert a payload containing collapsed whitespace round-trips.
  (Store tests stub the psql query output, so no live DB needed — follow the
  existing resonate test's fake-`--query` pattern.)
- `test/satan-resonance-test.el` — render: a match with `:payload` emits the
  third quoted line; a match with nil/empty payload emits only two lines (no
  empty quotes); long payload truncated.

## Watch-outs

- **Memory errors must not fail the tick.** `derive` maps store `(error . _)` →
  `:status 'memory-unreachable` and the run proceeds (`:90`). Keep that — a psql
  blip already degrades gracefully; the join must not introduce a hard failure.
- **Tab/newline safety.** Only safe because the `REPLACE(REPLACE(...))` collapse
  runs server-side before the tab-join. Don't drop it, or a payload with a tab
  splits into a phantom 5th field and the `(= 4 …)` guard silently drops the row.
- **`traces` is the table, `t.payload` the column, `t.id = r.trace_id` the join
  key** — confirmed against `memory-store-show` (`:367–376`). If `memory_resonate`
  is ever changed to already return payload as a column, prefer that over the join
  (drop the join, select `payload` directly) — but that's a SQL-function migration
  (out of this repo), heavier than the join. The join is the contained option.
- Don't touch the gate or the excluded/admitted handle sets — orthogonal to this.

## Pointers

- `satan/satan-resonance.el` — gate, derive, render (`render-block:113`).
- `satan/satan-memory-store.el` — `-resonate:269`, `-show:317`,
  payload-collapse pattern `:371`.
- `satan/satan-broker.el:726` — where `satan-resonance-derive` is called and
  attached to `:resonance` for the context-fn.
- `docs/satan/perceptual-design.md` §S2 — the auto-resonance design (intended
  three-line render lives here).
