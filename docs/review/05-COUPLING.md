# 05-COUPLING.md — Coupling smells

## Broker centrality (intentional — see architecture doc)

`dl-satan-broker.el` requires 14 modules. It is the central orchestration hub. Per the architecture doc, this is the design intent. However:

- `dl-satan-broker.el` calls private (`--`) symbols from at least: percept, resonance, motive, observer, sensor-alerts, output, context, mode, audit.
  confidence: high — the broker is designed to orchestrate everything; this is intentional coupling.

## Layer-crossing: context-assembler imports perceptual layer

`dl-satan-context.el` imports `dl-satan-percept`, `dl-satan-resonance`, `dl-satan-motive`, `dl-satan-sensor-alerts`. This is context assembly pulling from the perceptual layer. Per the architecture doc, context assembly sits in the broker layer. The perceptual layer's modules (percept, resonance, motive, observer, sensor-alerts) are consumed by both broker and context — context assembly overlaps with broker orchestration.

  `dl-satan-context.el:10-15` — requires percept, resonance, motive, sensor-alerts.
  confidence: high — legitimate but worth noting.

## Tank imports both broker and memory substrate

`dl-satan-tank.el` requires:
- `dl-satan-broker` (orchestration)
- `dl-satan-memory-evidence` (substrate)
- `dl-satan-memory-store` (substrate)
- `dl-satan-memory-grammar` (substrate)

The tank bridges two architectural layers. Per governance doc, this is the tank's purpose (observation/aggregation), so likely intentional.

  `dl-satan-tank.el:24-27`
  confidence: medium — check whether this cross-layer dependency is documented.

## Multiple writers to audit/log paths

`dl-satan-audit.el` is the canonical audit writer, but:
- `dl-satan-observer.el:721` (`observer-process`) writes to audit as part of the outcome observer
- `dl-satan-percept.el` writes to audit via requires on `dl-satan-audit`
- `dl-satan-broker.el` drives the sentinel which calls output handlers that also produce artifacts

The audit handle pattern (opened by broker via `dl-satan-audit-open`, written to by various subsystems) is designed to handle this. The observer's use of audit (persisting verdicts, writing dedup marks) adds another writer alongside the transcript/actions.json writer in the broker.

  confidence: medium — the observer writing its own audit records alongside the broker's audit path is a coupling point worth monitoring.

## Network/op:// resolve duplication

Both `dl-satan-broker.el` and `dl-satan-patch-adapter-pi.el` resolve `op://` references:
- Broker does it for the model harness spawn (`my/op-read-env` + `my/scrub-op-refs-env`)
- Adapter-pi does it for the coding-agent spawn (its own `--resolved-env` function at L231)

These share the same helper (`my/scrub-op-refs-env` in `lisp/dl-secret.el`), which is good. But the env resolution logic in adapter-pi is its own implementation (82 LOC), duplicating the pattern from the broker.

  `dl-satan-patch-adapter-pi.el:231` — `dl-satan-patch-adapter-pi--resolved-env` (82 LOC)
  `dl-satan-broker.el` — op resolution integrated into spawn
  confidence: high — env resolution appears twice with different implementations.

## Observer→motive→memory substrate coupling

`dl-satan-observer.el` requires: `dl-satan-jsonl`, `dl-satan-memory-canon`, `dl-satan-memory-evidence`, `dl-satan-memory-grammar`, `dl-satan-memory-store`, `dl-satan-motive`.

This is a wide import set spanning 3+ architectural layers (observer, motive, memory substrate). The observer uses memory-store for persistence (`observer--persist-positive` at L614), memory-canon for canonicalization, memory-grammar for enums. This cross-layer coupling is by design for the perceptual layer v0 but is the widest import set in the codebase.

  confidence: high — observer is the most coupled file in the codebase (6 requires + calls into motive).

## defcustom grouping

No evidence of scattered, poorly-grouped defcustoms. The heaviest users are:

| File | defcustoms | Topic |
|---|---|---|
| `memory-evidence.el` | 8 | Evidence-window tunables |
| `observer.el` | 7 | Observer timeouts/mode settings |
| `context.el` | 7 | Context assembly paths/templates |
| `tank.el` | 6 | Tank paths/formatting |
| `tools-agenda.el` | 5 | Calendar/Mail config |
| `broker.el` | 5 | Timeouts, direnv, budget |

These are reasonably scoped per module.
