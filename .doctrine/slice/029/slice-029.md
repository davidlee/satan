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

- **Per-call `cwd` versus a launch-time jail.** A jail is fixed when the wrapper
  starts, but `pi_agent` takes a `cwd`. Two shapes keep bwrap out of the server:
  the flake exposes a per-call launcher that receives the root, or the server runs
  inside one root fixed at launch and refuses a `cwd` outside it. Design chooses.
- **Nested confinement is settled, and it is additive.** An unjailed process in a
  jail is jailed; a jailed process in a jail gets the union of both. So a nested
  jail can never repair an outer profile's exposure — if the driver is
  `jailed-claude` with the eval socket bound, that still applies. The flake
  profile, not the server, is where this is fixed.
- **Authority placement.** ADR-017 §3 gives each authority item one owner
  (allow-list, ceiling, audit append, kill switch, permission profile). Research
  finds no "adds no authority" escape: the server needs new rows under a token
  such as `pi-mcp`, and the execution profile stays with `satan-flake`.
- **Driver registration.** How a driver declares a stdio server (project config
  file vs `claude mcp add`) is a deployment question the design should answer once.
- **Cost ceiling.** A delegate run spends money with no driver-visible cap: the
  backstop is time, not tokens. Decide whether a token/cost ceiling is in scope.

## Follow-Ups

- Spawn-script transport migration (RPC → json) and the deletion of
  `lib/pi-reap.sh` plus `lib/pi-reap-test.sh` (that test is run by nothing and
  takes 94 s).
- The wrapped-runner jail profile in `flakes/agents`, using the DEC-088 read-only
  directory bind rather than `jailEnvOptions` (which rw-binds the editor eval
  socket and reaches `~/notes`), plus its flake check.
- The `pi-research` runner defect found while starting the research round: the
  `researcher` profile was absent from this repo, its model disagrees with
  `CLAUDE.md`, and outside the jail the `deepseek` provider key is invalid.
- The harness jail machinery stays in `flakes/agents`; revisit only if the server
  needs a profile of its own there.

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
