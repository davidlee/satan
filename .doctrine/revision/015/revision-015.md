# REV REV-015 — reconcile SL-034

Revision — a pending revise-intent against authored governance/spec
truth. The structured `[[change]]` payload lives in the sister `revision-NNN.toml`;
this prose companion carries the rationale and the free-text before/after excerpts
for prose-body section edits.

## Rationale

<!-- Why this revision: what authored truth needs to change and why, the scope of
     the staged delta, and (for ADR/POL/STD/prose rows) the before/after excerpts
     the structured payload only labels. Seeded at `revision new`. -->

SL-034 (RV-063) gave the interactive daemon's room profile a new duty —
SATAN's self-scheduled wakes — and a second satan-mcp connection kind. SPEC-002,
the whole-system map, should say both.

### SPEC-002 — containers table, Interactive daemon row, Owns (modify)

Before:

| … | its durable conversations (`durable/room/`); model loop, persona and SATAN MCP on the host; coding tools in an oubliette room as its own room user | — |

After:

| … | its durable conversations (`durable/room/`); model loop, persona and SATAN MCP on the host; coding tools in an oubliette room as its own room user; SATAN's self-scheduled wakes (room profile: `satan.wake` tasks, heartbeat, start sweep, `MALEBOLGE_WAKES` switch; SL-034) | — |

### SPEC-002 — transports table, MCP row (modify)

Before: "the client names its conversation and kind in `initialize` (DEC-121, DEC-125)"

After: "the client names its conversation and kind (`interactive`, or `scheduled` for the room daemon's wake calls) in `initialize` (DEC-121, DEC-125)"

## Reconcile narrative

- [RV-063 F-9]: design SL-034 sec-6 deferred the SPEC-002 update to reconcile.
  The interactive daemon's Owns gains wake scheduling; the MCP row names the
  `scheduled` kind.
