---
name: satan-index
description: SATAN docs index — one-line hooks into every chunk under docs/satan/
metadata:
  type: reference
  topic: satan
  status: living
  updated_at: 03398479
  verified_at: 03398479
---

# SATAN docs index

## Governance & architecture
- [governance](governance.md) — proposal-first, source of truth, scope of agency, file map, modes, tools, ops
- [architecture](architecture.md) — invocation / broker / adapter / model / tool / output / state
- [protocol](protocol.md) — JSONL wire protocol (message types, fixtures)
- [perceptual-design](perceptual-design.md) — v0 percept capsule, auto-resonance, motive file, outcome observer, sensor alerts, cooldown floor (Phases 0–6 shipped 2026-05-22→23; see doc §1.5)
- [epistemics-roadmap](epistemics-roadmap.md) — gap analysis: scientist loop (hypothesis/probe/patterns) vs built; sequencing patterns→probe→hypothesis (DE-009 = step 1)

## Attribute layer
- [attributes.brief](attributes.brief.md) — brief: Brooding + mechanical Shame, 8 attrs, update inputs, deltas, persistence, capsule render
- [attributes/outcome-semantics](attributes/outcome-semantics.md) — design contract — outcome classification vocabulary, lifecycle, evidence, revision (T1.5a, merged)
- [attributes/design-contract](attributes/design-contract.md) — design contract — attribute layer vocabulary, storage, event schema, update rules, caps, rebuild (T-attr-1a)
- [attributes/patterns_attributes.design_note](attributes/patterns_attributes.design_note.md) — design note — global attributes vs pattern-local scars; rules out pattern-specific attribute vectors
- [attributes/wiring-status](attributes/wiring-status.md) — living reference — which attributes are wired, dormant, or structurally locked; activation roadmap

## Memory substrate
- [memory/design](memory/design.md) — grammar, canonicalizer, evidence window, schema
- [memory/handover](memory/handover.md) — current memory-substrate state

## Patch agent
- [patch/brief](patch/brief.md) — technical brief
- [patch/plan](patch/plan.md) — implementation plan
- [patch/handover](patch/handover.md) — current patch-agent state
- patch/archive/ — superseded handovers

## @satan agent triggers
- [at-satan/design](at-satan/design.md)
- [at-satan/plan](at-satan/plan.md)

## Tracking
- [resonance-payload-handover](resonance-payload-handover.md) — shipped 2026-05-30: inline the recalled trace's payload text in the resonance block
- [bough-gaps](bough-gaps.md) — bough CLI gaps surfaced by SATAN
- [follow-ups](follow-ups.md) — durable cleanup / audit items deferred during perceptual-layer v0
- [refactor/plan](refactor/plan.md) — refactor themes index (T1, T1.5, T2–T4, T6–T8, T-attr-1)
- [refactor/extraction-policy](refactor/extraction-policy.md) — guiding policy + standing candidates for moving modules out of `.emacs.d/`
