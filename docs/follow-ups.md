---
name: satan-follow-ups
description: SATAN follow-ups — migrated to the spec-driver backlog (2026-05-30)
metadata:
  type: tracking
  topic: satan
  status: superseded
---

# SATAN follow-ups → spec-driver backlog

This tracker has been **superseded by the spec-driver backlog** (2026-05-30).
Open follow-ups now live as backlog items; capture new ones with
`spec-driver create {issue|improvement|risk} "…"` rather than appending here.

Open items migrated from this file:

| Was | Now |
| --- | --- |
| A1 strict — every run writes `percept.json` | `ISSUE-001` |
| A16 verifier — `notified.json` ↔ `actions.json.pre_spawn` | `IMPR-001` (blocked: needs fixtures) |
| A13 verifier — `observer.json` ↔ intervention transcripts | `IMPR-002` (blocked: needs fixtures) |
| T-attr-1d — attribute capsule render | `IMPR-003` (blocked: needs real outcome rows) |

Resolved without migration:

- **Resonance block payload enrichment** — shipped 2026-05-30 (`6f5f708`); see
  `resonance-payload-handover.md`.
- All §"Code cleanup" and §"Daemon contract pins" items — done 2026-05-29/30.

The completed-item detail (capability migration, jsonl-read collapse, `vcs_log`
cadence fix, broker manifest test, curiosity self-cancel, outcome-pipeline
timestamp bug, JSON null/empty render, `satan-attrd rebuild` idempotence) lives
in git history and `CHANGELOG.md`.
