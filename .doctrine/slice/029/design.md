<!-- doctrine:section sec-1 -->
# Overview and postures

`pi/mcp/` is a stdio MCP server exposing one tool, `pi_agent`, which runs a single one-shot pi agent and answers with a reduced transcript. It imports `pi/reduce` (no shell-out) and is launched by `bin/pi-mcp`, a bash shim that execs `node` on the TypeScript entry point — the same no-build-step shape as `bin/pi-run-reduce`.

## Two postures (DEC-100)

| posture | confinement | roots | capabilities |
|---|---|---|---|
| `per-call` (default) | a flake-provided wrapped runner launched once per call, cwd = the call's root | many, from the allowlist | one per profile (`read` / `write`) |
| `static` | the server *is* the jailed process; children inherit | one, fixed at launch | one, fixed at launch |

The posture is an operator declaration in the policy artefact, fixed for the process lifetime. It is never a per-call argument: a caller must not choose its own confinement.

## One policy artefact (DEC-097)

A single read-only file, operator-published, carries: `mode`, `roots`, `maxima`, `profiles`, the wrapper forms (or `agent` in static mode), `enabled`, `transcript_budget_bytes`. Read once per call so a change applies to the next call; an in-flight run keeps its snapshot, and the audit records the policy digest. Absent or malformed refuses everything: a delegate with no ceiling is unbounded spend.

## What it is not

The server is not an MCP *proxy*: it does not forward tools, hold sessions open, or steer runs. One call is one process. Results are MCP tool results (`content` + `isError`), never JSON-RPC errors — a failed run is a successful call.
<!-- doctrine:section sec-2 -->
# Request contract

```
pi_agent(prompt, profile, cwd?, session?, tools?, ceilings?, transcript_budget_bytes?)
```

`prompt` and `profile` are required. `tools` may only narrow the profile's set. `ceilings` may only lower the policy maxima.

## Validation order (fail closed, first failure wins)

1. **policy** — absent or malformed → `policy-unavailable` / `policy-invalid`.
2. **enabled** — `enabled = false` → `disabled`.
3. **profile** — must match `^[a-z][a-z0-9-]{0,31}$` and exist in the server's tracked profile directory (DEC-092); it must be listed in the policy → `profile-invalid` / `profile-unknown` / `profile-not-allowed`.
4. **root** — canonicalised, existing directory, inside the allowlist by path components (DEC-095) → `root-missing`, `root-not-a-directory`, `root-not-allowlisted`. Static mode: a `cwd` other than the declared root → `cwd-not-supported`.
5. **capability** — the profile's `filesystem` must match the posture: per-call, the required wrapper form must exist → `wrapper-unavailable`; static, the jail's mode must agree → `capability-mismatch`.
6. **ceilings** — clamped to the maxima; a ceiling above a maximum is a refusal, not a silent clamp → `ceiling-above-maximum`.
7. **session** — grammar, then binding to (root, capability), then liveness → `session-invalid`, `session-root-mismatch`, `session-capability-mismatch`, `session-busy`.

The refusals are the contract: each is a stable token plus a `detail` string, and each is audited (`refuse`). A caller never receives a silent downgrade.
<!-- doctrine:section sec-3 -->
# Confinement contract

Jail policy lives in the flake and is exposed as a wrapped form; the server holds no bwrap argv (DEC-098/100, SPEC-001 REQ-009). The flake is the only place a bind is decided.

## Per-call mode

Two forms are declared, one per capability. Each binds:

- the launch dir as the root — `--ro-bind` for read, `--bind` for write. `mountLaunchDir` alone will not do: its true branch is a rw `--bind` and a profile does not change it (`mem.fact.jail.profile-is-not-readonly`).
- `~/.pi` (pi writes session and settings state there) and `--tmpfs /tmp`.
- **the active session directory only** — `<PI_MCP_SESSION_HOME>/<session-id>/`, via raw args with run-time paths (`mem.fact.jail.runtime-path-bind`). Not the session home, and never the run directory: the child's writable set is exactly what it needs to continue its own conversation.

The server-owned evidence directory (events, stderr, transcript, status, audit) is bound into no child.

## Static mode — designed, not in the initial build

(DEC-100 build-status note: the shape below stands as the design of record; the
initial build ships per-call only. Read it as a specification, not a deliverable.)

`makeJailedAgent { agent = pi-mcp; profile = … }`; the launch jail is the whole confinement. The policy restates what the jail decided — `root`, `filesystem`, `agent`, `session_home`, `run_dir`, `evidence_dir` — and the server validates at start-up that its own dirs are writable (`bind-unavailable`).

