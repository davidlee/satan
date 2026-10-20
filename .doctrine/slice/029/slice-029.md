# pi-agent MCP server: one blocking delegate call over stdio

## Context

Delegating work from an expensive driving model (claude) to a cheap pi agent
currently means a shell invocation and a wire log (IMP-046). The second half of
that problem is solved: `bin/pi-run-reduce` turns a pi event stream into a
budgeted transcript, `status.json` and one status line, and the spawn scripts now
report through it. The first half — a typed, discoverable delegate call — is this
slice.

Measured basis for the transport choice: `pi -p` and `pi --mode json` are the same
self-exiting one-shot; `pi --mode rpc` shuts down on stdin EOF (it answered
nothing when the prompt was piped and stdin closed), which is the only reason the
fifo keeper, tail poll and process-group reap in `scripts/lib/pi-reap.sh` exist.
See `mem.fact.harness.pi-transport`.

## Scope & Objectives

A stdio MCP server exposing one tool:

```
pi_agent(prompt, profile, cwd?, session?, tools?, ceilings?, transcript_budget_bytes?)
  → { schema, state, session, final, result, transcript, status, artifacts, refusal }
```

- `pi/mcp/` is the server; `bin/pi-mcp` is the node shim (interpreter swappable,
  as `bin/pi-run-reduce` is).
- Underneath: `pi --mode json`, prompt on the child's stdin, a backstop on the
  wall clock, a per-run dir holding `events.jsonl`, `transcript.md`, `status.json`
  and `audit.jsonl`. Process exit is completion — no fifo, no poll, no group kill.
- **Two postures, chosen by the operator** (DEC-100): a wrapper per call
  (default — many roots, one capability per profile) or a static launch-time jail
  around the server (one root, one capability, and the server's own writes
  confined too). The posture is never a per-call argument.
- **One operator-published policy artefact** (DEC-097) carries the postures,
  roots allowlist, ceilings, permitted profiles, wrapper forms and the enable
  switch. Absent or malformed refuses everything.
- `profile` is an identifier resolved only from the server's tracked profile
  directory, never a path and never from the call's cwd (DEC-092); a profile
  declares `filesystem: read | write` as a capability, and capability — not the
  tool list — selects the wrapped form (DEC-098).
- `session` maps to `--session-id`; it is minted and returned when absent, bound
  to (root, capability) on first use, and same-session calls are serialised by
  refusal (DEC-099).
- **Ceilings are owned by the server and enforced retrospectively** (DEC-090,
  amended by DEC-097): usage is counted from the event stream and a crossing
  aborts the run. There is no admission gate, and the design says so.
- The result carries the reducer's transcript (budgeted, soft) and the status
  record verbatim, with `final` distinguishing an answer from partial text
  (DEC-093). `artifacts` names the rest.
- The reducer is **imported, not shelled out**: one implementation serves the
  shell entry point and the server.

**Affected surface:** `pi/mcp/**`, `bin/pi-mcp`, `pi/reduce/reduce.ts` (one added
field), `flake.nix` (the wrapped forms and the static-mode derivation),
`justfile` (test hook).

**Verification intent.** TDD at the seams that can be tested offline: argv
construction, profile→tool resolution, jail refusal, exit/state mapping, result
shape — with `pi` stubbed on `PATH`. One live smoke run against deepseek-flash
recorded as evidence, not as a gate.

## Non-Goals

- **Static mode is designed but not built here.** DEC-100 keeps both postures as
  the design; the initial build ships per-call only. Rationale: the per-call
  overhead is negligible (measured: bwrap 3-4 ms, node ~16 ms, so the marginal
  cost is one pi process against model latency), while static mode adds a second
  policy shape, a second launcher derivation, and a security trade with nothing
  to buy that a per-call jail does not already give. Its convenience case is
  better served by cheap defaults (`default_profile`, launch-cwd as the default
  root) than by a posture that weakens evidence isolation. `sec-3`'s static half
  and DEC-100's second branch stand as the design of record if it is ever wanted.
- Mid-run steering or follow-ups. That is RPC's reason to exist and nothing here
  needs it.
- Job handles (`start`/`status`/`tail`). Revisit only if a real run outlives a
  driver's tool timeout.
- Retiring the shell wrappers (`scripts/pi-agent`, the spawn scripts), or
  migrating them off RPC — including deleting `scripts/lib/pi-reap.sh`.
