# 09-DOC-DRIFT.md — Documentation drift

## Cross-check: governance.md file map vs actual files

The governance doc's file map was checked against the actual file tree. All listed files exist. No stale entries.

The governance doc lists modes, tools, and their capabilities/permissions. Spot-check against `dl-satan-mode.el`:

- governance.md §Modes table: morning, motd, tick-*, self-edit-mech, self-edit-mind — all present in `dl-satan-mode.el`
  confidence: high

- governance.md tool table: 14 tools listed — all have corresponding `dl-satan-tools-*.el` files
  confidence: high

- governance.md file map: 48 files listed — all present on disk
  confidence: high

## architecture.md vs actual layering

The seven-layer model from architecture.md (invocation, broker, harness, model, tool, output, state) maps correctly onto the file structure. The file-to-layer mapping is deferred to `10-LAYER-MAP.md`.

## protocol.md vs implementation

Protocol.md defines message types: `ready`, `log`, `tool_call`, `final`, `error`, `tool_result`.
The elisp validator (`dl-satan-protocol.el`) and python validator (`harness/protocol.py`) both implement all message types. The shared `protocol/fixtures.json` drives both validator tests.

  confidence: high — protocol is kept in lockstep across both sides.

## patch/brief.md vs implementation

The patch-agent brief defines tool surfaces (`patch_job_create`, `patch_job_status`, `patch_job_result`, `patch_job_cancel`, `patch_job_cleanup`). Implementation in `dl-satan-tools-patch.el` covers create, status (via result), and result. Cancel is mentioned in the handover doc as not killing the process (only updating the DB row). Cleanup isn't implemented yet per the handover.

  `dl-satan-tools-patch.el` — tools implemented
  handover.md — cancel is state-only, process keeps running
  confidence: high — the brief's job lifecycle (states) matches the schema in `0005_patch_jobs.sql`

## memory/design.md vs implementation

Not checked in detail (1000+ line design doc). Handover.md states all 12 implementation steps are complete, all acceptance criteria met. Hip campus cross-ref, renormalize CLI, and v2 grammar fixture all verified.

  confidence: medium — spot-check of handover claims vs actual files confirms key items present.

## Bough gaps doc

`docs/satan/bough-gaps.md` tracks B1 (DR-116 in flight — marked done in handover) and B2 (deferred). The implementation in `dl-satan-tools-bough.el` matches: `recent_changes` now uses `status-transitions` and `created` per DR-116.

  confidence: high — DR-116 follow-up confirmed in CHANGELOG and handover.

## Doc files out of date

No evidence of files that reference symbols/types that no longer exist. However, the doc tree files (`docs/satan/INDEX.md`, architecture.md, governance.md) contain metadata frontmatter with `updated_at` timestamps in hex format — these are updated on significant changes but the `verified_at` field suggests periodic review.

  confidence: medium — metadata freshness not systematically verified.

## Missing doc for new modules

Recent additions (perceptual-layer modules: `dl-satan-percept.el`, `dl-satan-resonance.el`, `dl-satan-observer.el`, `dl-satan-motive.el`, `dl-satan-sensor-alerts.el`, `dl-satan-tank.el`) have a dedicated design doc at `docs/satan/perceptual-design.md` and governance.md has been updated to note them in the file map. No obvious drift.
