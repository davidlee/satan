
# SATAN arrival gate: attributes as stochastic scheduling surface

Depends on **[[DE-010]]** (perception/agent split): this is the *gate*
component — the trigger that decides whether/when/in-what-mode the consumer
arrives. Captured 2026-06-08 from design discussion.

## Idea

Promote the attribute layer from a **within-run bias surface** (the model reads
`Attributes:` in the capsule) to a **between-run scheduling surface**: attributes
decide arrival. High Curiosity → likely info-gathering run; high Metamorphosis →
likely introspection/self-edit; Brooding → ruminate. The gate reads attributes,
rolls a (biased) die, maybe fires; a completed run of a kind satiates its
matching attribute. Integrate-and-fire / leaky bucket → bursty, irregular,
natural-rhythm arrival. Cashes the existing metaphor: *"global attributes are
the animal's metabolism"* (`patterns_attributes.design_note`).

## Mostly not new — reuses existing machinery

- **Satiation already exists.** Source-event tables already decrement the
  matching attribute on the matching action (ruminate writes → Brooding −0.025
  ea; `worked` → Hunger −0.05; `trace_marked` → Curiosity −0.025). Naming it
  as the scheduler's negative feedback, not adding it.
- **Homeostatic floor exists.** T-attr-2 daily decay (−0.01/day) is what stops
  ratchet-to-ceiling — a stochastic gate is unusable on a saturating substrate.
- **Continuous integration exists.** Sensors already charge attributes every
  tick (`segment_backlog` → Curiosity +0.05, `typing_active` → Hunger +0.05).
  So the gate likely **doesn't nudge** — integrate happens upstream; gate =
  read + roll + (on-fire) satiate. Don't double-count.

## Sharp edges (ranked)

1. **The roll must be a logged, seeded event** or it breaks the layer's
   replay-determinism foundation (`Math.random`/`Date.now` are banned in that
   world). Seed RNG from recorded state; emit an `arrival.rolled` event
   (threshold, roll, fired?). #1 gotcha.
2. **Gate is a new writer → new dispatcher source** (`source=arrival`/`gate`),
   own reason enum + delta table + caps + replay. Invariant 7 (only the
   dispatcher writes) holds. Slots into the reserved-source pattern cleanly.
3. **Intervention ≠ slow global attribute.** Global attrs are deliberately
   *ambient/slow* (design-contract §3.1). Intervention urgency is a fast,
   cue-bound spike. So: slow global attrs → *discretionary* arrival; fast
   **episode-scoped transient** → intervention reflex. The contract reserves
   `scope = episode | motive:<id>` but v1 only writes `global` — this motivates
   finally implementing episode-scoped attributes. Same vocabulary, two
   timescales.
4. **Placement: daemon owns the gate, broker effects it.** Like decay
   (daemon-side per `extraction-policy`), the gate reads attrs + rolls in
   `satan-attrd` and signals the broker to spawn via the existing pg_notify/
   inbox path. May retire the systemd heavy-run timer entirely; waybar widget =
   manual arrival injection.
5. **Governance crux.** `architecture.md`: arrival is "explicit, scheduled,
   inspectable, boring." A stochastic metabolic gate shifts arrival
   deterministic-schedule → self-paced-stochastic. Needs: daily token ceiling
   as hard cap (`dl-satan-budget`), fire-probability modulated by remaining
   budget, and a written self-manipulation analysis (model already nudges its
   own attrs via tools, §6H.7 — gating arrival raises the stakes; contain via
   probability-not-trigger + budget cap + satiation negative feedback). **Wants
   an ADR or `governance.md` amendment**, not a quiet delta.

## Net

High-fit; reuses event-log/caps/replay/decay wholesale. Genuinely new build:
new `arrival` source + seeded-logged gate in the daemon + episode-scoped
attributes for the reflex. **Arrival-doctrine shift is the thing to settle
before any code.** Promote to a delta (or fold into [[DE-010]]'s successor)
once D1/D2 in DE-010 are settled and the doctrine question has an ADR.

