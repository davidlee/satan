# REQ-004: A run cannot exceed its token and budget ceilings

## Statement

<!-- The sister TOML's `description` field is the primary, normative statement.
     Prose here may elaborate, expand upon, or disambiguate it — never
     duplicate it. -->

## Rationale

<!-- Why it must hold — the force behind it, not the implementation. -->

Status 2026-10-21 (SL-029): the `pi-mcp` delegate (`pi_agent`) enforces ceilings
on requests, tokens, cost and wall clock, with three properties weaker than "cannot exceed":

- **Retrospective, not admission control.** The stream gate aborts a run once it
  has crossed a ceiling. It does not prevent the next request, and there is no
  provider output cap. Overshoot is bounded by observation latency plus one
  in-flight request's spend (DEC-097, operator-accepted).
- **Own sends only.** Accounting covers the run's own provider sends as its event
  stream reports them. Outside it: a nested `pi`, a direct call to the reachable
  gateway, spend evidenced only inside a tool result, and extension-mediated
  summarization (an extension handling `session_before_compact` supplies its own
  usage). The build passes no extension beyond `builtin:mcp`, which registers no
  such handler.
- **The rest needs a per-run gateway token** (IDE-015), not this accumulator.

Every unit is bounded: a policy whose `maxima` lacks any of `requests`,
`tokens`, `cost_usd` or `wall_clock_s`, or carries a non-positive maximum, is
refused `policy-invalid`. The wall clock is the backstop that does not depend on
reported usage, and it does not stand in for a spend ceiling (DEC-057). REQ-004 stays `pending`; this records what holds, not a
promotion.
