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

A single read-only file, operator-published, carries: `mode`, `roots`, `maxima`, `profiles`, the wrapper forms (or `agent` in static mode), `child_binds`, `enabled`, `transcript_budget_bytes`. Read once per call so a change applies to the next call; an in-flight run keeps its maxima snapshot, and the audit records the policy digest. The `enabled` switch is the exception and is re-read at every gate tick, because a switch read once is an admission gate rather than a halt (sec-4). Absent or malformed refuses everything: a delegate with no ceiling is unbounded spend.

**This build serves one posture.** `mode` must be `per-call`; a policy asking for `static`, or carrying a static-only field (`agent`, `root`, `filesystem`, `session_home`, `run_dir`, `evidence_dir`), is refused `posture-unsupported` before anything spawns. It is never silently downgraded to another posture and never falls back to a bare agent on the host — that would be a different security story wearing the requested one's name (DEC-100 amendment).

## What it is not

The server is not an MCP *proxy*: it does not forward tools, hold sessions open, or steer runs. One call is one process. Results are MCP tool results (`content` + `isError`), never JSON-RPC errors — a failed run is a successful call.
<!-- doctrine:section sec-2 -->
# Request contract

```
pi_agent(prompt, profile, cwd?, session?, tools?, ceilings?, transcript_budget_bytes?)
```

`prompt` and `profile` are required. `tools` may only narrow the profile's set. `ceilings` may only lower the policy maxima.

## Validation order (fail closed, first failure wins)

1. **policy** — absent or malformed → `policy-unavailable` / `policy-invalid`; a posture this build does not serve, or a static-only field in an otherwise valid file → `posture-unsupported` (DEC-100 amendment).
2. **enabled** — `enabled = false` → `disabled`.
3. **profile** — must match `^[a-z][a-z0-9-]{0,31}$` and exist in the server's **start-up profile snapshot** (DEC-092 amendment), not in a directory read per call; it must be listed in the policy → `profile-invalid` / `profile-unknown` / `profile-not-allowed`.
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
| the tracked profile directory | not protected *as a store* — the live authority is the start-up snapshot below | the profile **documents** are source; the **snapshot** is what grants capability and tools |

## Profiles are live authority, so the server snapshots them

An earlier revision of this section called the profile directory unprotected because a write-capable root already owns the server's source. That equated editing source with deploying it, and it was wrong: profiles are read for every call and DEC-098 takes the filesystem capability *from the profile document*, so a delegate with a write root containing the checkout could rewrite a `read` profile into a `write` one and elevate a later call on another root, with no policy change and no deployment act.

Corrected: the server loads, validates and **freezes** the tracked profiles at start-up — one snapshot, held for the process lifetime, its digest recorded in every run's audit `spawn` record. A profile edit on disk is therefore inert until the server is restarted, which is a deployment act rather than something a delegate can perform from inside a call. Startup refuses (`profile-invalid`, with the path) if the snapshot does not validate.

Refusal, not masking. A mask (`--ro-bind /dev/null` over the store) means the server authoring bwrap args (REQ-009) and gives the posture a second confinement story; a refusal names the overlapping path and keeps one.

Two consequences, stated rather than discovered:

- allowlisting a broad root such as `$HOME` now **fails** this check until the operator relocates the stores out of it or narrows the root. That is the cost of keeping one writable alias out of the delegate's reach, and the refusal detail names the path.
- the check covers what the policy declares. A bind the flake adds and the policy omits is outside the server's knowledge, so the flake check asserts the form's actual bind set equals root + session directory + `child_binds`. That is where the loop closes; a server promise alone would not close it.

## Static mode — designed, not in the initial build

(DEC-100 build-status note: the shape below stands as the design of record; the
initial build ships per-call only. Read it as a specification, not a deliverable.)

In this build the posture is refused at validation step 1 (`posture-unsupported`), so nothing below can activate; it is the design of record for whoever builds it.

