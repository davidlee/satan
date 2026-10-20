# Implementation Plan SL-029: pi-agent MCP server: one blocking delegate call over stdio

Prose companion to `plan.toml`. Narrative only — no queried data lives here
(the storage rule); the phase list, criteria, verification, and links are
authored in the TOML. Use this for the plan's rationale and sequencing.
<!-- Reference forms: `lib:reference/glossary.md` § reference forms. -->

## Overview

Nine phases, each one mechanism, in dependency order:

1. `pi/reduce` gains the single usage accumulator and the answer fields.
2. The server exists and refuses: wire loop, policy artefact, posture, enable gate.
3. Profiles become frozen authority; root, capability and ceiling validation.
4. Sessions: cross-process ownership, binding, reclamation.
5. Child-view disjointness and the evidence store layout.
6. Spawn: launcher argv, the per-call termination domain, evidence capture.
7. The gate: ceilings, switch, policy re-read, usage sanity.
8. The result: state, causes, precedence, schema conformance.
9. The flake's two wrapped forms and one live smoke. (The offline test hook lands
   in PHASE-02, not here — see below.)

The build is per-call only (design §1, DEC-100 build status). Static mode stays
as design of record and is refused at validation step 1 — a phase that built it
would be building something the slice does not ship.

## Sequencing & Rationale

**The reducer goes first, and everything downstream reads it.** The server
embeds `status` verbatim, so two accounting paths would be two truths
(RV-043 F-6). Landing the accumulator before the gate means the gate has nothing
to invent: it consumes fields that already exist and are already tested against
the three verified event traces. It also keeps PHASE-01 genuinely offline and
cheap — `node --test pi/reduce/*.test.ts`, no Postgres, no spawn.

