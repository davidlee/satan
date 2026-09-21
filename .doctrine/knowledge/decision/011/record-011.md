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

## Amendment — the suppression channel and the trace were both asserted, not checked (RV-007 F-8, F-9)

### F-8 — sensor alerts cannot carry suppression

Alerts are derived **pre-spawn** from a closed sensor-status table covering only
current-window, focus and browser faults (`satan/satan-sensor-alerts.el:102`,
`:322`). Goad suppression happens **later**, inside a model-invoked tool handler.
There is no enqueue API, no status source, and — because this record also said
the suppression is not audited — no durable trace for the next tick to read.
Verification item 6 was not achievable as written.

**Verified replacement:** enqueue an **attribute** from the tool handler via
`satan-attribute-enqueue`, following `satan/satan-tools-hippocampus.el:109`,
which is a tool handler doing exactly that. Confirmed by read this time rather
than assumed.

It is also the right shape. Suppression is a persistent *condition of the
organism* — no motive names the subject, so it holds until a human writes one —
not an event in the world. That is what the attribute layer is for, and the
cooldown this record demanded becomes a property of attribute semantics instead
of bespoke throttle code.

Two constraints to carry into the plan:

- attributes reach the capsule as **pressure**, not readable text, so any detail
  needs a second sink;
- [[ISS-011]] records that `satan-attrd` **rejects** unknown sensor outcome
  reasons, so a new reason value needs attrd support — a cross-repo dependency.

`satan-sensor-alerts.el` leaves the affected surface; `satan-attribute.el` joins
it. The same channel carries a matured `:no_correlation` ([[DEC-007]]).

### F-9 — the memory trace does not hold the answer

The observer's trace records intervention id, motive id, predicates,
classification and confidence (`satan/satan-observer.el:131`, `:141`) — **not**
the question and not the submitted value. It writes via
`satan-memory-store-mark` directly (`:149`), so it is not dispatched under the
mode's `memory-write` capability either. Both halves of this record's third
landing place were wrong.

The answer trace is now an **explicit write by this slice**, carrying the
question and the value, on a stated path. If that is not worth its cost the
honest alternative is to drop the third landing place and say the answer lives
in the day record and the percept only — but that will be a decision rather than
an assumption.