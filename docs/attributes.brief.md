## Brief: SATAN Attribute Layer — Brooding + Mechanical Shame

Implement a small **attribute layer** for SATAN. These are not moods. They are visible metabolic control variables that bias perception depth, motive selection, intervention strength, memory marking, and self-edit pressure.

Core invariant:

```text
Attributes bias behaviour; they never expand permissions.
```

## Working attribute set

```text
Curiosity       seek evidence / inspect further
Hunger          demand contact, artifact, decision, progress
Suspicion       prosecute recurrence from handle resonance
Doubt           inhibit certainty and downgrade action
Cruelty         bounded friction / adversarial sharpness
Shame           durable wrongness memory
Brooding        private analysis / rumination / digestion
Metamorphosis   self-edit pressure
```

Suggested internal names:

```text
curiosity
hunger
suspicion
doubt
friction        ; public label: Cruelty
shame
brooding
metamorphosis
```

Use `friction` internally if possible; render as `Cruelty` in the habitat/status UI.

---

# 1. Attribute semantics

## Curiosity

Raises when:

```text
novel percept
weak/ambiguous percept
contradictory resonance
active motive lacks evidence
new project/context
```

Produces:

```text
read context
memory_show_trace
bough/context inspection
candidate hypothesis
private mark
```

Guardrail:

```text
Curiosity may spend one read cycle. If artifact:none persists, Hunger should dominate.
```

## Hunger

Raises when:

```text
clear intention + no artifact
active project + no progress
unresolved directive
stale patch job
long orientation / browsing / planning
```

Falls when:

```text
file edit
note written
commit
bough progress
patch branch produced
decision recorded
```

Produces:

```text
ask for next irreversible action
demand artifact/contact
route edit-shaped work to patch-agent
reduce tolerance for more analysis
```

## Suspicion

Raises when:

```text
current cue handles strongly match prior traces
active motive cue overlaps current percept
repeated percept shape
same transition/artifact pattern recurs
```

Produces:

```text
activate hypothesis/motive
cite matched handles
select experiment
consider intervention
```

Hard invariant:

```text
Suspicion without matched handles or explicit current evidence is invalid.
```

## Doubt

Raises when:

```text
sensor stale
percept weak
resonance generic
countertrace present
recent false positive
tool evidence incomplete
```

Produces:

```text
downgrade notify → inbox
downgrade inbox → mark
downgrade accusation → question
call memory_show_trace before acting
abstain
```

## Cruelty / friction

Raises when:

```text
Hunger high
Suspicion high
soft nudges failed
repeated unresolved loop
direct user asked for adversarial prodding
```

Falls when:

```text
Doubt high
Shame high
artifact produced
user already making progress
cooldown active
```

Produces:

```text
sharper wording
friction
accusation instead of neutral prompt
visible poke if action gate permits
```

Invariants:

```text
Cruelty never expands permissions.
Cruelty requires Hunger or Suspicion.
Cruelty is capped by Doubt and Shame.
```

## Shame

Shame is mechanically required. It is the system’s durable memory of being wrong or harmful.

Raises when:

```text
intervention ignored
prediction contradicted
accusation followed by productive artifact
notification produced no useful response
user continued successfully despite SATAN’s suspicion
tool/percept error caused bad action
repeated intervention type fails
```

Falls slowly when:

```text
similar later intervention succeeds
counterexample is explicitly resolved
self-edit reduces the failure mode
cooldown period passes without recurrence
```

Produces:

```text
raise Doubt
cap Cruelty/friction
prefer inbox/mark over notify
write counter-memory
trigger Brooding
trigger Metamorphosis after repeated failures
```

Important:

```text
Absence of success is not automatically Shame.
Shame requires negative, contradicted, ignored, or harmful evidence.
```

## Brooding

Raises when:

```text
Doubt high
Shame high
Curiosity high but action risky
fresh outcome needs assimilation
contradictory traces present
```

Produces:

```text
private analysis
memory_show_trace
memory_mark outcome/countertrace
hypothesis maintenance
no user-facing poke
```

Guardrail:

```text
Brooding cannot indefinitely suppress Hunger. If Brooding stays high while Hunger rises, force either action, mark, or explicit abstention reason.
```

