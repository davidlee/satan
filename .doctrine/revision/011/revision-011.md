# REV REV-011 — reconcile SL-028

Revision — a pending revise-intent against authored governance/spec
truth. The structured `[[change]]` payload lives in the sister `revision-NNN.toml`;
this prose companion carries the rationale and the free-text before/after excerpts
for prose-body section edits.

## Rationale

<!-- Why this revision: what authored truth needs to change and why, the scope of
     the staged delta, and (for ADR/POL/STD/prose rows) the before/after excerpts
     the structured payload only labels. Seeded at `revision new`. -->

SL-028 made malebolge's interactive daemon an on-demand systemd user service and, by
running it from the live `~/dev/malebolge` tree beside the pinned patch runner, accepted
a second malebolge revision in production (RSK-020). Two governance texts lag that.

- **SPEC-002** `spec-002.md:36`, Interactive daemon row, Runtime cell.
  Before: "jailed launcher `jailed-malebolge`, room profile: no network".
  After: "on-demand user service; jailed launcher `jailed-malebolge`, room profile: no
  network". The unit is not named (SPEC-002 D2: host facts live in `~/flakes/SATAN.md`).
- **REQ-015** Rationale. Before: "Tracked gaps: RSK-016." After: "Tracked gaps: RSK-016,
  RSK-020."

User agreement: "agreed" (2026-10-20, this session).

## Reconcile narrative

- [RV-050 F-3]: SPEC-002's daemon row did not say the daemon is a managed service; now it
  does, without naming the unit.
- [RV-050 F-3]: REQ-015 did not track RSK-020 (pinned runner + live-tree daemon); now it does.