**The residual, stated:** in a single-uid jail the child shares the server's writable view, so it can reach the evidence the server writes. Static mode therefore (a) buffers evidence in memory and flushes it after the child exits, and (b) permits a single declared session, which is also the only session the child can reach. It does not claim per-child evidence isolation; per-call mode is the posture that provides it. A policy naming both wrapper forms and `agent` is `policy-invalid`.

## Executable contract (both postures)

The launcher has the executable baked in and forwards arguments to it: `<launcher> --mode json …`, with no executable word and no `--` (DEC-098 amendment). Static mode names `agent` and requires pi plus its provider configuration in the launch closure and `PATH`; a launcher probe asserts reachability, because the flake's `piInJail` is false when the agent is the server.

<!-- doctrine:section sec-4 -->
# Execution, the stream gate and termination

## Spawn

The child is spawned as a **process-group leader** (its own session), so the ladder can signal `-pid` without reaching the server or a concurrent call — the jail sets `no-new-session` (`jailed-agents.nix:184`), so no group exists unless the server creates it. cwd is the root; the prompt goes to the child's stdin through a pipe the server closes; stdout is captured by the server into its **own evidence directory** (a path no child can open); stderr goes to a separate file. Never `2>&1`: stdout is JSONL only.

`--no-extensions` is load-bearing (ISS-052). `--tools` replaces the selection. Lifetimes are coupled — the child is never backgrounded — but the group is independent, and those are different things (DEC-096 amendment).

## Gate

One reader parses each event (LF framing, no `readline`) and maintains a **single usage accumulator** fed by `message_end`, `compaction_end` and retry attempts; a compaction triggers a gate check. At every tick (each such event, plus an idle poll bounded to about a second) it evaluates:

- ceilings — requests, tokens, cost, against the clamped maxima;
- the wall clock — the hard backstop;
- the **switch** — `enabled` re-read at the tick, so a flip halts an in-flight run through the ladder, audited `abort(switch)`, with no driver cooperation (DEC-097 amendment);
- usage sanity — absent or unpriced usage aborts as `accounting_unknown`; missing data is never headroom.

The gate is **retrospective**: it aborts a crossing, it does not prevent the next request, and there is no provider output cap (DEC-097; operator-accepted conformance concession). Overshoot is bounded by observation latency plus one in-flight request's spend. The same accumulator produces the returned status, so enforcement and reporting cannot disagree (DEC-093 amendment).

## Termination

One ladder for every trigger: SIGTERM to the group, 2 s grace, SIGKILL to the group, then reap and drain the stream, then audit, then return. The result and the session-lock release happen only after cleanup. Concurrently the MCP loop reads its own stdin: a blocking result never blocks cancellation.

<!-- doctrine:section sec-5 -->
# Result contract

```json
{
  "schema": "pi-agent-result/1",
  "state": "completed|failed|incomplete|timeout|cancelled|ceiling_exceeded|accounting_unknown|audit_failed|refused",
  "termination": "stop|length|error|aborted|backstop|cancelled|switch|ceiling|accounting|audit|refused",
  "session": "<id>",
  "final": true,
  "truncated": false,
  "result": "<answer>" | null,
  "transcript": "<markdown>",
  "status": { ...pi-run-status/1... } | null,
  "artifacts": { "dir": "…", "events": "…", "transcript": "…", "status": "…", "audit": "…" } | null,
  "refusal": { "reason": "…", "detail": "…" }
}
```

## Answer semantics

`result` is the **terminal assistant message** — the last assistant `message_end` with a terminal stop reason and no later assistant message — with all of its text blocks joined. `final` is true only for `stop`; `length` is `final: true, truncated: true`; `error`, `aborted`, `toolUse`, `deferred` and every server-caused stop give `final: false, result: null`. A backwards search for the last prose block is expressly not the rule (DEC-093 amendment).

`session` is always present — minted and returned when the caller supplied none.

`transcript` is budgeted and the budget is **soft**: mandatory sections can exceed it, by design and by test. The unbudgeted text is at `artifacts.transcript`.

## Cause, state and precedence

The table in DEC-093 is normative: each non-completed cause names its state, and every one carries `termination`. The **earliest** cause wins, and a cause discovered after the child has settled still decides — the run cannot claim success when the reason it stopped was audit or accounting failure. Exit 0 is never evidence of success (json mode exits 0 on a model error).

`refused` carries `status`, `artifacts`, `result` all null and a `refusal { reason, detail }`: nothing ran.

## Artefacts