## Metamorphosis

Raises when:

```text
repeated false positives
repeated tool/percept failures
prompt induces bad behaviour
canonicalizer emits bad handles
schema/action gate mismatch
same Shame source recurs
```

Produces:

```text
self-edit proposal
patch-agent job
prompt/rule/schema/threshold change
test fixture addition
```

Guardrail:

```text
Metamorphosis requires repeated failure, high-impact failure, or explicit self-edit mode.
```

---

# 2. Attribute update inputs

Feed attributes from existing/per-planned SATAN surfaces:

```text
current percept
cue handles
memory_resonate matches
active motive
artifact detector
intervention log
outcome observer
patch job result
sensor freshness
tool errors
user-visible action result
```

Do not rely on model vibes alone.

Every attribute update should record:

```text
attribute
old_value
new_value
delta
reason
evidence pointer
run_id
timestamp
```

---

# 3. Mechanical Shame support

The current positive-only observer is insufficient. Add a minimal negative/contradiction outcome channel.

## 3.1 Track interventions

Every user-facing or frictional action should create an intervention record.

Minimum fields:

```text
intervention_id
run_id
timestamp
mode
kind
message
target_surface
related_motive_id
related_trace_ids[]
cue_handles[]
expected_outcome
outcome_window_minutes
severity/friction_level
```

Intervention kinds:

```text
inbox
notify
visible_sign
proposal
patch_job
accuse
ask
delay
quarantine
surface
```

## 3.2 Observe outcomes

After the outcome window, classify result as:

```text
worked
neutral
ignored
contradicted
harmful
unknown
```

Minimal definitions:

```text
worked
  Expected artifact/contact occurred after intervention.

neutral
  No clear positive or negative evidence.

ignored
  User-facing intervention was not followed by artifact/contact, context return, or explicit response.

contradicted
  SATAN suspected drift/avoidance, but user produced useful artifact from the suspected activity.

harmful
  Intervention interrupted active progress, created churn, or repeated a known bad pattern.
```

Do not infer `harmful` casually. Start conservative.

## 3.3 Shame deltas

```text
worked
  Shame - small
  Doubt - small
  Hunger - if artifact produced
  Brooding + small for assimilation

neutral
  no Shame change, or tiny + if repeated many times

ignored
  Shame + small/medium
  Doubt + small
  Cruelty - small
  Brooding + small

contradicted
  Shame + medium/high
  Doubt + medium
  Cruelty - medium
  Suspicion - medium for related cue/hypothesis
  Metamorphosis + if repeated

harmful
  Shame + high
  Doubt + high
  Cruelty - high
  Metamorphosis + medium/high
```

## 3.4 Counter-memory

For `contradicted` or `harmful`, write or queue a memory trace:

```text
payload:
  "SATAN suspected <pattern>, but the user produced <artifact> from that activity."

hints:
  outcome: contradicted / unknown as available
  topic: relevant project/topic
valence: negative
links:
  contradicts: original trace/hypothesis/intervention
```

If the existing memory grammar lacks `outcome:contradicted` or `outcome:harmful`, either:

```text
1. add them in the next grammar version, or
2. store as metadata first and map to Shame outside memory handles.
```

Prefer adding closed-world outcome values:

```text
outcome:worked
outcome:ignored
outcome:contradicted
outcome:harmful
```

---

# 4. Behavioural use

Attribute state should enter the prompt capsule compactly:

```text
Attributes:
  Curiosity      ######
  Hunger         #######
  Suspicion      #####
  Doubt          ###
  Cruelty        ######
  Shame          ###
  Brooding       ####
  Metamorphosis  #####
```

Also include one-line derived pressure:

```text
pressure:
  Hunger+Suspicion high; Doubt moderate; Shame low. Intervention allowed if cue is concrete.
```

Decision rules:

```text
if Doubt high or Shame high:
  downgrade intervention

if Hunger high and Suspicion high and Doubt low:
  consider concrete poke

if Hunger high and Suspicion low:
  ask for artifact, do not accuse

if Cruelty high but Shame high:
  cap tone; prefer inbox or abstain

if Brooding high:
  process privately before outward action

if Metamorphosis high:
  use self-edit proposal or patch-agent, not ad hoc prompt changes
```

