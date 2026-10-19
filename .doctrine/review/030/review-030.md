# Review RV-030 — reconciliation of SL-024

Adversarial-review ledger. Structured findings live in the sister
ledger toml; this prose companion carries the reviewer's framing.

## Brief

<!-- Pre-reading + lines of attack: what this review is probing, the invariants
     it must hold the subject to, and where the bodies are likely buried. Seeded
     at `review new`; the reviewer fills it before raising findings. -->

Subject: SL-024 as landed — malebolge `3f5b506`, `9eb1123`, `b5a08ff`; satan `f677f55` (+ records `8d236f8`, `39b94f7`, `3f49a39`). Mode: conformance, self-audit.

Lines of attack:
- `src/skills.ts` against design §4 parsing rules 1-6, Duplicates and Rendering, and against the pi 1.3.0 source they cite (`utils/frontmatter.ts`, `core/skills.ts:420-455`, `formatSkillsForPrompt`).
- RV-028 F-1..F-3 carried into code: whitespace-only description skipped (F-1), realpath-then-name duplicate order (F-2), `SKILL.md` presence asserted by the jail profile (F-3).
- Wiring (`config.ts`, `daemon-main.ts`) against §4 Config / Wiring: load once (DEC-067), persona → skills order, count in the startup line.
- Code Impact (§5) completeness — the only declaration for M paths, since selectors cannot fence another repo.
- Evidence: M `just check`, satan gate (in its dev shell), `slice conformance`, `slice verify-vt`, PHASE-02 smoke and PHASE-03 negative controls in notes, VH-1 as reported by the user.

## Synthesis

The slice does what it set out to: malebolge lists Agent Skills in the system prompt with pi's wording, and the jailed daemon advertises goad-backend from the pinned goad-kit. The user confirmed the listing live.

Code reads as a faithful port. Frontmatter extraction, the realpath-then-name duplicate order, and the rule that a name-collision loser does not register its real path all match pi line for line. Two places differ from pi on purpose, both as the design says: a non-mapping or unparseable frontmatter is a logged skip rather than a throw, and pi's leading blank lines are dropped because this is a section of its own. Gates: M `just check` green (97.98% lines against an 85% gate); satan `just lint` green inside `nix develop` (bare `doctrine check gate` fails only because `luau-analyze` is not on the host PATH, which has nothing to do with this slice); `nix flake check` green per PHASE-03 notes, with both negative controls failing as they should.

Standing risks: wording drift from pi (accepted, design §7; the version is pinned in a code comment); non-store skill dirs need a daemon restart (DEC-067). The mechanical evidence tools cannot see the M half of the slice (F-4); this audit replaced them with direct reading.

Accepted tradeoffs: VH-1 steps e/f waived by the user (F-2); a records file in PHASE-03's delta (F-3); the MALEBOLGE_SKILLS jail probe interpolates its binding against the literal-probe convention, guarded by the SKILL.md check and negative controls (F-5).

Not this ledger: RV-028 F-1..F-3 (the design review) still await raiser verification. The code honours all three answers (see the lines of attack).

## Reconciliation Brief

### Per-slice (direct edit)
- design.md §5 Code Impact (RV-030 F-1): add three malebolge rows —
  `eslint.config.js` | ignore `.pi` (doctrine-vendored extensions sit outside tsconfig; type-aware lint baseline fix);
  `test/harness-fixture.ts` | new shared `systemPromptSections` helper;
  `test/persona.test.ts` | moved onto that helper.
  No selector change: M paths cannot be fenced by satan's selectors.

### Governance/spec (REV)
- None. SL-024 has no spec or ADR targets (plan.toml `[specs]` and `[requirements]` empty); DEC-066/DEC-067 hold as implemented.

## Reconciliation Outcome

### Direct edits applied
- design.md §5 Code Impact: added `eslint.config.js`, `test/harness-fixture.ts`, `test/persona.test.ts` rows → matches what landed (finding F-1). User agreement: `/reconcile + /close` invoked on the brief as presented, 2026-10-19.

### REVs completed
- None needed: the brief carries no governance/spec items.

### Withdrawn / tolerated
- F-2 (VH-1 steps e/f waived by the user), F-3 (notes.md in the PHASE-03 delta), F-4 (M half invisible to conformance/verify-vt), F-5 (interpolated jail probe): tolerated; rationale in each disposition.

Reconcile pass complete — handoff to /close.
