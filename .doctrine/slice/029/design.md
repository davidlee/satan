<!-- doctrine:section sec-1 -->
# Overview and postures

`pi/mcp/` is a stdio MCP server exposing one tool, `pi_agent`, which runs a single one-shot pi agent and answers with a reduced transcript. It imports `pi/reduce` (no shell-out) and is launched by `bin/pi-mcp`, a bash shim that execs `node` on the TypeScript entry point — the same no-build-step shape as `bin/pi-run-reduce`.

## Two postures (DEC-100)

| posture | confinement | roots | capabilities |
|---|---|---|---|
| `per-call` (default) | a flake-provided wrapped runner launched once per call, cwd = the call's root | many, from the allowlist | one per profile (`read` / `write`) |
| `static` (designed, not built here — DEC-100 build status) | the server *is* the jailed process; children inherit | one, fixed at launch | one, fixed at launch |

The posture is an operator declaration in the policy artefact, fixed for the process lifetime. It is never a per-call argument: a caller must not choose its own confinement.

## One policy artefact (DEC-097)

A single read-only file, operator-published, carries: `mode`, `roots`, `maxima`, `profiles`, the wrapper forms (or `agent` in static mode), `child_binds`, `enabled`, `transcript_budget_bytes`. Read once per call so a change applies to the next call; an in-flight run keeps its snapshot, and the audit records the policy digest. Absent or malformed refuses everything: a delegate with no ceiling is unbounded spend.

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
8. **child view** — no member of the effective child bind set may expose a protected store more strongly than that store tolerates (sec-3) → `view-overlaps-protected`.

The refusals are the contract: each is a stable token plus a `detail` string, and each is recorded — `attempts.jsonl` when nothing spawned, `refuse` in the run audit once a run directory exists. A caller never receives a silent downgrade.

<!-- doctrine:section sec-3 -->
# Confinement contract

Jail policy lives in the flake and is exposed as a wrapped form; the server holds no bwrap argv (DEC-098/100, SPEC-001 REQ-009). The flake is the only place a bind is decided.

## Per-call mode

Two forms are declared, one per capability. Each binds:

- the launch dir as the root — `--ro-bind` for read, `--bind` for write. `mountLaunchDir` alone will not do: its true branch is a rw `--bind` and a profile does not change it (`mem.fact.jail.profile-is-not-readonly`).
- `~/.pi` (pi writes session and settings state there) and `--tmpfs /tmp`.
- **the active session directory only** — `<PI_MCP_SESSION_HOME>/<session-id>/`, via raw args with run-time paths (`mem.fact.jail.runtime-path-bind`). Not the session home, and never the run directory: the child's writable set is exactly what it needs to continue its own conversation.

## Child-view disjointness

The server-owned evidence directory (events, stderr, transcript, status, audit) is bound into no child — and "no bind names it" is not the property that matters, because a root or a fixed mount that *contains* it exposes it just as surely. DEC-095 lets an operator allowlist `$HOME` or `/`, which contains everything.

The property is **disjointness over the effective child view**, checked before spawn. The policy declares the posture's **fixed child binds** (`child_binds`): the mounts the wrapped form adds beyond the root and the session directory — `~/.pi`, a flake's `workspaceDeps`, whatever else. The child view is therefore the union of {root, active session directory, `child_binds`}, all canonicalised, and it is refused `view-overlaps-protected` when a member is, contains, or lies inside a protected path **more strongly than that store tolerates** — unreachable stores refuse any exposure, read or write; the never-writable policy file refuses only a writable one (a `write`-capability root, or a rw fixed bind). The active session directory is not inside the protected region by construction: it is the one session path the child is meant to have.

Protected paths, by the harm each would do:

