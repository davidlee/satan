---
name: attributes-wiring-status
description: Operational status of each attribute — which signal sources are wired, which are dormant, and what structural constraints hold
metadata:
  type: reference
  topic: attributes/wiring
  status: living
  parent: design-contract.md
  updated_at: 2026-05-25
---

# Attribute wiring status

> **Purpose.** The brief describes what *should* drive each attribute. The design
> contract narrows v1 to two implemented sources (`outcome`, `hippocampus`) with
> five reserved (`percept`, `resonance`, `sensor`, `tool_error`, `manual`). This
> document maps the operational consequence: which attributes actually move today,
> which are structurally locked at zero, and what would change that.

> **Companion to** `design-contract.md` (normative spec) and `attributes.brief.md`
> (conceptual intent). This doc is descriptive — it reports wiring state, not
> policy. Update it when new sources land or delta tables change.

---

## Signal source implementation status

| Source        | Status        | Ticket    | Notes |
|---            |---            |---        |---    |
| `outcome`     | implemented   | T-attr-1c | 5 classifications × 3 confidence levels |
| `hippocampus` | implemented   | T-attr-1e-hc | 6 reasons (incl. `trace_marked`), binary (no confidence weighting) |
| `percept`     | reserved      | T-attr-1e | novel/weak/contradictory percept signals |
| `resonance`   | reserved      | T-attr-1e | memory_resonate hit signals |
| `sensor`      | implemented   | T-attr-1e-sensor | segment_backlog, typing_active, typing_idle |
| `tool_error`  | reserved      | T-attr-1e | tool execution failure signals |
| `manual`      | reserved      | post T-attr-1 | interactive command / notes directive |

---

## Per-attribute wiring

### Curiosity — active

**Current value: moves on sensor and hippocampus events**

Outcome deltas: all zero across all 5 classifications.

Sensor deltas:
- `segment_backlog` → +0.05 (uninspected panopticon segments raise curiosity)

Hippocampus deltas:
- `trace_marked` → −0.025 (trace persistence *partially* satisfies curiosity; amended 2026-05-29 from −0.05 to break daily cancellation against sensor `segment_backlog` — see design-contract §6H footnote 6)
- `trace_marked` also reduces Brooding (−0.025) as a cross-attribute side-effect (symmetric magnitude)

The brief lists five triggers (novel percept, weak percept, contradictory
resonance, active motive lacks evidence, new project/context). Sensor now
supplies one of these — uninspected segments signal knowledge gaps. Percept
and resonance sources remain reserved for the remaining triggers.

---

### Hunger — active

**Current value: moves on sensor and outcome events**

Outcome deltas:
- `worked` → −0.05

Sensor deltas:
- `typing_active` → +0.05 (WPM activity detection — user is producing)
- `typing_idle` → +0.025 (WPM idle detection — user present but not producing)

Hippocampus deltas: all zero.

Hunger now rises via sensor signals: active typing raises it faster than idle
presence. Falls on `worked` outcomes (artifact produced in response to
intervention). The brief's remaining triggers (stale patch job, long browsing)
still await `percept` sources.

---

### Suspicion — near-dormant

**Current value: 0.00 (wired but conservatively; signals near-cancel)**

Outcome deltas:
- `contradicted` → −0.05 (global ambience, not per-pattern; §6 footnote 2)
- All others → 0

Hippocampus deltas:
- `searched` (grep with 0 matches) → +0.025

Two signals push in opposite directions. A `contradicted` outcome *lowers*
global suspicion (−0.05); an empty hippocampus search *raises* it (+0.025).
In practice, these are rare events with small magnitudes — Suspicion stays
near zero.

The brief's triggers (matched handles, repeated percept shape, same
transition pattern recurs) all require `resonance` + `percept` sources.
Global Suspicion is intentionally ambient (§3.1) — per-pattern suspicion
lives in pattern records, not the attribute layer.

**To activate meaningfully:** implement `resonance` source. Handle-match
resonance is the canonical suspicion signal.

---

### Doubt — active

**Current value: 0.50**

Outcome deltas:
- `worked` → −0.05
- `ignored` → +0.05
- `contradicted` → +0.15
- `harmful` → +0.30

Hippocampus deltas: all zero (inward-facing tools don't affect certainty).

Doubt responds to every non-neutral outcome. Currently the most responsive
attribute — it captures "how much should SATAN trust its own interventions."
The brief's additional triggers (sensor stale, percept weak, countertrace
present) await T-attr-1e sources.

---

### Friction (public: Cruelty) — structurally locked at 0

**Current value: 0.00 (asymmetric wiring + cap = permanently clamped)**

Outcome deltas (all negative or zero):
- `ignored` → −0.05
- `contradicted` → −0.15
- `harmful` → −0.30
- `worked`, `neutral` → 0

Hippocampus deltas: all zero.

**No implemented source produces a positive friction delta.** The design
contract §7.1 notes this explicitly: the friction cap is included for
forward-compat but has no effect in T-attr-1c because no v1 outcome raises
friction.

Even if a positive source were added, the **friction cap** constrains:

```
friction ≤ max(0, 1 − doubt − shame)
```

With current doubt=0.50 + shame=0.50, ceiling = max(0, 0.0) = **0**. Friction
is doubly locked: no upward pressure, and even if there were, the cap would
clamp it.

The brief's "raises when" triggers (Hunger high, Suspicion high, soft nudges
failed, repeated unresolved loop) require cross-attribute cascade rules
and/or `percept` signals — both deferred beyond T-attr-1.