- Porting the pi tooling upstream to doctrine, and reconciling the doctrine
  checkout's duplicate `scripts/` tree.
- Emacs/`satan-mcp` integration: this server must run without Emacs.

## Summary

One process, one tool, one blocking call; the answer, the evidence and the verdict
are the reducer's output. The risky part is not the protocol — it is the authority
the server hands out (tool allow-lists, ceilings, confinement), which the design
must place explicitly rather than inherit from a shell script.

## Risks, Assumptions, Open Questions

These are the live risks after RV-043. Historical claims the review defeated are
superseded by the design, not deleted: the record that we were wrong is worth
more than a clean page.

- **Root versus posture.** Settled by DEC-089 and DEC-100: per-call mode takes a
  root per call; static mode fixes one at launch and refuses a `cwd`
  (`cwd-not-supported`). Nothing is undecided here.
- **Nested confinement intersects authority.** A nested jail can narrow further
  (an inner `--ro-bind`, a masked path) and can never widen; authority the mount
  namespace does not govern — inherited fds, credentials, reachable sockets —
  survives it. So a nested jail proves less than it looks like it proves, and the
  outer profile remains the containing guarantee. *Superseded text:* an earlier
  note in this slice said nesting was "additive, never narrowing"; that was a
  transcription error, corrected in `mem.fact.jail.nesting-is-additive`.
- **Ceilings are retrospective.** DEC-097 with the operator-accepted F-4
  concession: a hard wall clock, checks at every usage-bearing event, abort on
  crossing or on unknown usage, and **no provider output cap**. Overshoot is
  bounded by observation latency plus one in-flight request. This is a recorded
  conformance gap against SPEC-001 REQ-004, not an undecided question.
- **Process groups.** The server creates each call's termination domain
  (`setsid`); the jail sets `no-new-session`, so no group exists otherwise. Killing
  `-pid` without that would be a no-op or would fell the server (DEC-096
  amendment).
- **Evidence isolation differs by posture.** Per-call mode can keep evidence out
  of every child bind; static mode cannot, in a single-uid jail (DEC-094
  amendment). The posture choice is therefore a security choice, not a
  convenience.
- **Authority placement.** ADR-017 §3: five `pi-mcp` rows plus one `satan-flake`
  execution-profile row (DEC-091), with row 5c worded as retrospective accounting
  and row 6c covering admission refusal *and* active halt.
- **Driver registration.** How a driver declares a stdio server (project config
  vs `claude mcp add`) remains a deployment question the plan must answer once.

## Follow-Ups

- **Static mode**, if per-call cost ever shows up in practice, or if a driver
  needs one jail for a whole session for a reason the design did not anticipate.
  The design is complete; only the build is deferred.
- **Convenience defaults**, on evidence rather than speculation: a policy
  `default_profile` (which must name a `filesystem: read` profile) and the
  launch-cwd as the default root. Both are plan-time decisions.
- Spawn-script transport migration (RPC → json) and the deletion of
  `lib/pi-reap.sh` plus `lib/pi-reap-test.sh` (that test is run by nothing and
  takes 94 s).
- The `pi-research` runner defect found while starting the research round: the
  `researcher` profile was absent from this repo, its model disagrees with
  `CLAUDE.md`, and outside the jail the `deepseek` provider key is invalid.

**Promoted to delivery (no longer a follow-up):** the wrapped forms. sec-3 and
sec-7 make the read-only and read-write launchers, and the static-mode derivation
that carries pi in its closure, part of this slice. They are declarations in
`flake.nix` using the existing `makeJailedAgent` API and combinators, not work in
the pinned `flakes/agents` input — an earlier note in this slice called them a
cross-repo dependency, which was wrong.

## Explicitly out of scope, not precluded

The same server should later serve a **non-pi agent behind the same MCP** — the
operator uses codex/GPT for architecture review, and the design goal is that a
different profile set and model can ride the same surface. Nothing in this
slice's contracts is satan-specific: the model and profile are already
parameters (DEC-092), confinement is the flake's (DEC-091/098), and the policy
artefact (DEC-097) names the wrapped forms rather than assuming pi. What does
*not* transfer is the wrapper and the model: the jails are portable, the profiles
and providers are not. Recorded so a later reader does not narrow the contracts
to pi by accident.
