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

**The result envelope lands in PHASE-02, not PHASE-08.** An earlier draft kept
the refusal payload provisional and introduced `pi-agent-result/1` at the end —
which would have left five phases returning an undefined payload and made
PHASE-08 rewire the returns of four suites. The envelope is a data contract, not
runtime machinery, so a refusal carries the real shape from the first phase that
answers a call; PHASE-08 then owns only what needs a run to exist — state, cause
precedence, the latch, the success predicate.

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

The same reasoning places the blocker's **hostile fixture** in PHASE-09 rather
than PHASE-06. With a stub launcher there is no jail, so "the child cannot reach
the audit" is false by construction and "the run fails closed" is false by the
review's own measurement — truncate-then-append succeeds silently. PHASE-06
proves what is provable without a jail (the child inherits no fd, env var or
argv member naming the evidence) and PHASE-09 proves unreachability under the
real form, with a fallback to a human run if no jail is available. Putting the
fixture in PHASE-06 would have produced a criterion that can only be waived or
faked, and the slice's one blocker would have lost its only execution proof.

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
| RV-043 F-1 (blocker) | 05, 06, 09 | alias-case refusal before spawn; non-exposure of the evidence to the child; the hostile truncation fixture under the real form |
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

**Research advisory — drift checked, then restamped with its scope stated.**
`doctrine slice research 29` reported the baseline drifted: `slice-029.md`
changed and `design.md` was added after the research round. Both are expected —
research precedes the synthesised scope and the design. Every research claim the
plan leans on was re-checked against the current tree (below) and the baseline is
restamped with the split recorded in `research.md` itself: Thread 2's hotspots and
cited facts re-verified, Threads 3–4 (user-conveyed) and the naming precedents
carried as-is. Left un-restamped, the advisory fires for every later reader and
nothing distinguishes "checked" from "stale".

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
result (PHASE-08 EX-8). It is listed again among the REV candidates below, because
a reading recorded only in a plan is weaker than one recorded in the design.

**The module split is named, not left open.** Each phase owns one file under
`pi/mcp/`: `server.ts`, `policy.ts`, `profiles.ts`, `session.ts`, `childview.ts`,
`evidence.ts`, `spawn.ts`, `gate.ts`, `result.ts`, with `main.ts` as the entry
point. The VT mandates pin those files so the gate has a real target; a phase may
extract further modules *behind* its named file, but it may not move the file the
plan told the next phase to import. An earlier draft called the split
unspecified while the VT rows nevertheless pinned it — one of the two had to go.

**Known risk carried, not solved.** The reducer's accounting is exact only for
sends the parent stream sees; PHASE-07 discloses the residual and asserts the
absence of a nested figure rather than its zero. If a later phase finds the
stream cannot distinguish a retry from a fresh send, that is a `/consult`
moment — the arithmetic is the ceiling's input, and guessing it would be worse
than stopping.

## Plan-time decisions the slice owed

`slice-029.md` leaves two items for the plan to answer, and a review of this plan
found them unanswered:

- **Driver registration** ("a deployment question the plan must answer once").
  Answer: this slice does **not** build a registration helper. It delivers
  `bin/pi-mcp` plus the launch-environment contract (PHASE-02 EX-10: policy path,
  run dir, session home, all absolute, refusing when unset), and registration —
  project config versus `claude mcp add` — stays the operator's act. The reason
  is the posture: a per-call server has no launch-time state to register beyond
  its environment, so a helper would encode a deployment convention this repo
  does not own.
- **Convenience defaults** ("both are plan-time decisions"). Answer, on the
  evidence the design already fixes rather than on speculation:
  - `default_profile`: **not adopted.** Design §2 makes `profile` required, and a
    default would be a policy-supplied answer to "who is this delegate" — the one
    question the caller should have to answer. If it is ever added it must name a
    `filesystem: read` profile, as the follow-up says.
  - launch-cwd as default root: **adopted, with no special case.** An absent
    `cwd` resolves to the server's own launch directory, canonicalised and put
    through the same allowlist check as any supplied root — so an operator who
    has not allowlisted it gets `root-not-allowlisted`, not a quiet exemption.
    This keeps the root decision in the policy rather than in the caller.

## Wire contract additions, settled at plan time (DEC-103)

Three things the phasing work needs that the locked design does not name. The
operator chose to settle them here and fold them back through a reconcile-time
REV rather than reopen a design whose lock conditions are section attestations
plus a review disposition plus design acceptance. `DEC-103` is the record; the
plan cites its tokens.

1. **`tools-not-allowed`** — design §2 says `tools` "may only narrow" and supplies
   no token for a widening attempt. A request naming a tool outside the profile's
   snapshotted set is refused at validation, before the session step, with a detail
   naming the offending tool (PHASE-03 EX-10). The effective set is the
   intersection, and `--tools` receives the whole narrowed list because pi's flag
   replaces the selection.
2. **`request-invalid`** — §5 forbids JSON-RPC errors and §2's token list has
   nothing for a bad params object, a missing `prompt` or `profile`, or an unknown
   key. The refusal carries a detail naming the field and `session: null`
   (PHASE-02 EX-2, PHASE-08 EX-3).
3. **Cancellation** — `cancelled` is in both §5 enums and §4 says a blocking
   result never blocks cancellation, but no mechanism was named.
   `notifications/cancelled{requestId}` aborts exactly that call through the one
   ladder and reports `state: cancelled`; an id naming no in-flight call is
   ignored. stdin EOF is a different act: the client is gone, so admission stops,
   in-flight runs are aborted the same way, the audit is flushed and the server
   exits without attempting to deliver (PHASE-06 EX-10/EX-11).

Further **reconcile-time REV candidates**, recorded so an auditor reads them as
accounted-for rather than as drift:

- `final` is derived in the server, not the reducer — restating the reading above
  as a design-record correction.
- §5's reconciliation sentence still names `backstop` among stream-external
  causes while its enum and the timeout rows say `timeout` — the residue of
  RV-046 F-6's repair.
- §5 says `session` is "always present"; a refusal mints none, so a refused result
  carries `session: null`.
- `pi-run-status/1` gains fields in PHASE-01, so the id advances to
  `pi-run-status/2` and the status-line consumers are re-checked.
