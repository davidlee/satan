## The loop, once both legs land

```
                     satan-observer-classify
                              │
              predicates run FIRST, first-fire-wins
                              │
   ┌──────────────────────────┴───────────────────────────┐
   │ :goad_answer_observed fires                          │ none fire
   │   the keeper answered this ask                       │
   ▼                                                      ▼
:worked                                     satan-observer-classify-negative
(:high if it co-fires                                     │
 with a git commit)                    ack-events, NARROWED to target surface
                                                          │
                        ┌─────────────────┬───────────────┴────────────┐
                 goad focus, no answer   no focus anywhere      focus elsewhere,
                  (Later / Enough)        (keeper away)          none on goad
                        ▼                     ▼                       ▼
                 :unknown :low           not :ignored            :ignored :medium
                 engaged, unanswered      — absent, unassertable   ◄── THE KEYSTONE
```

## The positive leg

One entry in `satan-observer--predicates`, one function of the uniform
`(baseline after motive intervention)` signature. It reads the goad day record
out of `after` — the assembled evidence window — which DEC-004 already puts
there, so the predicate needs no database query and no side channel. It fires
when the record holds an entry carrying this intervention's `intervention_id`
with a `value` present and an `at` strictly after `intervention_emitted_at`.

Confidence rises to `:high` automatically when it co-fires with another
predicate, which is the correct behaviour: a keeper who answered *and* committed
is stronger evidence than either alone.

This is the first predicate in the alist that is direct evidence rather than
ambient inference. The other three ask whether the editor focused, whether a
commit landed, whether a file was visited. This one asks what the keeper said.

## The negative leg, and why it was inverted

`satan-observer--count-ack-events` (`satan-observer-classify.el:278-290`):

> *"v1 does not narrow by surface — any focus segment in the window counts (per
> outcome-semantics §8 deferral). A stricter surface mapping is a follow-up."*

and `classify-negative` (`:300-345`) awards `:ignored` only on
`ack-events-found = 0`. Composed, during any normal working day:

| keeper | focus segments | verdict today | what it should say |
|---|---|---|---|
| answered | yes | (predicate fires) | `:worked` |
| pressed Later | yes | `:unknown :low` | `:unknown :low` — correct |
| present, never looked | yes, elsewhere | `:unknown :low` | **`:ignored`** |
| away from the machine | none | `:ignored :medium` | not `:ignored` — absent |

The two rows that matter are both wrong, and they are wrong in opposite
directions. The slice's verification-intent item 3 — *an unanswered prompt
matures and classifies `:ignored` through the existing observer path* — would
have passed only by testing the keeper being away, which is not disengagement.

## Why this stays contained

The narrowing is keyed by a surface mapping that starts empty for every existing
kind. A kind with no mapping counts any segment, exactly as today. So no
currently-emitted intervention reclassifies, and the blast radius is the kinds
this slice introduces. That is what makes it a slice-sized change to a shared
classifier rather than a recalibration of the whole observer.

## The handle timing trap

Worth stating because it is easy to get backwards. Canon already emits `app:goad`
and `surface:<…>` from `current_window.app_id`. But that fires when goad *has*
focus — and SATAN asks when it does not. So the free handle is exactly absent at
the moment correlation is evaluated for a new ask. DEC-004's canon rule must emit
a goad handle from the day record's presence, not from the window. The free one is
a bonus at answer time, not the mechanism.