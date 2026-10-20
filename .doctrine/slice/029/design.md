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

Two forms are declared, one per capability: read-only and read-write. Both bind, at minimum:

- the launch dir as the root — `--ro-bind` for the read form, `--bind` for the write form. `mountLaunchDir` alone will not do: its true branch is a rw `--bind` (`jailed-agents.nix:193-198`), and a profile does not change it (`mem.fact.jail.profile-is-not-readonly`).
- the session home and the run dir, via **raw args with run-time paths** (`--bind "$PI_MCP_SESSION_HOME" … --setenv …`), the shape `satan/flake.nix:161` already uses for `"$SATAN_RUN_DIR"` (`mem.fact.jail.runtime-path-bind`). This is what keeps sessions out of the target repo and off the per-run tmpfs.
- `~/.pi` (pi writes session/settings state) and `--tmpfs /tmp`, per the existing generator.

The server selects the form by capability and executes it; it does not know or check what else the form binds. That limit is stated, not implied: the server authorises the root, the flake decides the rest of the reach.

## Static mode

`makeJailedAgent { agent = pi-mcp; profile = … }` with the launch jail as the whole confinement. The policy then restates what the jail already decided — `root`, `filesystem`, `agent`, `session_dir`, `run_dir` — and the server validates at start-up that the session and run dirs are writable (`bind-unavailable`) rather than discovering it mid-run. A policy that names wrapper forms *and* `agent` is `policy-invalid`, so the two postures cannot be half-configured.

The server cannot prove it is jailed. That claim belongs to a launcher check in the flake (`jailProbes` pattern), not to a runtime assertion.
<!-- doctrine:section sec-4 -->
# Execution and the stream gate

## Spawn

```
<wrapper form> [--] pi --mode json \
  --model <profile model> --system-prompt <profile body> --tools <resolved set> \
  --thinking <profile level> [--session-id <id> --session-dir <session dir>] \
  --no-extensions --no-skills --no-themes --no-context-files --offline --approve
```

with the prompt on the child's **stdin** (a pipe the server closes), the child's cwd set to the root, stdout redirected straight to `events.jsonl`, and stderr to a separate file. Never `2>&1`: stdout is JSONL only, and merging diagnostics would count them as events.

`--no-extensions` is load-bearing (ISS-052). `--tools` replaces the selection, so the resolved set names every tool. In static mode the executable comes from the policy's `agent`, resolved from `PATH` inside the jail.

## Reading and gating

One reader consumes the child's stdout to files and parses each line (LF framing; no `readline`), counting usage from `message_end` and `compaction_end`. It checks the ceilings (requests, tokens, cost) at each assistant-message boundary and the wall clock via the backstop. Concurrently, the MCP loop reads its own stdin: a blocking result never blocks cancellation (DEC-096).

**The gate is retrospective** (DEC-097). pi has no acknowledgement channel, so a crossing aborts the run; it does not prevent the next request. Overshoot is bounded by observation latency plus the spend of a request already in flight, and no tighter. Unreadable or unpriced usage aborts (fail closed).

## Termination

One ladder for every trigger — SIGTERM to the child's process group, 2 s grace, SIGKILL to the group, audit, return. The child is never detached: `jailed-pi` dies with its launching shell (`mem.fact.jail.background-launch-dies-with-shell`), so "detach and poll" yields a dead jail and no result.
<!-- doctrine:section sec-5 -->
# Result contract

```json
{
  "schema": "pi-agent-result/1",
  "state": "completed" | "failed" | "incomplete" | "timeout" | "ceiling_exceeded" | "refused",
  "session": "<id>",
  "final": true,
  "result": "<answer>" | null,
  "transcript": "<markdown>",
  "status": { ...pi-run-status/1... } | null,
  "artifacts": { "dir": "…", "events": "…", "transcript": "…", "status": "…", "audit": "…" } | null,
  "refusal": { "reason": "…", "detail": "…" }
}
```

## Semantics

