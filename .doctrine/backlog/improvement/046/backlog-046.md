# IMP-046: pi-agent MCP server: JSON-mode one-shot runs with a reduced transcript as the result

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Why

Delegating work from an expensive or rate-limited driving model (claude) to a
cheap pi agent is the cheapest way to keep a session's context and juice for
judgement. Today the only way to do it is to shell out to
`scripts/pi-agent` (the `--print` arm, behind the `pi-scout` / `pi-research`
shims) or to `scripts/{spawn-confined,pi-review,pi-spawn,pi-respawn-nofork}`
(the `--mode rpc` arm). Two costs land on the driver:

1. **The interface is a shell invocation.** Quoting, argv limits, exit-code
   interpretation and "is it hung?" all become the driver's problem, and none
   of it is typed or discoverable.
2. **The output is a wire log, not a result.** An orchestrator cannot read a
   JSONL event stream, so the scripts `tail -40` it — the least useful 40 lines
   by construction.

The durable capability is a **standalone MCP server that runs pi agents and
answers with a reduced transcript**, so any MCP-speaking harness delegates with
one typed call. Deliberately *not* part of the doctrine framework: profiles,
jails and transports are harness concerns.

## Measured evidence (pi 0.99.1, deepseek-flash, 2026-10-20)

| Experiment | Result |
|---|---|
| `pi --mode json "…"` | 66 records, exits 0 itself, last record `agent_settled` |
| `pi --mode rpc`, prompt piped, stdin then closed | exits 0 having answered **nothing** — EOF requests shutdown |
| `pi --mode rpc`, fifo-held stdin, same turn | 187 KB (json mode: 175 KB) |
| One small turn's 175 KB, by record | context echo 125 KB (**72 %**), stream deltas 37 KB, tool/turn payload ≈ 7 KB |
| `pi -p --session-id X` twice, separate processes | second turn recalled content from the first |
| `kill -TERM` on the `timeout` wrapper, json arm | whole chain dead in 6 ms, no survivors |
| trivial one-shot turn, wall clock | ≈ 1.0 s |

Inference from the above: `-p` and `--mode json` are the *same* one-shot
lifecycle (self-exiting; the only differences are output encoding and exit-code
honesty). `--mode rpc` is a different, long-lived lifecycle, and every piece of
`scripts/lib/pi-reap.sh` — fifo keeper, tail-window poll, process-group kill,
zombie waits, `pid <= 1` guards — exists to fit a one-shot into it. `--mode json`
removes that need: process exit *is* completion. The verbosity is a presentation
problem (a reducer), not a transport problem.

The reducer is verifiably a few lines of `jq`:

```jq
if .type=="tool_execution_start" then "→ \(.toolName)"
elif .type=="message_end" and .message.role=="assistant"
then (.message.content[]?|select(.type=="text")|.text)
else empty end
```

plus a second pass for status (`agent_settled` present; assistant `stopReason`)
and usage/cost from `agent_end`.

## Provisional shape (to be designed)

- **MCP server**, standalone process (not Emacs-hosted, unlike `satan-mcp`):
  `pi_agent(profile, prompt, cwd, tools?, jail?, backstop?)` → result.
- **Transport underneath**: `pi --mode json` one-shot, prompt by file or stdin,
  `timeout` as the sole backstop, confinement via the existing bwrap jail.
- **Result surface**: reduced transcript inline (bounded), full artefacts on
  disk (`events.jsonl`, `transcript.md`, `status.json`) with their paths
  returned; usage/cost and exit reason in the result.
- **Run dir** per invocation, so a delegated run is resumable
  (`--session-id`), inspectable, and greppable after the fact.

## Decisions (2026-10-20)

- **One-shot transport: `--mode json`.** Not RPC. The measured facts and the
  consequences are recorded in `mem.fact.harness.pi-transport`; the short form is
  that RPC shuts down on stdin EOF, so a one-shot inside RPC needs a fifo keeper,
  a tail poll and a process-group kill, and json mode needs none of it.
- **The result is a reduced transcript, not a wire log.** The audience is an
  agent; a human never reads it by default.
