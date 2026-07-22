
# Provider error typing for harness failures

Today the string heuristic in crash-context is diagnostic-only, not a control
signal. A typed exception layer would let resilience logic branch on failure
class.

**Blocked / deferred:** the provider-agnosticism goal means any typed exception
layer must support N providers — not worth it until rate limits are real (see
RISK-001). Revisit when 429s become a real failure mode.

Migrated from `docs/satan/resilience-design.md` §6 "Resolved decisions" #5 (2026-05-30).
