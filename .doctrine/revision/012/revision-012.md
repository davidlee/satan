# REV REV-012 — reconcile SL-029

Revision — a pending revise-intent against authored governance/spec
truth. The structured `[[change]]` payload lives in the sister `revision-NNN.toml`;
this prose companion carries the rationale and the free-text before/after excerpts
for prose-body section edits.

## Rationale

<!-- Why this revision: what authored truth needs to change and why, the scope of
     the staged delta, and (for ADR/POL/STD/prose rows) the before/after excerpts
     the structured payload only labels. Seeded at `revision new`. -->

SL-029 built `pi-mcp`, a stdio MCP server that runs one jailed pi delegate per
call. Its audit (RV-055) found three governance texts silent on what was built.
None of the changes below is a new decision: each restates what SL-029 decided
(DEC-091, DEC-097) and verified.

- **ADR-017 authority ledger** (`.doctrine/adr/017/authority-ledger.md`). New
  legend token `pi-mcp`. New rows: 1b (request schema validation), 2b
  (profile → tool allowlist), 4c (delegate audit), 5c (delegate ceilings:
  retrospective accounting, best-effort termination), 6c (kill switch: admission
  refusal *and* active halt), all owned by `pi-mcp`; and 3c (the per-call
  execution forms), owned by `satan-flake`. A transition block records each row
  as `(new)`. The summary paragraph names SL-029. No existing row changes owner.
- **SPEC-001 REQ-004** (rationale, appended). Records the three properties
  weaker than "cannot exceed": retrospective rather than admission control; the
  run's own sends only, which excludes nested `pi`, direct gateway calls,
  tool-result-only spend and extension-mediated summarization; and the per-run
  gateway token (IDE-015) for the rest. Also records the wall-clock backstop that
  reconcile's policy fix made mandatory. Status stays `pending`.
- **SPEC-002 REQ-016** (rationale, appended). The per-call forms are a consumer
  class: the `pi-mcp-forms` check (a residue over a derived generator baseline)
  ran green on 2026-10-21, and a confinement probe under both real forms found
  the audit unreachable. The open gap is IMP-048 (`child_binds` exposure, and a
  policy-vs-baseline check). Status stays `pending`: ISS-028 and ISS-043 are
  still open for other classes.

DEC-093 is a knowledge record, which a REV cannot target. Its reconcile
corrections (`pi-run-status/2`, `final` derived in the server, the
`status.state` divergences, `session: null` on a refusal, transcript budget
semantics) were appended to DEC-093 directly with `doctrine knowledge edit`.

User agreement: "yes" to reconcile, and the three settlement decisions
(2026-10-21, this session): fix the maxima gap in code; keep and document
`final`; backlog the `child_binds` schema change.

## Reconcile narrative

- [RV-055 brief, DEC-091]: the ledger had no rows for `pi_agent`'s own
  authority. Rows 1b, 2b, 3c, 4c, 5c and 6c now carry it, each anchored to a live
  symbol.
- [RV-055 brief, DEC-097]: REQ-004 claimed more than the delegate gives. Its
  rationale now states the three weaker properties.
- [RV-055 brief, F-1 → PHASE-09 operator run]: REQ-016 was pending on the
  bind-set check having run. It has run, so the class is recorded and its
  remaining gap is tracked (IMP-048).
