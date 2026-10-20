## Decision

`pi_agent` enforces four ceilings itself, outside the pi process:

- **wall clock** — `timeout` around the wrapped runner, abort = SIGTERM then SIGKILL to the process group;
- **model requests, tokens, cost** — counted from the event stream the server is already reading (`message_end.usage`), checked at each assistant-message boundary; a crossing aborts the run with a named reason before the next request is issued;
- **numbers** — per-call `ceilings` arguments (max_requests, max_tokens, max_usd, backstop_s), clamped by hard maxima loaded from a read-only config artifact the server reads and never writes (SPEC-001 REQ-006: surfaces read policy, none restate it).

Overshoot is bounded by one provider response — the same guarantee DEC-057 accepted for the patch runner ('spend therefore exceeds a ceiling by at most one request').

## Why not the gateway

DEC-043 (accepted) rules gateway key budgets out as SATAN ceilings: they are deployment insurance, generous on purpose, and not in the ADR-017 ledger. A per-call minted gateway key would make the number SATAN's but would put the enforcement point in the gateway's control plane, which the server has no business holding. The gateway stays insurance; the ledger row is `pi-mcp`'s.

## Why not a model gate like the patch runner's

DEC-057's gate sits inside the process that makes the calls (pi-durable's `runtime.models` view). A CLI delegate has no such seam — the calls leave from inside pi — so the gate must sit outside it, on the stream, and accept the one-response bound. If a future SL-029 drops the CLI transport for the SDK, the gate returns inside and the bound tightens; that is not this slice.

## What this does not do

A single in-flight model call cannot be interrupted mid-response by the stream gate; it is bounded by the wall clock instead. A ceiling crossing is a control decision and must be audited (inq-9), not merely returned.

## Consequence for the ledger

Ceilings become a `pi-mcp` row with an enforced-at symbol (the gate function plus the `timeout`), on the DEC-057 precedent — not a delegation to `satan-flake` and not to `emacs-client`'s run budget.
