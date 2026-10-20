## Decision

A single read-only policy artefact (default `$XDG_CONFIG_HOME/pi-mcp/policy.toml`, override `PI_MCP_POLICY`) is published by the **operator**, not by the flake and not by the client. It carries:

- `roots` — the allowlist (inq-10);
- `maxima` — max_requests, max_tokens, max_usd, backstop_s (DEC-090);
- `profiles` — the permitted profile names (DEC-092);
- `wrapper_read` / `wrapper_write` — the flake-provided wrapped forms (inq-5);
- `enabled` — the kill switch (row 6c, inq-8);
- `transcript_budget_bytes`.

Read once per call (cheap), so a change applies to the next call. An **in-flight run keeps the snapshot it started with**: no mid-flight ceiling or enable change, and the audit records the policy digest per run.

Absent or malformed policy ⇒ **fail closed**: every call is refused (`policy-unavailable`, `policy-invalid`). A delegate with no ceiling is unbounded spend, so a missing file is not a default.

## The switch (inq-8)

`enabled = false` refuses the next call with `disabled`. It is not a mid-flight interrupt; stopping a running delegate is the shutdown ladder (inq-11). Stated plainly rather than implied.

## Amendment to DEC-090: the ceiling guarantee is withdrawn and replaced

DEC-090 claimed the gate fires "before the next request is issued" and that overshoot is bounded by one response. Both were wrong, and the review that surfaced it was right:

- pi emits events and continues; there is **no acknowledgement channel**, so no admission gate exists between the server and the next request.
- Overshoot is therefore bounded only by observation latency plus the spend of whatever request is in flight — not by one response.
- Compaction and retry spend is reported separately (`compaction_end.result.usage`); counting assistant messages is not counting provider requests.

What the server actually does: count usage from the stream (`message_end`, `compaction_end`), abort best-effort when a ceiling is crossed, and refuse to continue when usage is unreadable or unpriced (**fail closed, never fail open**). DEC-090's ownership claim stands; its guarantee does not. DEC-057 remains precedent for *where such a gate would go* if this surface ever moves onto the SDK.

## Consequence

The ledger's row 5c (`pi-mcp` ceilings) must describe retrospective accounting with best-effort termination, not an enforcement gate. The audit records `abort(ceiling)` with the usage at the moment of the gate, and the overshoot is visible in the record rather than denied.


## RV-043 F-4: conformance disposition (operator-accepted 2026-10-20)

The concession below is not the author's: the operator accepted it explicitly
after review, and it is the disposition F-4 required.

- **Guaranteed**: a hard wall-clock cap; a check at every usage-bearing event
  (`message_end`, `compaction_end`); abort on crossing; abort on unknown or
  unpriced usage (fail closed — missing data is never headroom).
- **Not guaranteed**: that a single provider response cannot overshoot, or that a
  crossing prevents the request already in flight. Overshoot is bounded by
  observation latency plus one in-flight request's spend, and by nothing else.
- Ledger row 5c must therefore say *retrospective accounting with best-effort
  termination*, not "ceilings enforced". A REV to SPEC-001 REQ-004 (or an
  amendment naming the weaker property for non-SDK surfaces) is the revision
  candidate to raise at reconcile. DEC-057 stays the model for an SDK path.

## RV-043 F-3: the switch halts enactment

`enabled` is re-read at each gate tick — the same tick that evaluates ceilings,
bounded to about a second by event cadence plus an idle poll. A flip aborts the
in-flight run through the shutdown ladder, audited as `abort(switch)`, and the
next call is refused `disabled`. Admission refusal and active halt are two
distinct behaviours with two distinct names; row 6c covers both.

## RV-043 F-6: the counting units, per record

"Count usage from the stream" was not implementable: "retry attempts" named no record, and a retried turn can look like both a retry and a completion. The units, by record:

| record | requests | tokens | cost |
|---|---|---|---|
| `message_end`, `role: assistant`, carrying usage | +1 | + `input`, `output`, `cacheRead`, `cacheWrite` | + `usage.cost.total` |
| `compaction_end` carrying `result.usage` | +1 | as above | as above |
| `auto_retry_start` | +1, unmeasured | — | — |
| `summarization_retry_scheduled` | +1, unmeasured | — | — |
| `summarization_retry_attempt_start` | +1, unmeasured | — | — |
| everything else — `agent_end`, `turn_end`, `*_end`, `summarization_retry_finished` | — | — | — |

