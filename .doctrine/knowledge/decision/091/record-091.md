## Decision

The ledger edit (to be made at reconcile, via REV) adds these rows. Row numbers are proposals; the owner and the `Enforced at` symbol are the substance.

| row | authority item | owner | governs | enforced at (intent) |
|---|---|---|---|---|
| 1b | `pi_agent` request schema validation | `pi-mcp` | REQ-001 | the request validator in `pi/mcp`, before any child is spawned |
| 2b | delegate profile → tool allowlist | `pi-mcp` | REQ-002, REQ-006 | profile→tools resolution, clamped by the read-only maxima artifact |
| 3c | delegate execution / jail profile | `satan-flake` | REQ-002, SPEC-002 REQ-016 | the flake's read-only and read-write wrapped forms, plus their flake checks |
| 4c | delegate audit (run + control) | `pi-mcp` | REQ-003 | append-only run-dir log (sink settled by inq-9) |
| 5c | delegate ceilings | `pi-mcp` | REQ-004 | the stream gate + `timeout` (DEC-090) |
| 6c | delegate kill switch | `pi-mcp` | REQ-005 | the enable artifact / server absence (form settled by inq-8) |

## Why this split

- Row 3c mirrors 3b (malebolge): the operator's standing convention puts jail policy in the flake, so the flake owns it and its checks. Putting it on `pi-mcp` would make the server the second place jail policy is expressed (REQ-009).
- Rows 1b/2b/4c/5c/6c are `pi-mcp`'s because each must hold with Emacs absent (ADR-017 §4, SPEC-001 REQ-010) and none is a duty an existing owner performs for this consumer class: `emacs-client` needs the editor, `patch-runner`'s rows are patch-job duties, `daemon-core`'s read-only policy artifact (ADR-018 D2) does not exist yet.
- No row is shared, and no row re-implements an existing site: delegation to `emacs-client` is excluded by the no-Emacs requirement, which is also why this surface exists.

## Consequences

- The legend gains a `pi-mcp` token, entering when the component is first received as owner (authority-ledger.md, owner legend).
- `satan-flake`'s row inherits the obligation to declare the new profile per consumer class and test-assert it (SPEC-002 REQ-016).
- If the flake later exposes the server's own jail, that is a second `satan-flake` row, not a widening of 3c.
