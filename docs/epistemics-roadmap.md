---
name: satan-epistemics-roadmap
description: Gap analysis of SATAN's scientist loop (hypothesis/probe/patterns) vs what's built, and the sequencing to close it
metadata:
  type: reference
  topic: satan/epistemics
  status: living
  updated_at: 2026-06-03
  verified_at: 2026-06-03
  source: ~/notes/intake/20260519T003129--satan__agent_emacs_project.org
---

# SATAN epistemics roadmap

Gap analysis of the vision synthesis (`~/notes/intake/20260519T003129…org`) against
the codebase as of 2026-06-03, plus the sequencing to close the gap. Companion to
`attributes/patterns_attributes.design_note.md` (normative) and `perceptual-design.md`.

## The central finding

The **metabolism** is the most-built layer; the **epistemics** is the least-built.

- Attributes (metabolism) — 8 attrs, mechanical Shame, outcome observer, sensor
  sources, capsule rendered into prompt. Mature.
- Hypothesis loop / probe surface / pattern records (epistemics) — **0% built.**

The organism-vs-nudge-machine differentiator the vision keeps invoking (§3, §16) lives
entirely in the unbuilt half. Today the system *is* the "context-aware nudge machine"
§3 warns against, and risks §15's "dashboard death": rich rendered state (tank),
attribute shifts on outcome — but nothing to *test*.

## Built vs vision §2/§6/§11

| Layer | State | Evidence |
|---|---|---|
| Read/memory/write/staged tools (§2) | all real | `satan/dl-satan-tools-*.el`, `dl-satan-patch-*` |
| Attribute layer (§6) | mature | `dl-satan-attribute*.el`, `dl-satan-observer*`, DE-001 capsule |
| Habitat / tank (§11) | partly built (text) | `dl-satan-tank.el` |
| Percept loop (§5) | Phases 0–6 shipped | `dl-satan-percept.el`, `perceptual-design.md` |

## Genuinely missing — vision §3 is accurate

| Piece | Code | Note |
|---|---|---|
| Hypothesis loop (§8) | none | no board, no claim/predict/test/observe |
| Probe surface (§9) | none | no question/answer/outcome-window record |
| Pattern records + scars (§7) | none | design note exists, shape spec'd, zero impl |
| Outcome→belief update | **half** | observer updates global attrs; pattern/hypothesis halves absent |
| Direct user evidence capture | none | rides on probe |

## Design tensions to keep in view

1. **Vision §6 leans on attributes that cannot move** (see `attributes/wiring-status.md`):
   - **Friction/Cruelty structurally locked at 0** — no positive source AND cap
     `friction ≤ max(0, 1 − doubt − shame)` = 0 at current doubt+shame=1.0. §6
     "Cruelty high → sharper wording" can never fire.
   - **Suspicion near-dormant** — its canonical trigger (handle-match resonance) needs
     the reserved `resonance` source AND patterns, which don't exist. §16's spine
     "let it ring the past → testable suspicion" is unwired at both ends.
2. **Outcome observer updates only the global half.** The design note mandates outcomes
   update both global attrs and pattern records. Only global exists → no pattern-local
   learning, cooldown, or scars. This is the missing half of an *existing* mechanism.
3. **Percept doesn't feed attributes.** `percept`/`resonance` are reserved sources, so
   §5 step 6 ("consult/update attributes" from percept) is aspirational.

## Sequencing — reordered from vision §14

The vision lists the hypothesis board first. Dependency order argues otherwise:

1. **Pattern records + scars** → **DE-009** (this step). Cheapest, highest leverage:
   extends the existing outcome observer rather than greenfield, and unblocks Suspicion
   semantics. It is the missing half of a mechanism that already half-runs.
2. **Probe record.** Direct evidence capture; can ride `inbox_append` with a recognizable
   format initially (§14.2 concedes this) before a first-class record.
3. **Hypothesis board last.** Needs pattern handles + probe outcomes to be non-vacuous.
   Building it first = §15 "fake science" — claims with no test/outcome plumbing.

Rationale for not following §14's order: building the hypothesis board before patterns
and probes gives it nothing to test against and nowhere to record scars, so it would
render state without testing anything (§15 dashboard death).

## Vision tail ideas (§795) vs reality

- **@satan note-expose + remove-line** — largely *already shipped*: `notes_at_satan_scan`
  + `notes_at_satan_done` lifecycle (`dl-satan-tools-atsatan.el`). Do not re-spec.
- **image search → tank** — tank exists (text habitat); image display not built. Small add.
- **async deferred-cognition task** — genuinely missing. `patch_job` is async but
  *edit-shaped*; no general async queue for non-edit cognition (e.g. summarize-URL-later).

## Tracking

- [x] DE-009 — pattern records + scars (step 1). **Complete 2026-06-03.**
  - Pattern definitions in `satan/patterns.eld` (3 seed patterns, grammar-validated sync)
  - Immutable percept-handle snapshots stamped on every intervention
  - Containment-based rebuild projection (`satan_pattern_outcomes` + `satan_pattern_stats` view)
  - Guarded/isolated rebuild at observer tick end (structural non-regression of global path)
  - Delivered in 3 phases: P01 schema+snapshot, P02 definitions+rebuild, P03 observer wiring+guards
- Steps 2–3 (probe, hypothesis) — not yet scoped; file as deltas now that step 1 has landed.
  - Probe record can ride `inbox_append` with recognizable format initially
  - Hypothesis board needs pattern handles + probe outcomes; DE-009 unblocks both
