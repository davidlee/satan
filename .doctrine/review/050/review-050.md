# Review RV-050 — reconciliation of SL-028

Adversarial-review ledger. Structured findings live in the sister
ledger toml; this prose companion carries the reviewer's framing.

## Brief

<!-- Pre-reading + lines of attack: what this review is probing, the invariants
     it must hold the subject to, and where the bodies are likely buried. Seeded
     at `review new`; the reviewer fills it before raising findings. -->

Mode: conformance. Surface: main working trees of malebolge, ~ (flakes), satan,
satan-corpus, emacs, notes — no dispatch candidate (phases ran in-session).

Lines of attack:
- Path conformance per repo, by hand: `slice conformance` and `slice verify-vt` read only
  satan's git, and 21 of 22 selectors are cross-repo.
- Every design §5 row delivered; every delivered file declared (§5 / selectors).
- Checks green at HEAD: malebolge `just check`, satan `just check` + `nix flake check`,
  ~/flakes `just test`/`just gate`/`home-build`, `doctrine check gate`.
- Live VA/VH evidence (notes § PHASE-06) against design §6; substitutions named.
- §4.6 governance deferred to reconcile (REQ-015, SPEC-002) still stale vs deployed reality.
- Invariants: ADR-017 authority ledger unchanged (unit is service management, not a kill
  switch — design §4.1); satan-mcp bind read-only (DEC-088).

## Synthesis

- **Overall**: solid
- **Synopsis**: SL-028 makes malebolge's interactive daemon an on-demand user unit
  (`malebolge-room`) that Emacs starts and stops, tolerates satan-mcp's absence (zero
  tools, refresh before each input), refuses a second instance (SQLite lock + socket
  claim), and reaches satan-mcp through one read-only directory bind in every jail
  (`satanMcpOptions`). All six phases delivered; every design-target selector matched
  an edit. Suites green at HEAD across malebolge (1655), satan (1309), flakes; per-phase
  reviews RV-041/042/045/047/049 concluded. Live: unit shape and switch immunity proved
  with a changed unit and an unchanged PID; degraded start and tool recovery observed;
  VH-1..3 performed by the user. VH-1 caught a real defect (no autoload for -start/-stop)
  that no test could see — the value of the human check.
  Accepted: the conformance tools cannot see this cross-repo slice (F-2), so conformance
  was done by hand; EX-5 ran with a refused socket rather than an absent directory (F-4).
  Standing: RSK-020 — two malebolge revisions in production (pinned runner, live-tree
  daemon), documented in SATAN.md, tracked against REQ-015 once reconciled. A running
  daemon lags a changed wrapper until restarted (design §7). IMP-047 out of scope.
- **Haiku**: Six rooms built by hand; / the auditor's lamp finds doors / the plan never drew.

## Reconciliation Brief

### Per-slice (direct edit)
- F-1 — `design.md` §5 Code Impact: add rows — malebolge `src/coalesce.ts`,
  `src/reconnecting-client.ts` (refresh coalescing / lazy reconnect, extracted in
  PHASE-02), `src/attach-main.ts` (exit 1 on give-up), `justfile` (daemon recipe
  comment); flakes `features/profiles/personal-linux.nix` (enable) and
  `features-test.nix` (selection expectation); emacs `apps/dl-satan.el` (`:commands`
  lists `malebolge-start`/`-stop`). Load-bearing: `doctrine slice selector add` each as
  `design-target` with a cross-repo note; the §5 rows are the mirror.

### Governance/spec (REV)
- F-3 — SPEC-002 (`spec-002.md:36`, Interactive daemon row, Runtime): add "on-demand
  user service", not naming the unit (SPEC-002 D2) → REV modify.
- F-3 — REQ-015 Rationale: "Tracked gaps: RSK-016." → "Tracked gaps: RSK-016, RSK-020."
  → REV modify.

### For close (not reconcile writes)
- Backlog IMP-045, IMP-039, ISS-042 resolved at close (design §4.6); RSK-020 stays open.