`makeJailedAgent { agent = pi-mcp; profile = … }`; the launch jail is the whole confinement. The policy restates what the jail decided — `root`, `filesystem`, `agent`, `session_home`, `run_dir`, `evidence_dir` — and the server validates at start-up that its own dirs are writable (`bind-unavailable`). Its bind set is fixed at launch and it cannot add a bind, so disjointness is a flake check on the launcher plus a start-up comparison against the policy's declaration, not a per-call refusal.

**The residual, stated:** in a single-uid jail the child shares the server's writable view, so it can reach the evidence the server writes. Static mode therefore (a) buffers evidence in memory and flushes it after the child exits, and (b) permits a single declared session, which is also the only session the child can reach. It does not claim per-child evidence isolation; per-call mode is the posture that provides it. A policy naming both wrapper forms and `agent` is `policy-invalid`.

## Executable contract (both postures)

Extensions are off, and that flag has a wider reach than its name suggests.

`--no-extensions` disables *discovered, configured and built-in* extensions, and pi's MCP support is the built-in extension `builtin:mcp` (pi 0.99.1 `docs/settings.md`). A delegate run under a bare `--no-extensions` therefore has **no `mcp__*` tools at all** — no doctrine MCP, no `satan-mcp`, no corpus search — which is the right default for this slice's profiles (file and bash tools, per the tracked documents) and closes the ISS-052 route by which the doctrine extension rewrote state in whatever tree it started in. Explicit `-e` paths still load, so a profile that needs MCP tools makes the launch form pass `-e builtin:mcp`, which re-enables only the MCP built-in and still excludes every discovered extension. That opt-in is not silent: a profile whose tool list names an `mcp__*` tool while the form does not pass `-e builtin:mcp` is refused at validation (`profile-invalid`), because the alternative is a profile that asks for tools it will never receive. Verified against the installed build: no built-in extension registers a `session_before_compact` handler, so enabling `builtin:mcp` alone does not disturb sec-4's compaction-window rule. Any *other* extension is outside that model and outside the accounting — a `session_before_compact` handler can cancel a compaction after its attempt window opens, or supply its own compaction result with its own `usage` while the default provider call is skipped entirely (DEC-097, operator-accepted). The launch forms therefore pass no `-e` other than `builtin:mcp`.

The launcher has the executable baked in and forwards arguments to it: `<launcher> --mode json …`, with no executable word and no `--` (DEC-098 amendment). Static mode names `agent` and requires pi plus its provider configuration in the launch closure and `PATH`; a launcher probe asserts reachability, because the flake's `piInJail` is false when the agent is the server. That probe, like the rest of the static path, is *future* (DEC-100 build status): the per-call forms are the deliverable.

<!-- doctrine:section sec-4 -->
# Execution, the stream gate and termination

## Spawn

The child is spawned as a **process-group leader** (its own session), so the ladder can signal `-pid` without reaching the server or a concurrent call — the jail sets `no-new-session` (`jailed-agents.nix:184`), so no group exists unless the server creates it. cwd is the root; the prompt goes to the child's stdin through a pipe the server closes; stdout is captured by the server into its **own evidence directory** (a path no child can open); stderr goes to a separate file. Never `2>&1`: stdout is JSONL only.

