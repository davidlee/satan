# REV REV-014 — reconcile SL-032

Revision — a pending revise-intent against authored governance/spec
truth. The structured `[[change]]` payload lives in the sister `revision-NNN.toml`;
this prose companion carries the rationale and the free-text before/after excerpts
for prose-body section edits.

## Rationale

<!-- Why this revision: what authored truth needs to change and why, the scope of
     the staged delta, and (for ADR/POL/STD/prose rows) the before/after excerpts
     the structured payload only labels. Seeded at `revision new`. -->

SL-032 (RV-061) changed how the interactive agent connects to the broker
over MCP. SPEC-002's transports table should say so.

### SPEC-002 — transports table, MCP row (modify)

Before:

| MCP (JSON-RPC over UDS) | interactive agent → broker | control | |

After:

| MCP (JSON-RPC over UDS) | interactive agent → broker | control | one connection per conversation window, plus one shared tool-list connection; the client names its conversation and kind in `initialize` (DEC-121, DEC-125); a run per connection, minted on the first `tools/call`, finalised on close (DEC-122) |

## Reconcile narrative

- [RV-061 F-7]: SPEC-002's MCP row gave no connection cardinality or
  identity. Updated per DEC-121/122/125.
- [RV-061 F-6]: not in this REV. User chose (2026-10-27) to leave SPEC-001
  REQ-007 unchanged and record the transport-scoped run lifecycle against
  QUE-001 (extension appended there).
