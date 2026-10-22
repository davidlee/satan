# Notes SL-031: Extract pi-mcp as quotient: standalone package, satan cuts over

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## Design triage (2026-10-22, exploring)

Evidence: `research/research.md`. Operator decisions: IMP-051 § Operator
decisions.

- **Shaping decisions, settled by the operator:**
  - Name `quotient`: one bin with a `reduce` subcommand. npm package
    `@davidlee/quotient`.
  - Config is split by authority. The policy comes from env, else XDG.
  - Profiles are looked up local first, and the policy pins each profile's
    capability.
  - The host migrates at cutover.
  - No pi package in v1.
  - Claude Code and Codex are both clients.
  - Built-in help comes from one source, with per-section overrides.
  - v1 publishes to npm, with an explicit operator go-ahead at publish time.
- **Constraining governance.** DEC-089 to DEC-100 and DEC-103 (SL-029), and
  ADR-017 ledger rows 1b, 2b, 3c, 4c, 5c and 6c. Revision candidates: DEC-092,
  DEC-097, DEC-100, the ledger anchors and row 3c, and POL-001's candidate
  list.
- **Risks.**
  - A delegation outage during cutover.
  - The unconfined posture weakens the default.
  - Help overrides are text the model reads.
  - Codex's 60 s tool timeout.
  - Paths cited in memories and docs.
- **Assumptions.**
  - The code is erasable-only TypeScript; to be confirmed by `tsc
    --erasableSyntaxOnly`.
  - Claude Code CLI's MCP timeout is long enough. Observed with 300 s runs.
- **Open questions:** the design inquiries `inq-1` to `inq-13` in the design
  run. OQ-1 to OQ-5 from the scope map onto them.

## Devil's-advocate review (2026-10-22, informal, no RV)

Two pi research runs: `~/.local/state/pi-mcp/runs/run-20261021T234111161Z-6-…`
(security) and `…234139836Z-7-…` (packaging and cutover).

- **Accepted** (the operator: "Apply all"). Each is appended as an amendment to
  DEC-110 through DEC-120.
- **Refuted.** The claim that a `$HOME` root lets a delegate rewrite the policy
  is wrong. Step 8 already refuses it (`childview.ts:97-110`). The real gap was
  that the profile and help directories are missing from the protected stores.
- **Rejected.**
  - Two bins: this reopens the operator's decision.
  - A shipped default profile layer.
  - A digest pin on the unconfined binary.
- **The operator kept v1 contract-only** (no generic form).
- **Present-day bug in satan's pi-mcp**, fixed by this slice (DEC-118
  amendment). The child is spawned `detached` (`spawn.ts:290`), and the server
  kills nothing on stdin EOF or SIGTERM. A client that kills the server can
  therefore orphan the `pi` group.

## Design synthesis (2026-10-22, rev 23)

An independent redraft was compared against the rev-21 draft, and both were merged.
Operator rulings ("accept") are recorded as `2026-10-22b` amendments on DEC-112,
DEC-115, DEC-116, DEC-118, DEC-119 and DEC-120. Multi-root calls → IDE-016.
Scope gained `scripts/lib/pi-report.sh` (reducer consumer) and keeps
`pi/mcp/forms.test.ts` in satan. Correction: stdin EOF already ran the ladder;
only SIGTERM/SIGINT were uncovered.

## Hostile pass (2026-10-22, RV-058)

gpt-6-sol ran it through `codex exec` in three rounds. All 15 findings were
design defects, repaired in prose; the ledger holds the detail. F-8 is routed
`control`: its negative controls must appear on the phase that writes the
drift tests, and the raiser verifies it after `slice phases`.

**Further passes.** None is needed before planning, and the operator judged the
review conducted. Round 3 found nothing new, and all remaining risk sits in
implementation, which the plan's criteria cover. What a further pass would
probe, if one is wanted:

- the cutover table end to end against the real host (`~/flakes`, `.mcp.json`,
  form links);
- the generalised `scripts/hostile-audit` once it exists;
- the forms test's destination path, which the design leaves to the plan
  ("a satan-owned path").

## Harvest
<!-- single-copy: updated in place each harvest; ids only, never restated content -->
fresh-as-of: 2026-10-22 · ready (design locked rev 39; plan, 12 phases; none started) · d203626

### Produced

SL-031 (scope, research, notes, plan.toml/plan.md, phase sheets PHASE-01..12);
DEC-110 through DEC-120, with amendments (incl. 2026-10-22b); IDE-016;
IMP-051 § Operator decisions; design run `dr-01a160a3…` locked; RV-058
concluded, all 15 findings verified; memory
`mem.pattern.review.codex-exec-hostile-reviewer`.

### Learned

- Codex `tool_timeout_sec` defaults to 60 s.
- pi-mcp re-reads its policy on every call; profiles are read only at
  start-up.
- Node refuses type stripping under `node_modules`.
- satan's forms depend on the private `inputs.agents` flake.
- Nothing type-checks `pi/` today (RV-058 F-2): expect `tsc --noEmit` errors
  in PHASE-01.

The first four are in `research/research.md` and the DECs; the last is in the
plan.

### Open

- Uncommitted: only CLAUDE.md, the operator's edit, not SL-031's.
- Next: `/phase-plan` PHASE-01, then `/execute`.
- Operator gates: PHASE-01 VH-1 (secret scan before any push), PHASE-10
  (policy write, smoke confirmation), PHASE-11 VH-1, PHASE-12 (push, publish:
  separate go-aheads).
- No open QUE or ASM.