`--no-extensions` is load-bearing (ISS-052), and it also disables the `builtin:mcp` extension, so the child has no MCP tools unless the launch form adds `-e builtin:mcp` for a profile that needs them (sec-3's executable contract). `--tools`/`-t` applies to built-in, extension and custom tools, and replaces the selection. Lifetimes are coupled — the child is never backgrounded — but the group is independent, and those are different things (DEC-096 amendment).

## Gate

One reader parses each event (LF framing, no `readline`) and maintains the **single usage accumulator**. Counting units are defined per record, so two people reading the stream count the same run the same way (DEC-097 F-6 amendment):

| record | requests | tokens | cost |
|---|---|---|---|
| `message_end`, `role: assistant` | +1 | + `input`, `output`, `cacheRead`, `cacheWrite` when the stop reason is `stop` / `length` / `tool_use` / `deferred` | + `usage.cost.total` |
| `compaction_start` | opens a summarization **attempt window** | — | — |
| `summarization_retry_attempt_start` | opens a window | — | — |
| `summarization_retry_scheduled` | +1, unmeasured; closes the window | — | — |
| `compaction_end` **with a window open** | +1; closes the window | + usage when `result.usage` is present | as above |
| `compaction_end` **with no window open** — a diagnostic, a declined summarization, an abort before the attempt began | — | — | — |
| `auto_retry_start`, `auto_retry_end`, `summarization_retry_finished`, `agent_end`, `turn_end` | — | — | — |

**Assistant sends need no state.** The agent loop emits `message_end` for the final message on both its `done` and its `error` stream events, and `handleRunFailure` emits `message_start`/`message_end` for a thrown failure, so each assistant send has exactly one. `auto_retry_start` marks the retry of a send already counted, so it is not counted again.

**Summarization sends do**, because `compaction_end` is also emitted for outcomes that never reached the provider: the overflow-recovery diagnostic, a declined summarization, and an abort before the attempt began. The accumulator therefore keeps one bit — an attempt window — opened by `compaction_start` or `summarization_retry_attempt_start` and closed by a counted record; a `compaction_end` that finds no open window counts nothing, and the window count is clamped at zero so a diagnostic can never drive it negative.

The window is trustworthy because the session emits `compaction_start` only after preparation succeeded and the attempt is about to be made, emits `compaction_end` on its failure paths only inside the same `started` guard, and `retryAssistantCall` fires `onRetryAttemptStart` immediately before a retried send and `onRetryScheduled` only after a send returned an error. Verified traces: a plain success is 1; fail-then-success is 2; two fails then a success is 3; an all-fail chain is 3; an error-then-stop assistant pair is 2; **the overflow diagnostic with no open window is 0**. All are negative controls in sec-7. `agent_end.messages` replays turns already counted and is ignored for usage.

**Residuals, stated.** A summarization declined *after* its window opened would count one request too many — reachable only through a `session_before_compact` extension handler, and the server runs `--no-extensions` (ISS-052); the sole opt-in, `-e builtin:mcp`, registers no such handler, so it cannot occur in this build. A send whose failure emits neither `result.usage` nor a scheduling record would count one too few; that errs toward under-reporting requests, never toward unbounded spend, because tokens and cost come only from completed responses.

**`tool_use` and `deferred` are usage-bearing, not answers.** Two classifications meet at one record and must not be read into each other: a `message_end` with stop reason `tool_use` or `deferred` is a **counted request with priced usage** whose usage must validate, while both give `final: false` and `result: null` (sec-5). A message that issued a tool call paid for it; it did not answer.

**Placeholder usage.** A failure message carries `EMPTY_USAGE` — zeros, including `cost.total: 0` — which is a placeholder, not an observation. It is counted as a request and contributes nothing to tokens or cost: reading the zero as spend would understate, and reading it as an accounting failure would make every provider error and every retry fatal. It is classified **unmeasured** and disclosed as `requests_unmeasured`. The abort rule stays where the run's own accounting is meant to be complete — a *usage-bearing* message (`stop`, `length`, `tool_use`, `deferred`) whose usage is absent, non-finite, negative, or lacks `cost.total` aborts `accounting_unknown`. That narrowing is **operator-accepted** (DEC-097, 2026-10-20), recorded as a clause of the F-4 concession rather than an author's exception.

**Scope of accounting.** `requests`, `tokens` and `cost` describe this run's own provider sends. Two things are outside them and are named rather than assumed: a send that emits no record the parent stream sees (a nested `pi`, or a direct call to the reachable gateway — sec-3 grants bash and the launch environment), and spend whose only evidence is text inside a tool result. The ceiling is therefore a bound on the delegate's own run, not on all spend its tools can cause. The mechanism for the latter is a per-run gateway token (IDE-015), not this accumulator. A third item is extension-mediated work: an extension handling `session_before_compact` can cancel a compaction after its window opened (one request counted that never happened) or return its own `compaction` — summary, `tokensBefore` and **`usage`** — in place of the default provider call, so both the request count and the spend figure would carry the extension's word for it. The server passes no `-e` beyond `builtin:mcp`, which registers no such handler, so this is out of reach in this build; enabling another extension puts it outside the accounting model, and that limit is operator-accepted (DEC-097, 2026-10-20). That limit is **operator-accepted** (DEC-097, 2026-10-20) as a second conformance gap, and the REV to SPEC-001 REQ-004 carries it beside the retrospective-accounting concession.

A tick — every record that increments a unit, plus an idle poll bounded to about a second — evaluates:

- ceilings — requests, tokens, cost, against the clamped maxima;
- the wall clock — the hard backstop;
- the **switch** — `enabled` re-read at the tick, so a flip halts an in-flight run through the ladder, audited `abort(switch)`, with no driver cooperation (DEC-097 amendment);
- the **policy source itself** — the tick re-reads and re-parses the file. Absent, unreadable or malformed aborts the run through the ladder with cause `switch`, because a switch whose source cannot be read is not evidence that it is off. A brief window during a non-atomic rewrite halts the run: the operator publishes atomically (write, then rename), and fail-closed is the direction a control channel should fail in. Later calls are refused `policy-unavailable` / `policy-invalid` as usual;
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
  "termination": "stop|length|error|aborted|tool_use|deferred|eof|exit|spawn|timeout|cancelled|switch|ceiling|accounting|audit|refused",
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

The table in DEC-093 is normative. Cause tokens are canonical: they are the same vocabulary as `termination`, and no token names a mechanism where there is a name for the outcome — the wall-clock backstop's cause is `timeout`, which is also its state. Two rules apply the table.

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
- Same-session concurrency is refused (`session-busy`), not queued — **across processes**, not only within one. A stdio MCP server is per client, so two drivers run two servers over the same `PI_MCP_SESSION_HOME`; an in-memory busy map would pass a single-process test and still let both write one session.
  Ownership is conferred by exactly one act: an `O_EXCL` create of `<state>/sessions/<id>.lock` carrying pid, kernel start time (a bare pid is a false signal after reuse), call id and start. The (root, capability) binding is written in the same critical section as first use, so two processes cannot record different bindings. Ownership survives termination, reap and drain, and is released last.
  A stale lock is **never unlinked in place** — two reclaimers could both unlink, and the second could delete the first's fresh lock, leaving both believing they own the session. The reclaimer elects itself by **atomically renaming** `<lock>` to a private name: exactly one `rename` of a given path can succeed, and the losers refuse `session-busy` instead of retrying. The winner then checks that the file it now owns is the one it inspected (same device and inode), re-confirms the owner is dead, creates the successor with `O_EXCL`, and only then unlinks its private copy. If the file turns out to be alive, or the rename-back loses to a new owner, it refuses and unlinks its copy. A reclaimer that dies mid-reclaim leaves `<lock>` absent, so the next caller's `O_EXCL` create simply succeeds: ownership never doubles. Every reclaim is recorded in `attempts.jsonl`. Where owner liveness cannot be determined (no `/proc`), the answer is `session-busy` — fail closed.
- The child sees **one** directory: `<PI_MCP_SESSION_HOME>/<session-id>/`. Binding and lock metadata are server-side, outside every bind and inside sec-3's protected set. A session id is a bearer capability within the policy's trust domain and the design says so without pretending to authenticate callers.
- In static mode the home is bound at launch, so the policy declares a single session, and the reachability of other sessions is stated as that posture's known limit.

## Evidence (DEC-094, amended)

Two sinks, both server-owned and outside every child bind — asserted by sec-3's disjointness check, not assumed from the bind list:

- `attempts.jsonl` — server-level, one line per attempt that spawned nothing: policy unavailable/invalid, disabled, profile, root, capability, ceiling, session and child-view refusals, and any failure to allocate a run directory. Policy digest recorded when one was readable; no run directory required.
- `<run>/audit.jsonl` — control decisions for a spawned run: `spawn` (with the profile snapshot digest), `abort` (with usage at the gate and the cause), `timeout`, `exit`, `switch`, each with the policy digest.

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

- validation order and every refusal token, including a valid-looking **static** policy refused `posture-unsupported` before spawn with no agent-only fallback path; argv exactness (no executable word, no `--`; `--no-extensions` present, and `-e builtin:mcp` present exactly when a profile names an `mcp__*` tool, and no other `-e` path ever); capability→form selection; that no bwrap token appears anywhere in `pi/mcp`;
- accounting: compaction included; **one request per send**, with the two verified retry traces as negative controls (error+stop = 2, not 3; scheduled+`compaction_end` = 2, not 3); a failure message counted but unmeasured; a diagnostic `compaction_end` with no open attempt window counting no request; absent, non-finite or unpriced usage on a usage-bearing message aborts; returned status equals the gate's inputs — a recorded retry/compaction fixture pins the arithmetic;
- result: error+settled, textless terminal message, multi-block terminal message, stale planning prose, `length` truncation, and the three settlement combos — stop+EOF without `agent_settled`, stop+nonzero exit, settled+nonzero exit;
- precedence: concurrent causes (`causes[0]` and the full list), a failure after `agent_settled`, and a pre-spawn audit failure reported as a refusal;
- evidence isolation, per-call: a hostile bash attempting truncate/unlink/replace of the audit from inside the child — refusal-with-intact-evidence or a fail-closed `audit_failed`, never a clean success; and the alias case, a policy whose root contains the evidence store refusing `view-overlaps-protected` before spawn, for both capabilities;
- lifecycle: two concurrent calls plus a grandchild ignoring SIGTERM; cancel one, assert its subtree is gone after the grace, the other call and the server survive, and the session lock releases only after cleanup; a mid-run switch flip aborts;
- sessions: minting and return, binding mismatches, busy refusal, grammar edges including a valid single character and trailing `.` `_` `-` — and **two independent server processes** sharing one state root, where simultaneous same-session calls spawn exactly one, the loser is refused before side effects, and a first-use race with conflicting root/capability binds exactly once — plus two processes presented with one **stale** lock, where exactly one may reclaim and spawn, the loser refuses, and a reclaimer killed mid-rename leaves state the next caller can take without double ownership;
- authority integrity: mutate a tracked profile from inside an authorised `write` call and assert a subsequent call on another root keeps the snapshotted capability — the change takes effect only after a restart;
- policy loss: delete and separately corrupt the policy during an idle run, with no driver cancellation, asserting a fail-closed abort, cleanup, and refusal of later calls;

The demonstrate obligations above (child-view disjointness, accounting arithmetic, argv exactness, termination domain) bind the exit criteria of the phase that implements each mechanism; the design records the obligation and the assertion, and the plan owns the placement. None of them is verifiable before that phase exists.

One live smoke run, per-call posture, against deepseek-flash, recorded as evidence, not a gate. Flake checks: each wrapped form's argv and its actual bind set against `child_binds` (`jailProbes` pattern). *Future, on the static build:* the static launcher's closure check, the launch-time writability and disjointness validation, and the memory-buffered evidence path. `just check` carries the suite.

## Out of scope, not precluded

A non-pi agent behind the same MCP (the operator's codex/GPT review use case); steering and follow-ups; job handles; retiring the shell wrappers; the RPC→json migration of the spawn scripts.





