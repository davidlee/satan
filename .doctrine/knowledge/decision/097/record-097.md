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