- **Quiet by default, alertable on request.** One status line on stdout; the only
  unprompted output is `--alert RE` matches, on stderr, because the caller
  declared them.
- **TS, run by `node`** (v24 strips types — no build step, no bun-specific API,
  so the interpreter is swappable and a Rust port stays open). `bun` works too and
  is not depended on.
- **Layout:** `pi/` for pi-harness tooling, alongside `satan/` (the Emacs app) and
  `noctalia/` (the shell plugin). The MCP server lands in `pi/mcp/` when it comes.
- **Home: this repo.** SATAN owns `scripts/` (it was copied from doctrine once-off;
  porting upstream is a future concern, not a dependency) and owns the server.
  The harness jail machinery stays in `flakes/agents` (`inputs.agents`).
- **Transport: stdio.** Zero lifecycle, per-client, and it cannot reproduce the
  dead-socket class ISS-042 documents. No shared listener, no socket dir in the
  jail policy.
- **One blocking tool call.** No `start`/`status`/`tail` handles: the reducer's
  budget bounds the result, and the driver's own tool timeout is the ceiling. A
  job-handle protocol is more state and more code for a need nobody has shown.

## First increment: landed

`bin/pi-run-reduce` → `pi/reduce/{reduce,cli}.ts`, tested by `just test`
(`node --test pi/reduce/*.test.ts`, 15 behaviour tests).

```
events.jsonl ──▶ pi-run-reduce ──┬─▶ transcript.md   budgeted (8 KB), middle-out elision
                                 ├─▶ status.json     state/turns/tools/tokens/cost/model/session
                                 ├─▶ stdout: 1 line  completed turns=3 tools=2 tokens=9343/192 cost=0.0032 transcript=…
                                 └─▶ stderr: alerts  alert <pattern> :: <match ±40 chars context>
```

Rules it enforces: final answer always present and always last; assistant prose
verbatim; thinking and context echo dropped; one line per tool call, first line
per result, `[exit N]` tagged when non-zero; identical repeated call+result pairs
fold to `×N` on the action; alerts match untruncated text so neither the snippet
clip nor the budget can hide one; a budget too small for the mandatory sections
reports the honest byte count rather than pretending.

Measured: a real 175 KB turn reduces to 551 B of transcript (0.3 %); a 260 KB
tool-heavy turn to ~900 B plus the alert lines it was asked for.

## Wired in: spawn reports use the reducer

`scripts/lib/pi-report.sh` — `pi_report <stream> [tag]`, sourced by
`spawn-confined.sh`, `pi-spawn.sh` and `pi-respawn-nofork.sh` in place of their
`tail -40`. One helper, not three copies (the lesson `lib/pi-reap.sh` records:
four copies is how CHR-051 got fixed in two of them).

- Artefacts go to a temp dir, never under the worker's worktree — untracked files
  there would land in the delta the orchestrator imports.
- Degrades to the old tail, loudly, when the reducer or node is unavailable (a
  jail without node): a noisy report beats a silent one.
- `PI_ALERTS` (space-separated regexes) is the caller's warning channel.
- `spawn-confined.sh` calls it on the pi arm only: the claude arm emits a
  different event schema.

This does **not** migrate the transport. The RPC arm still runs its fifo/poll/reap;
its stream reduces the same way (one malformed line tolerated where `2>&1` mixes
worker stderr in), so the migration can land later without touching the report.

## Open questions

- **Do the shell wrappers retire behind the server?** They stay until the server
  has replaced them in real use; the reducer is shared either way.
- **Job handles** — deferred, not rejected. Revisit if a real run outlives a
  driver's tool timeout.

## Governance notes

A new spawn surface that can run agents with tool access is a trust-boundary
surface: ADR-017 §3 requires each authority item (allowlist, ceilings, audit
append, kill switch, permission profile) to have exactly one owner, and POL-001
gates new module seats. Design must state where these sit rather than inherit
them implicitly from `scripts/spawn-confined.sh`.

## Neighbours

- `scripts/pi-agent` — the print arm; the profile resolution and error handling
  to reuse.
- ISS-042, IMP-039 — the existing MCP socket lifecycle and tool-list surface.
- IDE-008 — malebolge on pi-env: the other "pi agents somewhere else" idea.
