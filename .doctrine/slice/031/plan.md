# Implementation Plan SL-031: Extract pi-mcp as quotient: standalone package, satan cuts over

Prose companion to `plan.toml`. Narrative only — no queried data lives here
(the storage rule); the phase list, criteria, verification, and links are
authored in the TOML. Use this for the plan's rationale and sequencing.
<!-- Reference forms: `lib:reference/glossary.md` § reference forms. -->

## Overview

Twelve phases in two runs. PHASE-01 to PHASE-09 build quotient in
`~/dev/quotient` (written `Q` in `plan.toml`); satan is untouched, so the old
`pi-agent` route keeps working throughout. PHASE-10 to PHASE-12 are the host
cutover of design sec-7, one phase for each risk boundary: side by side,
removal, and publish.

```
quotient (Q)                                              satan / host
P01 bootstrap ─ P02 cli ─ P03 config ─ P04 policy v1 ─ P05 profiles + step 8
  ─ P06 spawn + shutdown ─ P07 contracts + drift ─ P08 help ─ P09 probe, pack, nix, tag
                                                        └─▶ P10 side by side (steps 2–6)
                                                            └─▶ P11 removal (step 7)
                                                                └─▶ P12 push, pin, publish (step 8)
```

## Sequencing & Rationale

- **Moving the code is its own phase (PHASE-01).** The 262 moved tests must
  pass from the new paths before any behaviour changes. A later failure is
  then a regression, not a filter-repo mistake. PHASE-01 also brings in
  `tsc --noEmit`, which nothing in satan runs today. Type errors that Node's
  type stripping has hidden will surface here (RV-058 F-2).
- **Behaviour changes follow the data flow of a call.** The entry point comes
  first (PHASE-02), so later phases test through the real bin. Then where
  things are (PHASE-03), what the policy says (PHASE-04), which profile
  applies and what a write may touch (PHASE-05), and how the child runs and
  dies (PHASE-06). Each phase depends only on the ones before it:
  - `config.ts` feeds the policy and profile layers;
  - the policy's `profiles` map feeds the capability pin;
  - the `Form` union feeds the spawn branch.
- **Contracts come after the behaviour they describe, and before help
  (PHASE-07, then PHASE-08).** The drift tests can pin only final behaviour.
  Help prints the contracts verbatim, so the contracts must exist first. The
  RV-058 F-8 negative controls sit on PHASE-07 (EX-4, VT-2). That is the
  earliest phase that writes the drift tests and has the rig producing every
  state, which is what the finding's placement constraint asks for.
- **The publish gate and the nix package close out quotient (PHASE-09).**
  The host can then consume a tagged, packed artefact rather than a working
  tree.
- **Cutover is three phases, not one.** Each ends in a state the operator can
  stop in:
  - after PHASE-10, both routes work;
  - after PHASE-11, only quotient's works, from the local input;
  - after PHASE-12, from GitHub, and published.

  Rollback cost grows at each boundary. So each boundary has a live proof
  (RV-058 F-6, F-12) and an operator gate (VH rows, EN-2 entries).
- **The forms test moves to `test/flake/forms.test.ts`.** The depth matches
  the old path, so its `../../flake.nix` URL is unchanged. The new directory
  name says the test is about the flake, not the server. It moves in PHASE-10,
  where the `quotient-*` forms first exist, so the test is retargeted where it
  lands. Its `pi-mcp-*` assertions go in PHASE-11, with the forms they test.

## Notes

- **Outward acts are gated.** These need the operator's explicit go-ahead,
  each one separately:
  - the GitHub push (PHASE-12 EN-2);
  - the npm publish (PHASE-12 EX-4, after `npm whoami`);
  - writing the host policy (PHASE-10 EX-4, PHASE-11 EX-6).

  Commits in either repo wait for the operator's say.
- **Out-of-repo VT rows.** The quotient VT rows name absolute paths under
  `~/dev/quotient`. `doctrine slice verify-vt` reads them, failing "not found"
  until the files exist, so the gate is live, not waived.
- **Governance follow-through is `/reconcile`'s.** That is the design sec-7
  list: DEC-092/093/094/097/099/100, the ADR-017 ledger anchors, POL-001's
  candidate list, and the memories citing `pi/mcp`. It is not a phase.
- **Expected friction.**
  - `tsc --noEmit` in PHASE-01 may turn up type errors in code that has only
    ever been type-stripped. These are fixed in PHASE-01, not deferred, and
    no behaviour changes.
  - `buildNpmPackage`'s `npmDepsHash` will need one round of
    hash-from-failure in PHASE-09.
