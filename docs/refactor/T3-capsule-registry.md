---
name: satan-refactor-T3
description: Capsule render registry — sections ordered/named/registerable with byte-identical output
metadata:
  type: refactor-theme
  topic: satan-refactor
  status: not-started
  blocked_by: []
  updated_at: 2026-05-23
---

# Theme T3 — Capsule render registry (narrow)

**Impact:** Med. **Effort:** S–M. **Risk:** Low (narrow scope). **Reversibility:** Easy.

## Current shape

26 render-* / format-* functions across 11 files (sub-agent D). 5 broker-side assemblers in `context.el` (now/today/sources/recent-runs/prompt); per-module `render-block` in `percept.el`, `resonance.el`, `motive.el`, `sensor-alerts.el`. Block headers live in `~/notes/satan/system/framing.txt` (8 keys; text-first ethos preserved). `--render-prompt` reads framing + calls each block's render-fn in a fixed sequence inside its body.

## Why it hurts

Adding attribute bars = write `dl-satan-attributes-render-block` + add framing key + require + a line in `--render-prompt`. Three touch points, no automatic test that the block was registered. Future blocks (Pressure, Brooding state, Metamorphosis triggers per attributes.brief §4) repeat the pattern. GPT-5.5: *"Attribute presentation is not just rendering; it becomes part of how the model perceives itself and how the user audits state."*

## Target shape (narrow)

A capsule registry in `dl-satan-capsule.el`. `dl-satan-capsule-register` takes `:order`, `:framing-key`, `:render-fn`. `--render-prompt` becomes a fold over the registry. Adding attribute-bars = one register call.

## Migration sketch — pick ONE path

- **Path A (narrow registry before attributes).** PR 1: define registry + register helper, no callers. PR 2: register every existing block via the new API. Golden-file test asserts byte-identical output across all modes.
- **Path B (skip the registry).** Land attribute bars via the existing 11-file pattern. Defer the registry until rendering pain is real.

**Recommendation: Path A.** Cheap, byte-identical, gives attribute bars a clean register-call. Flips to Path B if PR 2's golden-file test surfaces existing render-order surprises that imply implicit invariants.

**Do NOT bundle T3 with first-time attribute UX in one PR.** Mixes registry invention with the model-perception-relevant rendering of the bars themselves.

## Abort condition

Path A only proceeds if PR 2's golden-file test confirms byte-identical output. Surprise = stop, write up the invariants, decide whether to continue or fall back to Path B.

## Considered and rejected

- Promote `framing.txt` to a full dispatch registry — text-first is great for headers, bad for function dispatch.
- Re-aggregate all renderers into `context.el` — re-creates a god file.
- Hook-based — loses ordering guarantees.

## First concrete step

PR 1 (data + helpers, no callers). PR 2 only if the golden-file test confirms byte-identical output.

## Open questions

- Should the registry enforce framing-key presence at register-time, or fail gracefully at render-time? (Recommend register-time per protocol.md fail-loud ethos.)

## PR log

- [ ] PR 1: registry + helpers (no callers) — pending
- [ ] PR 2: register all existing blocks + golden-file test — gated
