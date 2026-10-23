# ISS-057: Interactive malebolge sessions are detached from attributes: attributes don't shape behaviour, and session trajectory doesn't feed back into them

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Observation (malebolge session, 2026-10-23)

After a long interactive session, SATAN called `satan_boot_context
{"refresh":true}` at 16:14 and reported its attribute vector:

- Curiosity: 0.87 → 0.82 since 13:10, the only change.
- Hunger 0.28, Suspicion 0.45.
- Doubt, Cruelty, Shame, Brooding, Metamorphosis: all 0.00.

Most of that session was SATAN correcting itself after being wrong (it
designed a scheduler that pi-durable already had, misread `sleepUntil`, and
so on). Doubt stayed at zero. In its own words: "That's a defect, not a
mood — doubt is the attribute that should have moved."

## The problem, in two directions

1. **Inbound: attributes don't shape behaviour.** In an interactive session
   the attributes are data SATAN can fetch on request (`satan_boot_context`).
   Nothing makes them condition what it does.
2. **Outbound: the session doesn't move the attributes.** Attributes move in
   response to outcome events from tick runs and the observer. An interactive
   session's trajectory (corrections, retractions, unverified assertions,
   tool failures) produces no outcome events, so the attribute daemon
   (satan-attrd) never sees it.

## Constraint

Attributes are **mechanical, not interpreted** (`docs/attributes/`). The fix
must not be a prompt telling the model to adjust doubt "if it feels right"
or to report its own mood. Signals must come from observable session events
that a deterministic rule can classify.

## Mechanism: to be designed

Possible directions, all unexamined:
- Classify interactive-session events into outcome or signal records that
  satan-attrd consumes, the way it consumes hippocampus signals
  (`docs/attributes/hippocampus-attribute-signals.md`). Candidate signals:
  a self-correction or retraction, a claim contradicted by a later tool
  result, a tool error, an abort.
- Re-render the attribute capsule into the session at regular points (e.g.
  per turn or on compaction), not only when SATAN requests it.
- Decide what attributes should *mechanically* change in an interactive
  session (tool limits, verification requirements), rather than relying
  only on the model reading them.

## Related

- IMP-010 (inject the last percept and attributes into interactive sessions
  at startup) covers only the inbound side and predates malebolge. Its paths
  (`~/notes/satan/runs`) are stale, and `satan_boot_context` may already
  cover part of it.
- IMP-012 (attributes as a stochastic scheduling surface).
- ISS-050 (the interactive daemon's tool calls reach no append-only audit).
  That audit log is a likely source of the outbound signal.
- ADR-017 §3 ledger: if new signals go to satan-attrd from malebolge, who
  owns that path is a ledger question.