**Refusal before spawning.** PHASE-02–05 build the whole admission path with no
child process anywhere: wire, policy, profiles, roots, ceilings, sessions,
child-view. That ordering is what makes the refusal contract testable at all —
every token in design §2 is asserted before there is a run to fail in, and the
two pre-spawn demonstrations (RV-046 F-1 posture, RV-043 F-1's alias case) land
where they can actually be proven. It also front-loads the security boundary:
the phases that decide *whether* anything runs are done before the phase that
decides *how*.

**Sessions before spawn, not after.** Session ownership is validation step 7 and
is cross-process by construction (one stdio server per client). Building it after
the spawn machinery would tempt an in-memory busy map that passes a
single-process test and still lets two servers write one session. The lock
release ordering (release last, after reap and drain) belongs to PHASE-06
because it is only observable once there is a child to clean up.

**Child-view before spawn for the same reason.** The disjointness check is a
refusal, so it must exist before anything can spawn; its second half — the
hostile-bash truncation fixture — can only be tested once PHASE-06 exists, and
is placed there. The blocker (RV-043 F-1) is therefore carried by two phases:
PHASE-05 proves the refusal, PHASE-06 proves the evidence survives an attacker
who is already inside.

**Gate before result.** The gate produces causes; the result assembles them. The
latch and the commit point are meaningless until there is something to latch, so
the result phase follows the enforcement phase and consumes recorded fixtures
rather than live runs.

**The flake forms come late, and deliberately.** The two per-call wrapped forms
are the only real confinement, but every earlier phase tests against a stub
launcher with `pi` stubbed on `PATH`. Deferring the flake keeps eight phases
offline and fast; the form's bind set is then asserted against the policy's
`child_binds` — the closure RV-043 F-1 demanded, because a bind the flake adds
and the policy omits is outside the server's knowledge entirely.

**The live smoke is last and is not a gate.** Design §7 says so: one run against
deepseek-flash, recorded as evidence. It needs the real form, a real profile and
a real gateway, so it cannot move earlier, and making it a gate would make the
suite depend on a provider.

**The justfile hook lands early (PHASE-02), not with the flake.** `just test` is
gated behind test databases, so leaving the pi suite outside `just check` would
mean eight phases whose green light excludes their own tests. The hook is two
lines and belongs to the phase that creates the second test file; the flake's
forms still come last because they are the only part that needs `nix`.

## Notes

**Routed design-review findings are transcribed, not merely cited.** Ten findings
carry `route = demonstrate`; each is an obligation deliberately not repaired in
prose. Their placement, per the constraint recorded in each response:

| finding | phase | obligation |
|---|---|---|
| RV-043 F-1 (blocker) | 05, 06 | alias-case refusal before spawn; hostile truncation fixture after |
| RV-043 F-6 | 01, 07 | counting arithmetic with the verified traces; gate inputs == returned status |
| RV-043 F-7 | 06 | argv exactness: no executable word, no `--`, conditional `-e builtin:mcp` |
| RV-043 F-9 | 06 | per-call process group, concurrent calls, subtree gone after the grace |
| RV-046 F-1 | 02 | `posture-unsupported` before spawn, no downgrade, no bare-agent path |
| RV-046 F-2 | 07 | policy unreadable/malformed mid-run aborts fail-closed |
| RV-046 F-3 | 04 | two servers, stale-lock race, orphan claim, fail-closed liveness |
| RV-046 F-4 | 07 | nested spend not attributed and not claimed |
| RV-046 F-5 | 03 | start-up profile snapshot survives an in-call mutation |
| RV-046 F-6 | 08 | one cause vocabulary; every mapped outcome satisfies the schema |

F-1 remains `answered`, not `verified`, and it refuses audit→reconcile while
unresolved: the plan gives it teeth in PHASE-05/06 and leaves the ledger status
alone. Nothing here verifies it; the phase criteria do.

**Research advisory — drift, checked rather than restamped.** `doctrine slice
research 29` reports the baseline drifted: `slice-029.md` changed and `design.md`
was added after the research round. Both are expected — research precedes the
synthesised scope and the design — and every research claim the plan leans on was
re-checked against the current tree (see below). Restamping now would record
freshness the artefact has not re-earned, so the advisory is left standing and
the drift is named here instead.

**Selectors unchanged.** The slice's selectors already cover the design's
affected surface (`pi/**`, `pi/mcp/**`, `pi/reduce/**`, `pi/reduce/reduce.ts`,
`bin/pi-mcp`, `flake.nix`, `justfile`). The research hotspot map adds no file the
design changes: `scripts/pi-review.sh`, `scripts/spawn-confined.sh`,
`scripts/pi-agent` and `satan/satan-mcp.el` are read-only precedents, and adding
them as selectors would make review staleness churn on files this slice never
touches.

**Design premises re-grepped (plan skill step 2).** All concrete references
resolve; two anchor line-numbers drifted and nothing else moved:

- `pi/reduce/reduce.ts` — `absorb`/`totalCost` are at 116–117 (the review cited
  109–112); the compaction blind spot and the zero-cost default are still present
  as described. No `result` field on `Reduced`, as the research found.
- `/workspace/flakes/agents/jailed-agents.nix` — `no-new-session` is at line 193
  (design says 184). The premise stands: the jail creates no session, so the
  server must.
- Unchanged and confirmed: `bin/pi-run-reduce` exists; `pi/reduce/{reduce,cli}.ts`
  and `reduce.test.ts` exist; there is no `package.json`/`tsconfig.json` (no
  TypeScript dependency mechanism); `justfile:60` runs `node --test
  pi/reduce/*.test.ts` under the DB-gated `just test`; `flake.nix` has
  `jailProbes` and `workspaceDeps` and no pi-mcp forms yet; pi 0.99.1 is
  installed with its docs.

**A design reading the plan makes explicit: `final` is derived in one place.**
Design §7 lists `final` among the reducer's new fields, but §5 defines it as
requiring `agent_settled` **and** exit status 0 **and** known accounting — and the
reducer never sees the child's exit. Computing `final` in both places would be
two truths about the same call, the exact defect RV-043 F-6 raised about spend.
The plan therefore puts `result`, `terminalReason`, `settled` and the
accounting-known signal in the reducer (PHASE-01) and `final` in the server's
result (PHASE-08 EX-8), which is the only place the predicate's inputs exist.
Flagged here so an auditor can contest the reading rather than discover it.

**deliberately under-specified (and why).** Two things are left to the phase
that implements them rather than being pre-decided here: the module split inside
`pi/mcp/` (the design names `pi/mcp/*.ts`; the plan names the file each phase
owns, and a phase may split further if a module earns it), and the exact wire
encoding details of `initialize` (the research names `satan/satan-mcp.el:230-331`
as the precedent, and matching it is the phase's job).

**Known risk carried, not solved.** The reducer's accounting is exact only for
sends the parent stream sees; PHASE-07 discloses the residual and asserts the
absence of a nested figure rather than its zero. If a later phase finds the
stream cannot distinguish a retry from a fresh send, that is a `/consult`
moment — the arithmetic is the ceiling's input, and guessing it would be worse
than stopping.