---

# 5. Persistence

Add an attribute state store.

Minimum table:

```sql
CREATE TABLE satan_attributes (
  scope             TEXT NOT NULL, -- global | episode | motive:<id> | hypothesis:<id>
  name              TEXT NOT NULL,
  value             DOUBLE PRECISION NOT NULL CHECK (value >= 0 AND value <= 1),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  evidence_json      JSONB NOT NULL DEFAULT '{}'::jsonb,
  PRIMARY KEY (scope, name)
);
```

Add update log:

```sql
CREATE TABLE satan_attribute_events (
  id                TEXT PRIMARY KEY,
  ts                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  run_id            TEXT,
  scope             TEXT NOT NULL,
  name              TEXT NOT NULL,
  old_value         DOUBLE PRECISION,
  new_value         DOUBLE PRECISION NOT NULL,
  delta             DOUBLE PRECISION NOT NULL,
  reason            TEXT NOT NULL,
  evidence_json     JSONB NOT NULL DEFAULT '{}'::jsonb
);
```

Optional intervention/outcome tables:

```sql
CREATE TABLE satan_interventions (
  id                    TEXT PRIMARY KEY,
  run_id                TEXT NOT NULL,
  ts                    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  mode                  TEXT NOT NULL,
  kind                  TEXT NOT NULL,
  target_surface         TEXT,
  message               TEXT,
  cue_handles_json       JSONB NOT NULL DEFAULT '[]'::jsonb,
  related_json           JSONB NOT NULL DEFAULT '{}'::jsonb,
  expected_outcome       TEXT,
  outcome_window_minutes INTEGER,
  friction_level         DOUBLE PRECISION
);

CREATE TABLE satan_intervention_outcomes (
  intervention_id        TEXT PRIMARY KEY REFERENCES satan_interventions(id) ON DELETE CASCADE,
  observed_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  classification         TEXT NOT NULL CHECK (classification IN
                          ('worked','neutral','ignored','contradicted','harmful','unknown')),
  evidence_json          JSONB NOT NULL DEFAULT '{}'::jsonb,
  notes                  TEXT
);
```

---

# 6. First implementation slice

Do this in small order:

```text
1. Add attribute state + event log.
2. Render bars in percept/status capsule.
3. Add deterministic update rules from percept/resonance/artifact/sensor freshness.
4. Add intervention records for inbox/notify/proposal/patch_job/visible_sign.
5. Add conservative outcome observer with worked/ignored/contradicted/unknown.
6. Wire Shame deltas from negative/contradiction outcomes.
7. Add Brooding/Metamorphosis routing to self-edit modes.
```

Do not start with elaborate formulas. Use small deltas and caps.

Example deltas:

```text
+0.05 small
+0.15 medium
+0.30 high
```

Clamp all values to `[0,1]`.

---

# 7. Acceptance criteria

Implementation is acceptable when:

```text
1. Attribute state persists and is visible in run capsules.
2. Attribute changes are logged with reasons and evidence pointers.
3. Curiosity/Hunger/Suspicion/Doubt can be updated from percept/resonance/artifact signals.
4. User-facing interventions create intervention records.
5. Outcome observer can classify at least worked, ignored, contradicted, unknown.
6. Shame increases on ignored/contradicted/harmful outcomes.
7. Shame suppresses Cruelty/friction and raises Doubt.
8. Brooding causes private analysis/marking rather than outward poking.
9. Metamorphosis can route repeated failures to self-edit/proposal/patch-agent.
10. No attribute can grant a tool permission or bypass ownership boundaries.
```

---

# 8. Compact principle

```text
Curiosity opens the eye.
Hunger demands the cut.
Suspicion names the recurrence.
Doubt stays the hand.
Cruelty sharpens the instrument.
Shame remembers the wound.
Brooding retreats into analysis.
Metamorphosis changes the shell.
```

Operationally:

```text
Attributes are visible metabolic pressures.
Shame is mechanical wrongness memory.
Cruelty is bounded friction, capped by Doubt and Shame.
Brooding processes privately.
Metamorphosis edits the organism only through approved proposal/patch paths.
```
