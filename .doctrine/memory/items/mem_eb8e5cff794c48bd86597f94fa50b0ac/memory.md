# SATAN perceive-consume seam

# SATAN perceive/consume broker seam

The SATAN tick (`satan-broker-run`) is cut into **perceive** and **consume**
([[DE-010]], landed 2026-06-10; ratified by [[ADR-001]]).

## Control flow (as built)

```
broker-run: prepare (alloc run_id, freeze time_now) → mkdir run-dir
  → PERCEIVE (unconditional, pure)
  → if perceive failed → no-child failed bundle, return
  → if another run's child is live (`satan-run--spawn-running`, DEC-023)
      → silent no-child `run_busy` bundle, return
  → if budget-exceeded → no-child denied bundle, return   ← ISSUE-001 fixed
  → else CONSUME (effects + tokens)
```

- **Perceive** (`satan-run-perceive`) = percept-build + persist `percept.json`
  + probe **read-snapshot** + ingest-cursor heads (`satan-ingest-cursor-heads`,
  under `:ingest`) (frozen onto `prepare :probe_snapshots`, internal,
  never serialized → bundle byte-stable). PURE: no LLM, no tool dispatch, no
  attribute enqueue, no consumption-state mutation. Runs **before both gates** —
  budget-denied no longer skips perception. Its ONLY write is `percept.json`.
- **Consume** (`satan-broker--spawn`) = observer + resonance + motive +
  sensor-alerts + bundle + `make-process` (LLM). The **frontier commits**
  (probe-commit ×3 + ingest-cursor advance to the perceive snapshot) run on the
  child's **first `ready`** (`satan-broker--commit-frontiers`, once-only
  guard = `satan-run-ready` slot; SL-022 PHASE-03, I5). A child that dies
  before `ready` without sending `error` is `spawn_failed` (broker
  `spawn-failed` event with `:process-status`/`:code`/`:stderr` tail) and
  commits nothing.
- `assemble-context = enrich∘perceive`; `-probe = commit∘read`. Single percept
  builder (`satan-percept-build`).

## No-child terminal paths (`--write-no-child-run STATUS REASON`)

Shared helper; three callers, all mirror `:percept` into `bundle.json` (consumers
read it THERE, not the sidecar):

| caller | status | reason | .FAILED? | announce? |
|---|---|---|---|---|
| budget-denied | `budget-exceeded` | — | yes | yes |
| **run-busy** (`--write-silent-run`) | `failed` | `run_busy` | **NO** | **NO** |
| perceive-failed | `failed` | `perceive_failed` | yes | yes |

run-busy is verify-clean and silent (it must not pop desktop alerts). An
in-flight MCP call no longer gates the tick: DEC-8 was retired by DEC-124
(SL-032 PHASE-02); `session_blocked` appears only in old run dirs. Since SL-017 PHASE-07 there is no global failure-streak counter:
`satan-broker--failure-streak` walks the per-mode, same-cause streak from run
outcomes (`satan-run-outcome-streak`), and `session_blocked` /
`credential_deferred` are transparent (`satan-broker--streak-transparent-reasons`)
— they neither extend nor break a streak.

## Related

- [[mem.fact.satan.ingest-cursor-store]] — the frontier the first `ready` advances.
- [[mem.pattern.satan.sensor-watermark-format]] — probe watermark = native ts.
- Signal model UNCHANGED (perception still reads present-tense live state; not yet
  replayable → IMPR-013).
