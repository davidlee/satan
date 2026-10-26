# Review RV-061 — reconciliation of SL-032

Adversarial-review ledger. Structured findings live in the sister
ledger toml; this prose companion carries the reviewer's framing.

## Brief

Mode: conformance (self-audit). Surface: satan main tree at 4aa5c51
(code ends aad0d4c); malebolge main tree at c3cdcaf (code a737928).

Lines of attack:

1. Mechanical conformance — `slice conformance 32` (undeclared /
   undelivered) and `slice verify-vt 32`.
2. Gates — satan `just check` + `doctrine check gate`; malebolge
   `just check`.
3. Design invariants I1-I5 (`satan-mcp.el` header) and V1-V16 each map to
   a VT/VA/VH with recorded evidence (notes.md Execution log).
4. Divergences between design.md (sec-3 lifecycle, sec-7 client, sec-9
   verification) and what landed, including phase-level decisions
   (PHASE-05 D1/D2, PHASE-06 A1-A8, PHASE-07 VA-1, DEC-126).
5. Governance follow-through named in design sec-91: SPEC-001 REQ-007 /
   QUE-001, SPEC-002 transports row, memory mem_eb8e5cff, malebolge
   IDE-002.
6. RV-060 (design review) deferred instrument findings F-1..F-3 closed
   against the phase VA evidence.

## Synthesis

SL-032 delivers what it set out to: an MCP run per conversation window, not
per process. Evidence:

- satan PHASE-01..06 (49b144d..aad0d4c): verify-vt PASS for all 20 VTs;
  gate 1378 tests, 0 unexpected (TZ=Australia/Brisbane, 2026-10-27; see F-9
  for the host-time flake). malebolge PHASE-07 (a737928): 2105/2105 green,
  re-run in this audit.
- Every V1-V16 maps to a plan VT/VA; V13 ran live in PHASE-08 (malebolge
  5775ac5, satan 85fab44): two interactive run dirs naming conversations
  "1" and "1519", a broker tick spawned and finished while both were open,
  both finalised by the 15 min idle close and passed
  `satan-audit-verify-run` (I4). User confirmed VH-1.
- RV-060 F-1..F-3 (design-review instrument findings) are discharged by
  PHASE-06 VA-1/VA-2, PHASE-05 VA-1/VA-2 and PHASE-07 VA-1 respectively.

No code finding stands against the slice. The findings are drift between
canon and what landed: sec-3/sec-7/sec-9 lag phase-level decisions that
the user took mid-flight (DEC-126, the awaited refresh), the selector
registry missed two PHASE-01 files, and the governance items the design
already scheduled for reconcile (SPEC-001 REQ-007, SPEC-002, one memory).

Standing risks:

- malebolge IMP-013: a failed tools/list refresh empties the satan
  extension; per-entry refreshes (sec-7) make it more reachable. Deferred
  by the user.
- RSK-020: the room daemon runs the malebolge live tree; PHASE-08
  verified 5775ac5 only.
- Quit propagation to an enclosing caller is not batch-observable (F-5);
  relied on Emacs semantics plus the nested quit-flag deferral.
- More run dirs (one per activity window): readers are capped; revisit if
  the capsule's recent-runs block crowds out broker runs.

Accepted tradeoffs: PHASE-07 attribution via notes rather than the delta
registry (F-2, tool limit); the 3 activity-test failures treated as
outside the slice (F-9 → ISS-061). The malebolge Emacs client cannot show
two conversations at once (malebolge IMP-014); V13 worked around it.

## Reconciliation Brief

### Per-slice (direct edit)

- F-1 — selector registry (load-bearing): `doctrine slice selector add 32`
  design-target for satan/satan-intervention-mark.el,
  satan/satan-tools-atsatan.el, and tests satan-audit-test,
  satan-broker-test, satan-mcp-test, satan-intervention-mark-test,
  satan-memory-store-test, satan-observer-test, satan-tools-atsatan-test,
  satan-tools-memory-test (all under satan/test/). Mirror: design.md sec-8
  code impact lists the two source files.
- F-3 — design.md sec-3: `in-flight` is the list of in-flight request ids;
  Settle covers any non-error non-local exit per DEC-126 (reason "exit",
  closes the transport like quit); a quit in a nested filter is deferred
  to quit-flag (`--filter-depth`, `--resignal-quit`) because a quit
  cannot cross the C process reader; -32603 is sent only on an open, live
  session; `--deliver` records cancelled/disconnected instead of sending;
  the verifier change is a `calls-match-results` docstring + VT (no event
  registry).
- F-4 — design.md sec-7: the first call of a new pool entry awaits the
  coalesced refresh (bounded by the refresh deadline; not replayed) and
  why (VA-1: pi-durable resolves tools at step start); idle default in
  satan-pool.ts, overridable by `MALEBOLGE_SATAN_IDLE_MS` (strict
  integer); cite malebolge IMP-013 as the known residual risk.
- F-5 — design.md sec-9 V15: quit propagation to an enclosing caller's
  wait is not batch-observable; the test drives `satan-mcp--filter` over a
  live socket pair. (plan.toml untouched.)

### Governance/spec (REV)

- F-6 — SPEC-001 REQ-007: REV either admitting transport-scoped run
  lifecycle for MCP (open on first tools/call, close on transport close),
  or recording the divergence against QUE-001. User picks. Transport
  cleanup is not ADR-017 §4 evidence.
- F-7 — SPEC-002 transports table, MCP row: REV adding "one connection per
  conversation window, plus one shared tool-list connection; identity in
  `initialize`" (DEC-121, DEC-125).

### Memory (before close)

- F-8 — mem_eb8e5cff (mem.fact.satan.perceive-consume-seam): remove the
  "MCP call in flight → blocked bundle" step; DEC-8 retired by DEC-124
  (SL-032 PHASE-02); session_blocked survives only in old run dirs.
