---
name: satan-architecture
description: SATAN architecture — trust/data flow and broker/harness/model/tool/output/state layers
metadata:
  type: design
  topic: satan
  status: canon
  updated_at: 03398479
  verified_at: 03398479
---

# SATAN — Architecture

Companions: [[satan-governance]] (philosophy + policy), [[satan-protocol]] (wire spec).

## Architectural center of gravity

```text
systemd / manual invocation
        ↓
Emacs broker            (trusted authority)
        ↓
jailed harness/model    (untrusted reasoning)
        ↓
JSONL protocol          (membrane)
        ↓
broker-owned tools and output handlers
        ↓
org/denote/bough/local surfaces
```

Emacs is the trusted local broker. Org/Denote are the canonical
personal text substrate. `bough` is a graph/cache/metadata/index layer
around that substrate, not the primary owner of reality. The model is
a reasoning engine, not trusted with direct authority.

## Conceptual layers

### Invocation
Defines when and why SATAN runs (morning, evening, MOTD, weekly review,
manual self-edit). Explicit, scheduled, inspectable, boring. SATAN does
not decide for itself when to wake up except through mechanisms the
user has explicitly installed.

### Broker
Trusted authority. Owns mode resolution, context assembly,
prompt/hippocampus loading, permission profile selection, process
lifecycle, JSONL handling, tool dispatch, action validation, output
handling, audit logging. The broker enforces policy; the model
proposes.

### Harness adapter
Talks to a model or model-running environment (OpenRouter, gptel,
pi.dev, zerostack, local model runner, fake test harness).
Replaceable. Translates between the SATAN protocol and the
harness-specific interface. No adapter should become the canonical
definition of SATAN behaviour.

### Model
Performs reasoning. Receives model-facing prompts, relevant hippocampus,
selected context, tool manifest, output contract. Emits tool calls,
logs, final structured output. Must not receive ambient authority;
can only request named capabilities through the broker.

### Tool
Broker-owned capability. Not "whatever shell command the model wants."
Named, validated operation with risk level, capability requirement,
argument schema, mode allowlist, implementation handler, model-facing
description. The description is advisory; the broker-side handler and
policy are authoritative.

### Output
Final model output is not automatically trusted. The output handler
validates, classifies, and routes requested effects: apply low-risk
owned writes; stage proposals; reject invalid actions; record failures;
notify locally if permitted; update audit artifacts. Mode-specific.

### State
Local, text-first, inspectable. ROM prompt fragments, mode prompts,
tool descriptions, hippocampus, proposals, run logs, owned daily-note
blocks, MOTD/status surfaces. Favour files the user can read, diff,
grep, review, and version.