| store | protection | why |
|---|---|---|
| the run evidence directory (every run's), `attempts.jsonl` | unreachable — neither read nor write | tampering defeats the audit; reading it leaks other runs' transcripts and prompts |
| the session home's *other* sessions — the home minus the active session directory — and the binding/lock metadata | unreachable | other sessions' histories are not this call's to read, and a forged binding crosses the session capability check |
| the policy file | never writable (readable is tolerated) | it governs *other* calls — `enabled`, maxima, allowlists — i.e. authority the call does not have |
| the tracked profile directory | not protected | a write-capable root already confers authority over the server's own code and flake forms, so guarding the profile documents would be theatre |

Refusal, not masking. A mask (`--ro-bind /dev/null` over the store) means the server authoring bwrap args (REQ-009) and gives the posture a second confinement story; a refusal names the overlapping path and keeps one.

Two consequences, stated rather than discovered:

- allowlisting a broad root such as `$HOME` now **fails** this check until the operator relocates the stores out of it or narrows the root. That is the cost of keeping one writable alias out of the delegate's reach, and the refusal detail names the path.
- the check covers what the policy declares. A bind the flake adds and the policy omits is outside the server's knowledge, so the flake check asserts the form's actual bind set equals root + session directory + `child_binds`. That is where the loop closes; a server promise alone would not close it.

## Static mode — designed, not in the initial build

(DEC-100 build-status note: the shape below stands as the design of record; the
initial build ships per-call only. Read it as a specification, not a deliverable.)

`makeJailedAgent { agent = pi-mcp; profile = … }`; the launch jail is the whole confinement. The policy restates what the jail decided — `root`, `filesystem`, `agent`, `session_home`, `run_dir`, `evidence_dir` — and the server validates at start-up that its own dirs are writable (`bind-unavailable`). Its bind set is fixed at launch and it cannot add a bind, so disjointness is a flake check on the launcher plus a start-up comparison against the policy's declaration, not a per-call refusal.

**The residual, stated:** in a single-uid jail the child shares the server's writable view, so it can reach the evidence the server writes. Static mode therefore (a) buffers evidence in memory and flushes it after the child exits, and (b) permits a single declared session, which is also the only session the child can reach. It does not claim per-child evidence isolation; per-call mode is the posture that provides it. A policy naming both wrapper forms and `agent` is `policy-invalid`.

## Executable contract (both postures)

The launcher has the executable baked in and forwards arguments to it: `<launcher> --mode json …`, with no executable word and no `--` (DEC-098 amendment). Static mode names `agent` and requires pi plus its provider configuration in the launch closure and `PATH`; a launcher probe asserts reachability, because the flake's `piInJail` is false when the agent is the server. That probe, like the rest of the static path, is *future* (DEC-100 build status): the per-call forms are the deliverable.

<!-- doctrine:section sec-4 -->
# Execution, the stream gate and termination

## Spawn

The child is spawned as a **process-group leader** (its own session), so the ladder can signal `-pid` without reaching the server or a concurrent call — the jail sets `no-new-session` (`jailed-agents.nix:184`), so no group exists unless the server creates it. cwd is the root; the prompt goes to the child's stdin through a pipe the server closes; stdout is captured by the server into its **own evidence directory** (a path no child can open); stderr goes to a separate file. Never `2>&1`: stdout is JSONL only.

`--no-extensions` is load-bearing (ISS-052). `--tools` replaces the selection. Lifetimes are coupled — the child is never backgrounded — but the group is independent, and those are different things (DEC-096 amendment).

## Gate

One reader parses each event (LF framing, no `readline`) and maintains the **single usage accumulator**. Counting units are defined per record, so two people reading the stream count the same run the same way (DEC-097 F-6 amendment):

| record | requests | tokens | cost |
|---|---|---|---|
| `message_end`, `role: assistant`, carrying usage | +1 | + `input`, `output`, `cacheRead`, `cacheWrite` | + `usage.cost.total` |
| `compaction_end` carrying `result.usage` | +1 | as above | as above |
| `auto_retry_start` (an assistant send failed) | +1, unmeasured | — | — |
| `summarization_retry_scheduled` (a summarization send failed) | +1, unmeasured | — | — |
| `summarization_retry_attempt_start` (a retried summarization send) | +1, unmeasured | — | — |
| everything else — `agent_end`, `turn_end`, `*_end`, `summarization_retry_finished` | — | — | — |

A failed send emits only its retry record and never a `message_end`/`compaction_end` for that attempt, so a retried-and-then-succeeded turn is two requests and one response, and no record is counted twice. `agent_end.messages` replays turns already counted and is ignored for usage.

Requests are therefore an **observed lower bound** on provider sends, and this is stated rather than implied: a send that emits no record at all is invisible, as is an abandoned summarization chain's final attempt and any nested agent the delegate launches itself. Tokens and cost come only from completed responses, so a failed attempt is counted but not priced — it increments `requests_unmeasured` instead of being silently zero.

A tick — every record that increments a unit, plus an idle poll bounded to about a second — evaluates:

- ceilings — requests, tokens, cost, against the clamped maxima;
- the wall clock — the hard backstop;
- the **switch** — `enabled` re-read at the tick, so a flip halts an in-flight run through the ladder, audited `abort(switch)`, with no driver cooperation (DEC-097 amendment);
- usage sanity — a completed response whose usage is absent, non-finite or negative, or whose `cost.total` is absent, aborts `accounting_unknown`. A cached read priced at zero is a price, not missing data. Missing data is never headroom.

The gate is **retrospective**: it aborts a crossing, it does not prevent the next request, and there is no provider output cap (DEC-097; operator-accepted conformance concession). Overshoot is bounded by observation latency plus one in-flight request's spend. The same accumulator produces the returned status, so enforcement and reporting cannot disagree (DEC-093 amendment).

## Termination

One ladder for every trigger: SIGTERM to the group, 2 s grace, SIGKILL to the group, then reap and drain the stream, then audit, then return. The result and the session-lock release happen only after cleanup, and the commit point (sec-5) is the last of these steps. Concurrently the MCP loop reads its own stdin: a blocking result never blocks cancellation.

<!-- doctrine:section sec-5 -->
# Result contract

```json
{
  "schema": "pi-agent-result/1",
  "state": "completed|failed|incomplete|timeout|cancelled|ceiling_exceeded|accounting_unknown|audit_failed|refused",
  "termination": "stop|length|error|aborted|tool_use|deferred|eof|exit|spawn|backstop|cancelled|switch|ceiling|accounting|audit|refused",
  "causes": ["timeout", "audit"],
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

`result` is the **terminal assistant message** — the last assistant `message_end` with a terminal stop reason and no later assistant message — with all of its text blocks joined. A later assistant `message_start` or `message_end` invalidates an earlier candidate, so a message is only terminal once the stream has none after it. A backwards search for the last prose block is expressly not the rule (DEC-093 amendment).

`final` is true for exactly two terminal reasons — `stop`, and `length` (which also sets `truncated: true`, the text being complete as far as the provider produced it) — and only when the run also **settled and exited 0** (below). `error`, `aborted`, `tool_use`, `deferred` and every server-caused stop give `final: false, result: null`: a stop reason on a message is not by itself evidence that an answer exists.

`session` is always present — minted and returned when the caller supplied none.

`transcript` is budgeted and the budget is **soft**: mandatory sections can exceed it, by design and by test. The unbudgeted text is at `artifacts.transcript`.

## Cause, state and precedence

The table in DEC-093 is normative. Two rules apply it.

- **The abort latch defeats provisional success.** `completed` is provisional until the **commit point**: after the ladder, reap, stream drain, final accounting and the `exit` and abort evidence appends. A cause recorded before that point joins the latch and decides the state, so there is no ordering in which the run reports success while the reason it stopped was accounting or audit failure. After the commit point the result is immutable — nothing is left that can fail, because the return is the last step.
- **`causes[0]` is the reported cause; the whole ordered list is returned.** Precedence among concurrent causes is order of discovery, and a later cause is never hidden behind an earlier one: an audit append that fails after a timeout reports `termination: "timeout"` with `causes: ["timeout", "audit"]`, and the audit carries both. `termination` is always `causes[0]`, and `state` is that cause's row.

**Success** requires all of: a terminal answer-bearing message (`stop` / `length`); `agent_settled` observed; child exit status 0; accounting known. Anything else is decided by the latch, or, when the latch is empty, by the terminal reason. Exit 0 is never evidence of success (json mode exits 0 on a model error), and a valid answer plus a nonzero exit is `failed`.

`status.state` is the reducer's verdict **on the stream**; `state` is the server's verdict **on the call**. They differ only when the deciding cause happened outside the stream — `exit`, `spawn`, `audit`, `accounting`, `backstop` — and `causes` names it. Two verdicts, one reason, and never two accounting stories.

`refused` carries `status`, `artifacts`, `result` all null and a `refusal { reason, detail }`: nothing ran. `termination` is `"refused"` and `causes` is `["refused"]`; `refusal.reason` names which refusal, which may be a refusal token or a failure to record one (`audit-failed`, `audit-unavailable`). `audit_failed` as a **state** exists only for a run that spawned; `failed` with `termination: "spawn"` is a pre-spawn process failure after the run directory was allocated.

## Artefacts

One directory per run under `PI_MCP_RUN_DIR`, never inside the root, never bound into a child and excluded from every child bind by sec-3's check: `events.jsonl`, `stderr.log`, `transcript.md`, `status.json`, `audit.jsonl`. Pre-spawn refusals have no run directory and are recorded in the server-level `attempts.jsonl` (sec-6).

<!-- doctrine:section sec-6 -->
# Session and audit contracts

## Sessions (DEC-099, amended)

- Minted when absent and returned; grammar alnum at both ends, 1–64 characters — the grammar pi itself accepts.
- Bound on first use to (canonical root, filesystem capability); resuming otherwise is refused.
- Same-session concurrency is refused (`session-busy`), not queued.
- The child sees **one** directory: `<PI_MCP_SESSION_HOME>/<session-id>/`. Binding and lock metadata are server-side, outside every bind and inside sec-3's protected set. A session id is a bearer capability within the policy's trust domain and the design says so without pretending to authenticate callers.
- In static mode the home is bound at launch, so the policy declares a single session, and the reachability of other sessions is stated as that posture's known limit.

## Evidence (DEC-094, amended)

Two sinks, both server-owned and outside every child bind — asserted by sec-3's disjointness check, not assumed from the bind list:

- `attempts.jsonl` — server-level, one line per attempt that spawned nothing: policy unavailable/invalid, disabled, profile, root, capability, ceiling, session and child-view refusals, and any failure to allocate a run directory. Policy digest recorded when one was readable; no run directory required.
- `<run>/audit.jsonl` — control decisions for a spawned run: `spawn`, `abort` (with usage at the gate and the cause), `timeout`, `exit`, `switch`, each with the policy digest.

Enacted actions are covered by `<run>/events.jsonl` beside it. Control decisions and enacted actions together are the audit (SPEC-001 REQ-003); neither is claimed alone.

**Failure policy.** If `attempts.jsonl` cannot be written, the refusal is returned in-band and on stderr and the server does not spawn (`audit-unavailable`). If a run's audit append fails **before** spawn, the run directory is discarded and the call is refused `audit-failed` — nothing ran, so it is a refusal, not a state. **Mid-run**, the run is aborted through the ladder and reported `audit_failed` with `causes` carrying any earlier cause. Static mode buffers evidence in memory and flushes after exit, so a co-resident child could still write the evidence directory: that is the posture's stated residual, not an assurance.

<!-- doctrine:section sec-7 -->
# Delivery, authority and verification

## Files

```
pi/mcp/*.ts                      server, policy load, profiles, wrapper forms, child-view check, gate, accounting, result, stdio loop
pi/mcp/profiles/*.md             tracked profile documents (filesystem capability + model + tools)
pi/mcp/*.test.ts                 node --test, offline
bin/pi-mcp                       shim → node pi/mcp/main.ts
pi/reduce/reduce.ts              + result, final, terminalReason, requests, requests_unmeasured; one accumulator incl. compaction_end and retry records
flake.nix                        two per-call wrapped forms (the static-mode derivation is deferred)
justfile                         node --test pi/mcp/*.test.ts
```

The reducer change is one accumulator and the fields that read it: the server embeds its status verbatim, so a second accounting path would be a second truth (DEC-093 amendment). The build is per-call only (DEC-100 build status); everything below marked *future* is the design of record for static mode, not a build obligation.

## Authority (DEC-091)

Five `pi-mcp` rows — request schema validation (1b), profile→tool allowlist (2b), delegate audit (4c), delegate ceilings (5c, described as retrospective accounting with best-effort termination), delegate kill switch (6c, admission refusal *and* active halt) — and one `satan-flake` row for the execution profiles (3c). Ledger edits land at reconcile via REV.

## Verification

Offline, with a stub launcher and a stub pi:

- validation order and every refusal token; argv exactness (no executable word, no `--`); capability→form selection; that no bwrap token appears anywhere in `pi/mcp`;
- accounting: compaction included; a retried turn counted once per send; a failed send counted but unmeasured; absent, non-finite or unpriced usage aborts; returned status equals the gate's inputs — a recorded retry/compaction fixture pins the arithmetic;
- result: error+settled, textless terminal message, multi-block terminal message, stale planning prose, `length` truncation, and the three settlement combos — stop+EOF without `agent_settled`, stop+nonzero exit, settled+nonzero exit;
- precedence: concurrent causes (`causes[0]` and the full list), a failure after `agent_settled`, and a pre-spawn audit failure reported as a refusal;
- evidence isolation, per-call: a hostile bash attempting truncate/unlink/replace of the audit from inside the child — refusal-with-intact-evidence or a fail-closed `audit_failed`, never a clean success; and the alias case, a policy whose root contains the evidence store refusing `view-overlaps-protected` before spawn, for both capabilities;
- lifecycle: two concurrent calls plus a grandchild ignoring SIGTERM; cancel one, assert its subtree is gone after the grace, the other call and the server survive, and the session lock releases only after cleanup; a mid-run switch flip aborts;
- sessions: minting and return, binding mismatches, busy refusal, grammar edges including a valid single character and trailing `.` `_` `-`.

The demonstrate obligations above (child-view disjointness, accounting arithmetic, argv exactness, termination domain) bind the exit criteria of the phase that implements each mechanism; the design records the obligation and the assertion, and the plan owns the placement. None of them is verifiable before that phase exists.

One live smoke run, per-call posture, against deepseek-flash, recorded as evidence, not a gate. Flake checks: each wrapped form's argv and its actual bind set against `child_binds` (`jailProbes` pattern). *Future, on the static build:* the static launcher's closure check, the launch-time writability and disjointness validation, and the memory-buffered evidence path. `just check` carries the suite.

## Out of scope, not precluded

A non-pi agent behind the same MCP (the operator's codex/GPT review use case); steering and follow-ups; job handles; retiring the shell wrappers; the RPC→json migration of the spawn scripts.

