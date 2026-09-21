## One datum, three lifetimes

| where | role | lifetime | whose storage |
|---|---|---|---|
| goad day record | arrival — the keeper's reply as written | the day | goad's own, corpus-tracked (DEC-005) |
| percept via evidence + canon rule | visibility and correlation for the run | one run | none new (DEC-004) |
| memory trace | durable human-sourced evidence, resonatable | indefinite | the memory substrate |

No tier holds what another tier is responsible for, so none of them can disagree in a way that matters. This is the SPEC-001 REQ-009 no-dual-enforcement shape applied to data rather than to authority.

## Why not the inbox

The slice already named `satan-tools-inbox.el` under deliberate non-duplication: *"the existing SATAN put something in front of you surface. If this slice builds question presentation, the inbox is the incumbent and a second one is a parallel implementation."*

The same logic runs the other way. The inbox is SATAN-to-human. An answer is human-to-SATAN, which is perception, and perception has a substrate already — the percept and the memory store. Putting an answer in the inbox would mean SATAN writing to itself through a surface built for writing to the keeper.

## Why the answer earns a trace

The observer's positive predicates today are `:editor_edit_in_window`, `:git_commit_observed` and `:fs_recent_delta` — all ambient inference from telemetry. A goad answer is the first time the keeper tells SATAN something directly and deliberately. Treating it as transient run data and discarding it at run end would throw away the highest-signal input the system has ever had, in a slice whose entire premise is that SATAN is starved of exactly this.

## The suppression channel, and why it needs a throttle

DEC-007 requires suppression to be observable: an ask tool that silently declines to ask whenever no motive correlates would leave SATAN unable to notice its own muteness — the RFC-016 failure one level up.

A sensor alert is the right channel because suppression is a *condition of the organism*, not an event in the world, and the alerts sensor already feeds the percept. But the condition is persistent by nature: if no motive names `app:goad`, it holds on every tick until a human writes one. `tick-pulse` draws roughly five ticks in eight, every ~30 minutes. Unthrottled, the signal that SATAN cannot ask becomes the noise that teaches the keeper to ignore it — the precise pathology RFC-016 is about. The alert needs a cooldown floor like every other alert, and the design should say so rather than discover it in production.