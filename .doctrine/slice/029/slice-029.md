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
pi_agent(prompt, cwd?, profile?, session?, tools?, jail?, backstop_s?)
  → { state, result, transcript, status, transcript_path }
```

- `pi/mcp/` is the server; `bin/pi-mcp` is the node shim (interpreter swappable,
  as `bin/pi-run-reduce` is).
- Underneath: `pi --mode json`, prompt supplied by file, `timeout` as the sole
  backstop, a per-run dir holding `events.jsonl`, `transcript.md` and
  `status.json`. Process exit is completion — no fifo, no poll, no group kill.
- `profile` names an agent profile (model + tool set, as `scripts/pi-agent`
  resolves them). **Read-only by default**: write/edit tools are reachable only by
  naming a profile that declares them, so write access is never ambient.
- `session` maps to `--session-id`, so a delegate conversation continues across
  calls without a long-lived process.
- `jail` is **not** a bwrap switch in the server. Jail policy is project-specific
  and lives in the flake, which wraps execution and exposes a wrapped form
  (`jailed-pi`, `jailed-claude`); the server execs a wrapped runner and holds no
  bwrap argv of its own. Consequence for the ledger: the execution/jail-profile
  row belongs to `satan-flake` (the row-3b precedent), while the server owns
  request schema validation, profile→tools, audit, ceiling and kill switch.
- The result carries the reducer's transcript (budgeted) and the status record
  verbatim; `transcript_path` names the artefacts for the rest.
- The reducer is **imported, not shelled out**: one implementation serves the
  shell entry point and the server.

**Affected surface:** `pi/mcp/**`, `bin/pi-mcp`, `pi/reduce/**` (import only),
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
