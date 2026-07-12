# 06-COHESION.md — Cohesion smells

## Files with likely single-purpose cohesion (well-factored)

The majority of SATAN modules appear well-cohesioned, each with a clear single responsibility:
- `dl-satan-block.el` — owned-block find/replace (pure)
- `dl-satan-budget.el` — daily token ceiling (single concern)
- `dl-satan-jsonl.el` — line-buffered JSON handling
- `dl-satan-protocol.el` — protocol validator
- `dl-satan-memory-grammar.el` — grammar constants
- `dl-satan-memory-canon.el` — canonicalizer + rules (purity-enforced)
- `dl-satan-memory-store.el` — PG store backend
- `dl-satan-patch-adapter.el` — abstract adapter base
- `dl-satan-patch-classify.el` — work classification
- `dl-satan-tools-notify.el` — single tool (simplest file at 59 LOC)

## Files with potential split concerns

### `dl-satan-observer.el` (859 LOC, 33 defuns)

Contains:
- Classification logic (`classify-for-motive`, `classify` at L474)
- Persistence logic (`persist-positive` at L614, `persist-verdict`)
- Broker integration (`observer-process` at L721)
- Dedup/correlation logic
- Motive/timestamp parsing

Split into 2-3 concerns: classification, persistence, integration.
  confidence: medium — the function count (33) across 859 LOC suggests multiple responsibilities.

### `dl-satan-broker.el` (797 LOC, 35 defuns)

Contains:
- Mode resolution
- Context assembly delegation
- Tool dispatch
- Process lifecycle (`make-process`, sentinel, timeout)
- Budget checking
- Env resolution (direnv, op://)
- Audit handle management
- Failure notification

The broker is a god-class by design (architecture doc: "Broker — trusted authority"). The function count (35) and LOC (797) reflect its central role. The governance doc explicitly calls this out as intentional.
  confidence: high — by-design centrality, not a cohesion smell per se.

### `dl-satan-tank.el` (554 LOC, 28 defuns)

Contains:
- Observation reading from audit bundles
- Last-run state parsing
- Tank rendering for context assembly
- Aggregation helpers

This module bridges the broker (requires `dl-satan-broker`) and the memory substrate (requires `dl-satan-memory-evidence`, `dl-satan-memory-store`, `dl-satan-memory-grammar`). The tank's dual concern is reading broker audit bundles AND assembling evidence — two separate data sources.
  confidence: medium — consider whether evidence-reading and audit-reading are separable.

### `dl-satan-tools-atsatan.el` (392 LOC, 13 defuns)

Contains:
- `@satan` directive scanning/classification
- `@satan-was-here` block rewriting
- Tick-agent registration (`dl-satan-tick-register`)
- Claim/done logic

The file mixes notes-scanning logic with mode-registration side effects. The `dl-satan-tick-register` call at load time adds tools to a mode — this is a side effect that couples directive scanning to mode configuration.
  confidence: medium — tick-register at load time is a design choice but mixes concerns.

### `dl-satan-context.el` (526 LOC, 25 defuns)

Contains:
- Mode-specific context assembly (morning, motd, tick, self-edit)
- Prompt assembly and rendering (`--assemble-prompt`, `--render-prompt`)
- Perceptual-layer block assembly (percept, resonance, motive, sensor-alerts)
- Recent-runs block rendering

The context module imports from the perceptual layer (percept, resonance, motive, sensor-alerts) to assemble bundle sections. This is a natural aggregation point, but the file is at 526 LOC.
  confidence: low — this is the intended design per architecture doc.

## Catch-all files

- `dl-satan-test.el` (2337 LOC) — the largest test file by far. Contains tests for ~15 modules. This is the shared test file used when modules don't have dedicated test files. A potential split candidate.
  confidence: high — 2337 LOC test file is a maintenance burden.
