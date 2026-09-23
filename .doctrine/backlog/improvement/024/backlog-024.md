# IMP-024: Record before side effect for sway, inbox, proposal and patch tools

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Context

SL-017 (PHASE-06, design sec-5) made `notify_send` record before it emits:
`satan-intervention-record` appends `intervention.created` to the run's
transcript before the pop, and the projection comes last. Four other
intervention-creating tools still produce their side effect first and call
`satan-intervention-create` afterwards (design "Out of scope, noted"; SL-017
PHASE-08 EX-2):

| tool | side effect | create call |
|---|---|---|
| `sway_border_set` | `swaymsg` per class | `satan/satan-tools-sway.el:135` |
| `proposal_stage` | `with-temp-file` proposal note | `satan/satan-tools-org.el:140` |
| `inbox_append` | `append-to-file` to `satan-inbox-file` | `satan/satan-tools-inbox.el:99` |
| `patch_job_create` | patch-store row insert | `satan/satan-tools-patch.el:143` |

If the create signals after the effect, the effect happened with no audit
record: the same REQ-003 gap ISS-016 was for alerts.

## Wanted

Apply SL-017's split to each: `satan-intervention-record` → side effect →
`satan-intervention-project` (a failed projection is a note on an `ok`
result). Decide per tool what a failed effect records. REQ-003 stays
`pending` until these land (RV-011 F-11).