No record is counted twice: a failed send emits its retry record and no completion record; a successful send emits its completion record only. `agent_end.messages` replays already-counted turns and is ignored for usage.

Requests are an **observed lower bound** on provider sends, and the gaps are named rather than implied: a send that emits no record at all, an abandoned summarization chain's last attempt, and any nested agent the delegate launches for itself. A failed attempt is counted but not priced — it increments `requests_unmeasured` instead of being silently zero.

Usage validity: a completed response with absent, non-finite or negative usage, or without `cost.total`, aborts `accounting_unknown`. A cached read priced at zero is a price, not missing data. `cacheWrite` counts; `cacheRead` is reported as `cached`. Every counting record triggers a gate check, and the same accumulator produces the returned status.

The policy artefact also carries `child_binds` — the fixed mounts the wrapped form adds beyond the root and the session directory — because the server cannot check disjointness (design sec-3) against binds it was never told about.


## RV-043 F-6 (second contest): the mapping was wrong — one record per send

Supersedes the counting table above. That table counted `auto_retry_start`,
`summarization_retry_scheduled` *and* `summarization_retry_attempt_start` beside
the completion records, and claimed "a failed send emits its retry record and no
completion record". Inspected against the installed pi 0.99.1 implementation, the
claim is false and the table over-counts:

- the agent loop emits `message_end` for the final message on both its `done` and
  its `error` stream events, and `handleRunFailure` emits `message_start` /
  `message_end` for a thrown failure. A failed assistant send therefore has its
  **own** `message_end`; `auto_retry_start` (emitted afterwards by
  `_prepareRetry`) marks the retry of a send already counted.
- in the summarization path `retryAssistantCall` fires `onRetryScheduled` for a
  failed send, `onRetryAttemptStart` before the next one, and `onRetryFinished` at
  the end, while the send itself lands as `summarization_retry_scheduled` (failed)
  or `compaction_end` (completed). Counting `attempt_start` as well double-counts
  the send that `compaction_end` reports.
- traces verified without any provider call, by exercising the extracted control
  flow with stubbed sends: error-then-stop = 2 sends, and scheduled-then-
  `compaction_end` = 2 sends. The superseded table reported 3 for each.

The corrected invariant is **one counting record per provider send**:

| record | requests | tokens | cost |
|---|---|---|---|
| `message_end`, `role: assistant`, stop reason `stop` / `length` / `tool_use` / `deferred` | +1 | + `input`, `output`, `cacheRead`, `cacheWrite` | + `usage.cost.total` |
| `message_end`, `role: assistant`, stop reason `error` / `aborted` | +1, unmeasured | — | — |
| `compaction_end` (with or without `result.usage`) | +1 | + usage when present | as above |
| `summarization_retry_scheduled` | +1, unmeasured | — | — |
| `auto_retry_start`, `auto_retry_end`, `summarization_retry_attempt_start`, `summarization_retry_finished`, `agent_end`, `turn_end` | — | — | — |

`requests` is therefore exact for this run's own sends, not a lower bound; the
lower-bound language applies only to what the stream cannot see at all.

### Placeholder usage, and the narrow clause this needs accepted

`handleRunFailure` builds its failure message with `usage: EMPTY_USAGE` — zeros,
including `cost.total: 0`. That is a placeholder, not an observation: a
mid-stream abort may well have been billed. It is counted as a request,
contributes nothing to tokens or cost, and is disclosed as `requests_unmeasured`.

That is a **narrowing of the F-4 concession's abort clause** ("abort on unknown or
unpriced usage; missing data is never headroom"), which the operator accepted on
2026-10-20. It is recorded here as a revision candidate awaiting the operator's
decision, not as granted:

- asked for: the abort applies to **answer-bearing** messages (`stop`, `length`,
  `tool_use`, `deferred`); a failure message's placeholder usage is counted,
  unpriced and disclosed, because the run's verdict is already failure and no
  further spend follows from that send except through its separately-counted retry.
