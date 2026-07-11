## Design note: global attributes, pattern-local scars

Do **not** make SATAN attributes pattern-specific.

Attributes are a closed, organism-level control surface:

```text
Curiosity
Hunger
Suspicion
Doubt
Cruelty/friction
Shame
Brooding
Metamorphosis
```

They describe SATAN’s current metabolic state, not the state of each pattern. They should remain global, possibly with episode-local deltas later.

Patterns are open-ended and numerous:

```text
docs-after-error
browser-orbit
patch-agent-failure
tick-agent-overreach
bough-stale-active
self-edit-loop
note-rewrite-risk
```

Giving every pattern its own attribute vector creates an unnecessary `pattern × attribute` matrix. Avoid that.

## Recommended model

```text
current percept
→ matching patterns by cue handles
→ pattern-local history/scars
→ global attributes
→ action gate
→ outcome
→ update pattern history + global attributes
```

Compact principle:

```text
Attributes describe SATAN.
Patterns describe what SATAN is looking at.
Scars describe what happened when SATAN acted on a pattern.
```

Or, in organism terms:

```text
Global attributes are the animal’s metabolism.
Patterns are its prey-shapes.
Scars are where the prey bit back.
```

## Pattern records

Pattern records should have local policy/history fields, not full attribute state.

Suggested shape:

```text
pattern_id
label
cue_handles[]
default_intervention
intrusion_ceiling
cooldown_until

success_count
ignored_count
contradicted_count
harmful_count
last_seen_at
last_tested_at
last_outcome

scars[]
notes
enabled
priority
```

Optional later:

```text
confidence
motive_biases
```

## What updates what

Outcomes should update both:

```text
1. global attributes
2. implicated pattern records
```

Example:

```text
contradicted intervention
  → global Shame ↑
  → global Doubt ↑
  → global Cruelty/friction ↓
  → pattern.contradicted_count += 1
  → pattern.scars append evidence
  → pattern.intrusion_ceiling may be lowered
```

Example:

```text
worked intervention
  → global Hunger ↓ if artifact produced
  → global Shame ↓ slightly or unchanged
  → pattern.success_count += 1
  → pattern.last_outcome = worked
```

## Pattern-specific consequences

Keep these local to the pattern:

```text
confidence
success/failure counters
cooldown
intrusion ceiling
preferred intervention
blocked interventions
last outcome
scar notes
cue handles
```

Keep these global:

```text
Curiosity
Hunger
Suspicion
Doubt
Cruelty/friction
Shame
Brooding
Metamorphosis
```

## Optional later: motive-local bias

If needed, add small local bias terms, not full vectors:

```text
motive: implement-memory-substrate
  hunger_bias: +0.2
  suspicion_bias: +0.1
```

These bias global state while the motive is active. Use sparingly.

## Implementation recommendation

For v1:

```text
- implement global attributes only
- implement pattern records with scars/counters/cooldowns
- outcome observer updates both
- action gate combines:
    current percept
    matching patterns
    pattern scars/cooldowns
    global attributes
```

Do **not** implement:

```text
pattern-specific attribute vectors
hypothesis-specific full attribute state
attribute matrix by mode/tool/pattern
```

This preserves a small closed affective system while allowing unbounded pattern growth.
