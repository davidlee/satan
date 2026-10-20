# Review RV-043 — design of SL-029

Adversarial-review ledger. Structured findings live in the sister
ledger toml; this prose companion carries the reviewer's framing.

## Brief

Review of SL-029 design revision 37 (seven materialised sections), requested by the operator after the informal inquiry critique. Raiser-only pass: raise evidenced defects and conclude; leave design changes, dispositions and user acceptance to the author/operator.

Lines of attack:
- Confinement: explicit launch-dir bind modes, writable aliases, child access to server-owned audit/session/policy state, and host/jail path translation in both postures.
- Enforcement: retrospective usage accounting, missing/pricing data, request-count semantics, kill-switch behaviour and fail-closed audit.
- Lifecycle: cancellation/EOF/signals, process-group termination, concurrent calls and cross-process session ownership.
- Results: final versus partial prose, reducer/exit/abort precedence, refusal artefacts, transcript semantics and bounded responses.
- Delivery: scope/selectors versus commitments, tested wrapper declarations, policy schema/publication and authority placement.

Basis: SL-029, DEC-089–100, ADR-017, SPEC-001/002, pi/reduce implementation and tests, installed pi 0.99.1 JSON/CLI/session documentation, and the jailed-agent generator/checks in /workspace/flakes/agents. The operator's three new claims are checked explicitly; no implementation is being reviewed or changed.