**To activate:** requires (1) a positive-delta source (T-attr-1e: percept or
resonance), AND (2) doubt + shame < 1.0 so the cap has headroom. The second
condition self-corrects as the system accumulates `worked` outcomes.

---

### Shame — active

**Current value: 0.50**

Outcome deltas:
- `worked` → −0.025 (deliberately halved from small; §6 footnote 1)
- `ignored` → +0.05
- `contradicted` → +0.15
- `harmful` → +0.30

Hippocampus deltas:
- `overwritten` → −0.025 (correcting wrong knowledge = acknowledging error)
- `deleted` → −0.025 (same rationale)

Shame has the widest signal coverage of any attribute. It rises on negative
outcomes and falls slowly on success + memory correction. The asymmetry
(+0.30 on harmful vs −0.025 on worked) is intentional: "a single success
should not easily wash it away."

No decay implemented (§8 defers to T-attr-2). Shame accumulates
monotonically until `worked` or hippocampus correction counters it.

---

### Brooding — active

**Current value: 0.05**

Outcome deltas:
- `worked` → +0.05 (fresh outcome needs assimilation)
- `ignored` → +0.05

Hippocampus deltas:
- `written` → −0.025
- `overwritten` → −0.025
- `deleted` → −0.025
- `renamed` → −0.025

Brooding rises when outcomes need digestion and falls when the organism acts
on what it's ruminating about. A ruminate run with 5–10 hippocampus writes
produces −0.125 to −0.25 cumulative reduction.

---

### Metamorphosis — active

**Current value: 0.27**

Outcome deltas:
- `contradicted` → +0.05
- `harmful` → +0.15

Hippocampus deltas: all zero.

Metamorphosis is self-edit pressure. It rises only on outcomes that reveal
SATAN was wrong in ways that demand structural change. No decay (§8). Falls
only via future mechanisms (successful self-edit reducing the failure mode).

---

## Summary matrix

```
                    outcome    hippocampus   percept   resonance   sensor   tool_error
Curiosity           —          active        reserved  reserved    active   reserved
Hunger              (−only)    —             reserved  —           active   —
Suspicion           (−only)    (+0.025)      reserved  reserved    —        —
Doubt               active     —             reserved  —           reserved —
Friction            (−only)    —             reserved  reserved    —        —
Shame               active     active        —         —           —        —
Brooding            active     active        —         —           —        —
Metamorphosis       active     —             —         —           —        —
```

Legend: `active` = has nonzero deltas in both directions or meaningful
positive deltas. `(−only)` = has only negative or zero deltas — cannot rise
from this source. `(+N)` = has one small positive delta. `—` = all deltas
zero. `reserved` = brief describes relevant triggers for this source.

---

## Structural constraints

### Friction cap (design-contract §7.1)

```
friction ≤ max(0, 1 − doubt − shame)
```

When doubt + shame ≥ 1.0, friction ceiling = 0. The cap only restrains
positive deltas — negative deltas always pass. Currently doubt(0.50) +
shame(0.50) = 1.0, so friction has zero headroom even if positive sources
were wired.

### No decay (design-contract §8)

All attributes move only on explicit source events. No automatic time-based
decay. Deferred to T-attr-2 pending production observation. Consequence:
Shame and Doubt accumulate toward their caps and stay there until countered
by `worked` outcomes.

### Zero seed (design-contract capsule-contract §3.4)

All 8 attributes seed at 0.0. Combined with missing signal sources, 4
attributes display as perpetually zero — the "cold organism" state
capsule-contract §3.4 acknowledges as intentional.

---

## Activation roadmap

Priority order for wiring dormant attributes, based on signal availability
and architectural readiness:

1. **`percept` source (T-attr-1e)** — unblocks Suspicion (repeated percept
   shape) and strengthens Curiosity (novel/weak percept) and Hunger
   (no-progress signal). Highest leverage for remaining dormant signals.

2. **`resonance` source (T-attr-1e)** — unblocks Suspicion (handle-match is the
   canonical suspicion trigger) and strengthens Curiosity (contradictory
   resonance). Second highest leverage.

3. **`tool_error` source (T-attr-1e)** — strengthens Metamorphosis (repeated
   tool failures) and Doubt (tool evidence incomplete). Lower priority: both
   attributes are already active.

4. **Cross-attribute cascade** (post T-attr-1) — Friction's brief triggers
   (Hunger high + Suspicion high) require reading other attribute values
   during delta computation. Not a source per se, but needed to make Friction
   responsive to organism metabolism rather than only intervention outcomes.

---

## Change history

| Date | Change | Source |
|---|---|---|
| 2026-05-25 | Initial wiring status — mapped all 8 attributes against implemented sources, documented structural locks and activation roadmap. | Attribute audit session. |
| 2026-05-25 | Curiosity and Hunger wired to active. Sensor source implemented (segment_backlog, typing_active, typing_idle). Curiosity also wired to hippocampus trace_marked. Roadmap updated — sensor done, percept + resonance remain for Suspicion. | T-attr-1e-sensor. |
| 2026-05-29 | `trace_marked` Curiosity delta reduced from −0.05 to −0.025 — production observation showed perfect daily cancellation against sensor `segment_backlog` (+0.05). See design-contract §6H footnote 6. Per-segment backlog scaling deferred to `T-attr-1e-percept` companion work. | Post-T-attr-1e snapshot review. |
