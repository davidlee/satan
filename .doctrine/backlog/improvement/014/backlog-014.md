# IMP-014: SATAN tick perf phase 3: percentile reporting + budget-breach sensor alert

Gated by SL-011 (tick trace + subprocess ledger must exist first).

Once trace JSONL accumulates:

- p50/p95 per pipeline stage derived from tick-trace rows; surface in a
  report command or waybar detail.
- Tick wall-budget breach raises a sensor alert through the existing
  `dl-satan-sensor-alerts` infra, so perf regressions surface instead of
  drifting silently.

Also quantifies the win when ADR-001 / DE-010 perception extraction lands —
before/after per-stage numbers come free from the same trace.
