# QUE-001: SPEC-001 has no invariant for run-lifecycle/arrival authority that ADR-017 §3 lists

<!-- Knowledge record body — context, detail, links. The structured, queried
     fields live in the sister `record-NNN.toml`; this prose is free-form and is
     never structurally parsed (the storage rule). -->


## Extension (2026-09-23, SL-018 / DEC-022): pre-spawn lifecycle gates

The question covers every **pre-spawn lifecycle gate**, not only arrival
policy. Four gates in `satan-broker-run` decide whether a scheduled run
spawns. Only `budget_denied` maps to a SPEC-001 REQ, and none has an
authority-ledger row:

- DEC-8 `session_blocked`: an interactive MCP session is open.
- `budget_denied`: the daily token ceiling (covered by REQ-004, token and budget ceilings).
- `credential_deferred` / `credential_unavailable` (SL-018, DEC-020/021/022):
  no 1Password session, and the mode's policy defers, or the prompt failed.
- `run_busy` (SL-018, DEC-023): a scheduled run arrives while a child is live.

A future run-lifecycle invariant should state that each gate fails closed
(SPEC-001 REQ-010) and records a no-child run with a typed reason, so that
every non-spawn is visible in the run bundles.
