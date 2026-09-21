# Why this assumption is load-bearing

[[DEC-005]] rules that SL-016 adds **no new stateful layer**: the durable record
of a question is its existing intervention row, the queue file is a disposable
projection, and the keeper's answer comes back in goad's own day record. That
whole argument — and with it the discharge of the ADR-018 D5 versus POL-001
tension — rests on one thing being true: that the answer can be **attributed**
to the question without a side table to hold the mapping.

Attribution requires `intervention_id` to survive the round trip:

```
intervention row (satan_memory)          ← the record
   │  intervention_id
   ▼
queue file (state root, whole rewrite)   ← DEC-010, the projection
   │  intervention_id
   ▼
backend.py pending() merge               ← the corpus-side change
   │  intervention_id
   ▼
goad renders the question                ← no host change (the slice's constraint)
   │  the keeper answers
   ▼
day record entry (JSON, DEC-009)         ← the answer
      intervention_id  ◄── THIS
```

If the id cannot be carried through, the design needs somewhere to hold the
mapping from rendered item back to intervention — which is exactly the new
stateful layer DEC-005 avoids, and the ADR-018 D5 tension reopens.

# Why it is believed

- The day record is `backend.py`'s own private persistence. Its module docstring
  is explicit: *"items, sections, slots and the record format are all this file's
  business"*, and the goad host never reads it.
- `backend.py` already threads opaque identity through the host today. Its
  docstring again: *"which item a button belongs to is carried in the option id
  (`yes:meds`), because the host mints view ids and will not carry ours."* So the
  pattern of smuggling backend-owned identity through a host that does not care
  is already in use and already proven.
- goad SPEC-003/R-11 makes `data` opaque and delivered to the backend whole, so
  the doorbell leg can carry identity too.

# Why it is not yet evidence

Nothing has been implemented. The inference is strong but it is inference: the
option-id precedent shows identity can ride *into* an answer, and what SL-016
needs is that it also rides *out* into the record. Those are the same mechanism
but not the same line of code, and `backend.py` has no tests, no fixtures and no
check recipe (slice R2) — so nothing would catch it silently not happening.

Promote to evidence when the round trip is demonstrated.