- `final` is true only when the run reached `agent_settled` with a stop reason, i.e. the text is an answer rather than the last thing the model happened to say before the run ended. `final: false` means the `result` is partial and `transcript` carries the evidence. This corrects the assumption that the reducer's last prose block is an answer (DEC-093).
- `session` is always present: minted and returned when the caller did not pass one (DEC-099).
- `transcript` is budgeted — and the budget is **soft**: mandatory sections (the final answer) can exceed it, by design and by test. The unbudgeted text is always at `artifacts.transcript`.
- Outcome precedence, one verdict: server abort (`ceiling_exceeded`) > backstop (`timeout`) > reducer verdict (`failed` / `incomplete`) > child exit code. Exit 0 is not success (json mode exits 0 on a model error).
- `refused` carries `status: null`, `artifacts: null`, `result: null` — nothing ran, and the audit records why.

## Artefacts

Under `PI_MCP_RUN_DIR` (default `$XDG_STATE_HOME/pi-mcp/runs`), one directory per run: `events.jsonl`, `stderr.log`, `transcript.md`, `status.json`, `audit.jsonl`, plus a symlink-free `latest` pointer per session. Never inside the root: the dispatch path imports a worker's uncommitted delta, and a run directory there would land in it.
<!-- doctrine:section sec-6 -->
# Session and audit contracts

## Sessions (DEC-099)

- Minted when absent and returned in the result; grammar `^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$`.
- Bound on first use to (canonical root, filesystem capability). Resuming with a different root or capability is refused — a session is not a cross-call privilege channel.
- Same-session concurrency is refused (`session-busy`), not queued: queuing hides ordering bugs and doubles spend behind the driver's back.
- Storage is a shared, persistent session home outside the tree (`PI_MCP_SESSION_HOME`, default under the run dir), bound into the jail by the wrapper form. That is what lets a read-only run on a read-only root carry a conversation across runs, which no bare `jailed-pi` invocation can do.

## Audit (DEC-094, amended)

`audit.jsonl`, one object per line, append-only in practice, single writer `pi-mcp`: `spawn`, `refuse`, `abort` (with usage at the gate), `timeout`, `exit`, each carrying the policy digest.

**Enacted actions** are covered by `events.jsonl` beside it — tool calls and results as pi reports them — and the design says so explicitly rather than claiming the control log is the whole audit (SPEC-001 REQ-003). The pair is the audit: control decisions in `audit.jsonl`, enacted actions in `events.jsonl`, both per-run and durable with the run directory.

**Audit failure is a refusal.** If the audit record cannot be written before spawn, the call is refused. If appending fails mid-run, the run is terminated (the ladder) and the result carries `state: failed`. An unrecorded delegate does not run. `O_APPEND` + fsync is what the OS offers: the file is not immutable, and the design says so rather than claiming more.
<!-- doctrine:section sec-7 -->
# Delivery, authority and verification

## Files

```
pi/mcp/{main,server,policy,profiles,gate,result}.ts   server, entry, policy load, forms, gate, result assembly
pi/mcp/profiles/*.md                                 tracked profile documents (capability + model + tools)
pi/mcp/*.test.ts                                     node --test, offline
bin/pi-mcp                                           shim → node pi/mcp/main.ts
pi/reduce/reduce.ts                                  + Reduced.result (final/partial flag)
flake.nix                                            two per-call wrapped forms; a pi-mcp derivation for static mode
justfile                                             node --test pi/mcp/*.test.ts
```

## Authority (DEC-091)

Five `pi-mcp` rows — request schema validation (1b), profile→tool allowlist (2b), delegate audit (4c), delegate ceilings (5c), delegate kill switch (6c) — and one `satan-flake` row for the execution profiles (3c). Ledger edits land at reconcile via REV, not here.

## Verification

- Offline tests with a stub wrapper and a stub `pi`, asserting: validation order and every refusal token; argv construction; capability→form selection; ceiling arithmetic and abort; the soft budget; result precedence; session minting, binding and busy refusal; audit-failure refusal; and that no bwrap token appears anywhere in `pi/mcp`.
- One live smoke run per posture against deepseek-flash, recorded as evidence, not a gate.
- Flake checks: each wrapped form's argv (the `jailProbes` pattern) and the static launcher; `just check` covers `just test`, which carries the new suite.

## Out of scope, not precluded

A non-pi agent behind the same MCP (the operator's codex/GPT review use case); steering and follow-ups; job handles; retiring the shell wrappers; the RPC→json migration of the spawn scripts.