One directory per run under `PI_MCP_RUN_DIR`, never inside the root and never bound into a child: `events.jsonl`, `stderr.log`, `transcript.md`, `status.json`, `audit.jsonl`. Pre-spawn refusals have no run directory and are recorded in the server-level `attempts.jsonl` (sec-6).

<!-- doctrine:section sec-6 -->
# Session and audit contracts

## Sessions (DEC-099, amended)

- Minted when absent and returned; grammar alnum at both ends, 1–64 characters — the grammar pi itself accepts.
- Bound on first use to (canonical root, filesystem capability); resuming otherwise is refused.
- Same-session concurrency is refused (`session-busy`), not queued.
- The child sees **one** directory: `<PI_MCP_SESSION_HOME>/<session-id>/`. Binding and lock metadata are server-side, outside every bind. A session id is a bearer capability within the policy's trust domain and the design says so without pretending to authenticate callers.
- In static mode the home is bound at launch, so the policy declares a single session, and the reachability of other sessions is stated as that posture's known limit.

## Evidence (DEC-094, amended)

Two sinks, both server-owned and outside every child bind:

- `attempts.jsonl` — server-level, one line per attempt that spawned nothing: policy unavailable/invalid, disabled, profile, root, capability, ceiling, session refusals. Policy digest recorded when one was readable; no run directory required.
- `<run>/audit.jsonl` — control decisions for a spawned run: `spawn`, `abort` (with usage at the gate and the cause), `timeout`, `exit`, `switch`, each with the policy digest.

Enacted actions are covered by `<run>/events.jsonl` beside it. Control decisions and enacted actions together are the audit (SPEC-001 REQ-003); neither is claimed alone.

**Failure policy.** If `attempts.jsonl` cannot be written, the refusal is returned in-band and on stderr and the server does not spawn. If a run's audit append fails before spawn, the call is refused `audit_failed`; mid-run, the run is aborted through the ladder and reported `audit_failed`. Static mode buffers evidence in memory and flushes after exit, so a co-resident child could still write the evidence directory: that is the posture's stated residual, not an assurance.

<!-- doctrine:section sec-7 -->
# Delivery, authority and verification

## Files

```
pi/mcp/*.ts                      server, policy load, profiles, wrapper forms, gate, accounting, result, stdio loop
pi/mcp/profiles/*.md             tracked profile documents (filesystem capability + model + tools)
pi/mcp/*.test.ts                 node --test, offline
bin/pi-mcp                       shim → node pi/mcp/main.ts
pi/reduce/reduce.ts              + result, final, terminalReason; one usage accumulator incl. compaction_end
flake.nix                        two per-call wrapped forms (the static-mode derivation is deferred)
justfile                         node --test pi/mcp/*.test.ts
```

The reducer change is one accumulator and three fields: the server embeds its status verbatim, so a second accounting path would be a second truth (DEC-093 amendment).

## Authority (DEC-091)

Five `pi-mcp` rows — request schema validation (1b), profile→tool allowlist (2b), delegate audit (4c), delegate ceilings (5c, described as retrospective accounting with best-effort termination), delegate kill switch (6c, admission refusal *and* active halt) — and one `satan-flake` row for the execution profiles (3c). Ledger edits land at reconcile via REV.

## Verification

Offline, with a stub launcher and a stub pi:

- validation order and every refusal token; argv exactness (no executable word, no `--`); capability→form selection; that no bwrap token appears anywhere in `pi/mcp`;
- accounting: compaction included, unknown/unpriced usage aborts, returned status equals the gate's inputs;
- result: error+settled, textless terminal message, multi-block terminal message, stale planning prose, `length` truncation;
- precendence: concurrent causes, and a failure after `agent_settled`;
- evidence isolation: a hostile bash attempting truncate/unlink/replace of the audit from inside the child, in both postures — refusal-with-intact-evidence or a fail-closed `audit_failed`, never a clean success;
- lifecycle: two concurrent calls plus a grandchild ignoring SIGTERM; cancel one, assert its subtree is gone after the grace, the other call and the server survive, and the session lock releases only after cleanup; a mid-run switch flip aborts;
- sessions: minting and return, binding mismatches, busy refusal, grammar edges including a valid single character and trailing `.` `_` `-`.

One live smoke run per posture against deepseek-flash, recorded as evidence, not a gate. Flake checks: each wrapped form's argv and the static launcher's closure (`jailProbes` pattern); `just check` carries the suite.

## Out of scope, not precluded

A non-pi agent behind the same MCP (the operator's codex/GPT review use case); steering and follow-ups; job handles; retiring the shell wrappers; the RPC→json migration of the spawn scripts.