- if refused, the strict alternative is an abort on every failure message, which
  makes every provider error and every retry terminate the run as
  `accounting_unknown` — fail-closed, and it should be chosen rather than
  silently weakened.

### Scope of accounting (RV-046 F-4)

The accumulator bounds this run's own provider sends. It cannot attribute a
nested `pi`, a direct call to the reachable gateway, or spend whose only evidence
is text in a tool result — and sec-3 grants bash plus the launch environment, so
those are reachable by design. The ceiling is therefore a bound on the delegate's
run, not on all spend its tools can cause; that limit is a stated conformance gap
(a second one, beside the retrospective-accounting concession) rather than an
implied guarantee, and a per-run gateway token with a spend limit (IDE-015) is the
mechanism for closing it.


## Operator acceptance (2026-10-20): the two recorded concessions

Both candidate clauses above were put to the operator as propositions and accepted
explicitly, in the same session that produced this response. Recorded here as the
durable disposition, not as the author's inference:

1. **Placeholder usage (RV-043 F-6, second contest).** Accepted: the
   `accounting_unknown` abort applies to *answer-bearing* messages (`stop`,
   `length`, `tool_use`, `deferred`). A failure message's `EMPTY_USAGE` is counted
   as a request, contributes no tokens or cost, and is disclosed as
   `requests_unmeasured`. The accepted F-4 clause is narrowed by exactly that
   much and no more — a failure message cannot be read as zero spend, and its
   separately-counted retry is the only spend that follows it.
2. **Nested spend (RV-046 F-4).** Accepted: the ceiling bounds the delegate's own
   run, not all spend its tools can cause. A nested `pi`, a direct call to the
   reachable gateway, and spend evidenced only inside a tool result are outside
   attribution; the limit is a stated conformance gap and a per-run gateway token
   with a spend limit (IDE-015) is the mechanism that closes it.

Both belong in one REV to SPEC-001 REQ-004 at reconcile, beside the retrospective
accounting concession, so the weaker properties are named together rather than
discovered one at a time. They do not change the shape of the guarantee the
ledger rows describe: row 5c remains retrospective accounting with best-effort
termination, and neither acceptance permits a claim of complete attribution.


## RV-043 F-6 (third contest): summarization needs an attempt window

"One counting record per send" was right for assistant sends and wrong for
summarization, because `compaction_end` is also emitted for outcomes that never
reached the provider: the overflow-recovery diagnostic ("context overflow recovery
failed after one compact-and-retry attempt"), a declined summarization, and an
abort before the attempt began. Counting every `compaction_end` overcounts.
Verified in the installed build: `_runAutoCompaction` sets `started` and emits
`compaction_start` only after preparation succeeds, guards its failure-path
`compaction_end` on that same flag, and the overflow diagnostic emits
`compaction_end` outside any such window.

The accumulator therefore keeps one bit, an **attempt window**:

- assistant sends: one `message_end` each, no state needed;
- `compaction_start` and `summarization_retry_attempt_start` **open** a window;
- `summarization_retry_scheduled` (+1, unmeasured) and `compaction_end` (+1, and
  priced when `result.usage` is present) **close** one;
- a `compaction_end` that finds no open window counts **nothing**, and the window
  count is clamped at zero so a diagnostic cannot drive it negative.

Traces, all as tests: success 1; fail-then-success 2; two fails then a success 3;
an all-fail chain 3; error-then-stop assistant pair 2; the overflow diagnostic 0.

Residuals: a summarization declined *after* its window opened would overcount by
one — reachable only through a `session_before_compact` extension handler, and the
server runs `--no-extensions`; and a failure that emits neither `result.usage` nor
a scheduling record undercounts by one, which under-reports requests and never
under-reports tokens or cost.

### `tool_use` and `deferred` are usage-bearing, not answers

Explicit, because one record carries two classifications: a `message_end` with
stop reason `tool_use` or `deferred` is a counted request whose usage must
validate, and it is not an answer — `final: false`, `result: null`. A message that
issued a tool call paid for it; it did not answer.
