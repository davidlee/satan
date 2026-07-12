# 11-TOOL-CATALOG.md — Broker-owned tool catalog

Sourced from `dl-satan-tools.el` (registry) and `dl-satan-tools-*.el` (handlers).
Mode allowlists and risk levels from `dl-satan-mode.el` and governance doc.

| Tool name | Risk | Capability | File | Handler symbol | Has test? | Modes (from governance) |
|---|---|---|---|---|---|---|
| `org_read_context` | read | — | `dl-satan-tools-org.el` | `dl-satan-tool/org-read-context` | Via shared test | morning, motd, tick-* |
| `org_update_owned_block` | low | `write-daily` | `dl-satan-tools-org.el` | `dl-satan-tool/org-update-owned-block` | Via shared test | morning |
| `proposal_stage` | low | `stage-proposal` | `dl-satan-tools-org.el` | `dl-satan-tool/proposal-stage` | Via shared test | morning, self-edit-* |
| `notify_send` | low | `notify` | `dl-satan-tools-notify.el` | `dl-satan-tool/notify-send` | Via shared test | morning, motd, tick-* |
| `hippocampus_write` | low | `hippocampus-write` | `dl-satan-tools-hippocampus.el` | `dl-satan-tool/hippocampus-write` | `tools-hippocampus-test.el` | morning, motd, tick-* |
| `inbox_append` | low | `inbox-write` | `dl-satan-tools-inbox.el` | `dl-satan-tool/inbox-append` | Via shared test | morning, motd, tick-* |
| `agenda_read` | read | — | `dl-satan-tools-agenda.el` | `dl-satan-tool/agenda-read` | Via shared test | morning, motd |
| `activity_read` | read | — | `dl-satan-tools-activity.el` | `dl-satan-tool/activity-read` | Via shared test | morning, motd |
| `bough_read` | read | — | `dl-satan-tools-bough.el` | `dl-satan-tool/bough-read` | `tools-bough-test.el` | morning, motd, tick-*, self-edit-* |
| `memory_mark` | low | `memory-write` | `dl-satan-tools-memory.el` | `dl-satan-tool/memory-mark` | `tools-memory-test.el` | morning, motd, tick-* |
| `memory_resonate` | read | — | `dl-satan-tools-memory.el` | `dl-satan-tool/memory-resonate` | `tools-memory-test.el` | morning, motd, tick-*, self-edit-* |
| `memory_show_trace` | read | — | `dl-satan-tools-memory.el` | `dl-satan-tool/memory-show-trace` | `tools-memory-test.el` | all (read-only) |
| `docs_list` | read | — | `dl-satan-tools-docs.el` | `dl-satan-tool/docs-list` | `tools-docs-test.el` | morning, self-edit-* |
| `docs_search` | read | — | `dl-satan-tools-docs.el` | `dl-satan-tool/docs-search` | `tools-docs-test.el` | morning, self-edit-* |
| `docs_read` | read | — | `dl-satan-tools-docs.el` | `dl-satan-tool/docs-read` | `tools-docs-test.el` | morning, self-edit-* |
| `sway_border_set` | low | `notify` | `dl-satan-tools-sway.el` | `dl-satan-tool/sway-border-set` | `test-sway-border.el` | morning, motd, tick-*, self-edit-* |
| `sway_border_reset` | low | `notify` | `dl-satan-tools-sway.el` | `dl-satan-tool/sway-border-reset` | `test-sway-border.el` | morning, motd, tick-*, self-edit-* |
| `motive_read` | read | — | `dl-satan-tools-motive.el` | `dl-satan-tool/motive-read` | `tools-motive-test.el` | broker-side (not model-facing?) |
| `notes_recent` | read | — | `dl-satan-tools-notes.el` | `dl-satan-tool/notes-recent` | Via shared test | morning |
| `satan_final` | — | — | synthetic (harness) | N/A — harness intercepts | Via protocol tests | all |
| `patch_job_create` | low | `patch-job-create` | `dl-satan-tools-patch.el` | `dl-satan-tool/patch-job-create` | `tools-patch-test.el` | tick-agent, self-edit-{mech,mind} |
| `patch_job_status` | read | — | `dl-satan-tools-patch.el` | `dl-satan-tool/patch-job-status` | `tools-patch-test.el` | tick-agent, self-edit-{mech,mind} |
| `patch_job_result` | read | — | `dl-satan-tools-patch.el` | `dl-satan-tool/patch-job-result` | `tools-patch-test.el` | (not listed in governance) |
| `patch_job_cancel` | low | `patch-job-cancel` | `dl-satan-tools-patch.el` | `dl-satan-tool/patch-job-cancel` | `tools-patch-test.el` | (not listed in governance) |

## Tool distribution

- **Read-only tools** (risk=read): org_read_context, agenda_read, activity_read, bough_read, memory_resonate, memory_show_trace, docs_list, docs_search, docs_read, motive_read, notes_recent, patch_job_status, patch_job_result — **13 tools**
- **Low-risk write tools**: org_update_owned_block, proposal_stage, notify_send, hippocampus_write, inbox_append, memory_mark, sway_border_set, sway_border_reset, patch_job_create, patch_job_cancel — **10 tools**
- **Synthetic**: satan_final — **1 tool**

**Total: 24 tool names** (22 implemented in elisp, 1 synthetic in harness, 1 `satan_final` hook)

## Missing from governance doc

The governance doc's tool table lists 15 tools (not including patch_job_* or notes_recent). The actual implementation has:
- `notes_recent` — not in governance.md tool table
- `motive_read` — not in governance.md tool table
- `patch_job_create`, `patch_job_status`, `patch_job_result`, `patch_job_cancel` — added to mode specs per handover but governance.md may not reflect the current tool surface

  confidence: medium — governance.md may lag behind latest additions (patch tools, notes_recent, motive_read).

## Tool `:modes` field (documentary only)

Per handover.md: "Tool-spec `:modes` is documentary only; the broker does not consult it." The actual gate is the mode's `:tools` list. Tools-atsatan.el adds tools to tick-agent at load time via `dl-satan-tick-register`, bypassing the mode-spec `:tools` list. Two paths for tool allowlisting.
