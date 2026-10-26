# QUE-001: SPEC-001 has no invariant for run-lifecycle/arrival authority that ADR-017 §3 lists

<!-- Knowledge record body — context, detail, links. The structured, queried
     fields live in the sister `record-NNN.toml`; this prose is free-form and is
     never structurally parsed (the storage rule). -->


## Extension (2026-09-23, SL-018 / DEC-022): pre-spawn lifecycle gates

The question covers every **pre-spawn lifecycle gate**, not only arrival
policy. Three gates in `satan-broker-run` decide whether a scheduled run
spawns. Only `budget_denied` maps to a SPEC-001 REQ, and none has an
authority-ledger row:

- DEC-8 `session_blocked`: an interactive MCP session is open.
- `budget_denied`: the daily token ceiling (covered by REQ-004, token and budget ceilings).
- `run_busy` (SL-018, DEC-023): a scheduled run arrives while a child is live.

(2026-10-18, SL-022 / DEC-042: the `credential_deferred` /
`credential_unavailable` gates were retired with the credential surface. A
refused launch is now a `spawn_failed` run with a child, not a pre-spawn
gate.)

A future run-lifecycle invariant should state that each gate fails closed
(SPEC-001 REQ-010) and records a no-child run with a typed reason, so that
every non-spawn is visible in the run bundles.

## Extension (2026-10-27, SL-032 / RV-061 F-6): transport-scoped MCP runs; DEC-8 retired

- DEC-8 `session_blocked` (listed above) is retired by DEC-124 (SL-032
  PHASE-02). An open MCP session or in-flight call no longer gates a
  scheduled run; `session_blocked` survives only in old run dirs. The
  remaining pre-spawn gates are `perceive_failed`, `run_busy` and
  `budget_denied`.
- MCP runs now have a lifecycle with no control-plane request at all
  (DEC-122): a run is minted on a connection's first `tools/call` and
  finalised when the connection closes (after in-flight calls settle). This
  diverges from SPEC-001 REQ-007 ("run lifecycle … request/response").
  REQ-007 is deliberately left unchanged (user choice at SL-032 reconcile):
  whether connection-scoped lifecycle is admissible, and who holds authority
  over it, belongs to the invariant this question asks for. Transport
  cleanup is not ADR-017 §4 evidence.
