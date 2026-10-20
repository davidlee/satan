# IDE-015: Per-run gateway token with a spend limit as the hard-cap mechanism

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## The idea

SL-029 enforces ceilings *retrospectively*: the server counts usage from the event
stream and aborts when a ceiling is crossed, with no provider output cap
(DEC-090 as amended by DEC-097; the REQ-004 conformance concession the operator
accepted under RV-043 F-4). That is a reporting-and-abort mechanism. It cannot
prevent a single response from overshooting, and it cannot stop the request
already in flight.

An operator-side alternative would give a genuinely hard cap, independent of what
the delegate's process does:

> Have the gateway mint a **run-scoped token** (every gateway token carries a
> spend limit) and hand that token to the run as the provider credential. The
> delegate then cannot spend past the token's limit even if it ignores the
> server, because the ceiling is enforced below the agent, at the point where
> money is actually spent.

The friction is issuing credentials: the gateway's token issuance path needs
operator authority (a sudo password), so it cannot be done silently per call.

## Why it is not being done now

- It moves a per-call decision behind an interactive operator step.
- It puts credential issuance in the server's path, which is a much larger
  authority grant than "count and abort" (ADR-017 ledger, DEC-043: gateway
  budgets are deployment insurance, not SATAN policy).
- The cheap postures (wall clock + retrospective abort + unknown-usage-aborts)
  cover the realistic failure — a runaway agent looping on tool calls — because
  the wall clock is a hard bound and the abort lands within an event or two.

## What would make it worth doing

- Repeated large overshoot incidents where the retrospective abort's latency
  mattered.
- Or the arrival of a non-interactive issuance path at the gateway, which would
  remove the sudo friction.
- Or a delegate whose provider calls do not flow through the gateway at all, so
  the server is the only observing point — that is already the case for direct
  provider keys, and is an argument *against* exposing those keys to delegates.

## Related

DEC-043 (gateway budgets are deployment insurance), DEC-057 (the patch runner's
model-gate precedent — the SDK-shaped answer to the same problem), DEC-097 and
the F-4 concession in RV-043.
