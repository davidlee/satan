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

## Amendment — the negative leg is withdrawn (RV-007 F-2, F-3, F-17)

The positive leg stands: one entry in `satan-observer--predicates`, uniform
signature, reading the goad day record out of the assembled evidence window.

**The negative leg does not.** Narrowing ack-events by target surface assumed a
usable focus signal underneath it. Three findings say there is none:

- `satan-observer--ack-checked-p` compares the symbol `'ok` to the string `"ok"`
  and is **nil on every production run** ([[ISS-014]]) — so the count it would
  narrow is never taken at all;
- even once fixed, ack-events count only segments *strictly after* the emit (so
  continuous presence reads as absent), only the newest ten segments survive
  assembly, and real telemetry carries `app_id:"goad"` against Emacs and Claude
  window titles;
- presenting the prompt may itself focus the window, which would turn every
  ignored prompt into acknowledgement.

Narrowing a broken count, on evicted data, with mislabelled surfaces, against a
possible self-focus artefact, is not a design. [[DEC-013]] reads non-engagement
from goad's own record instead, and this slice stops changing
`satan-observer-classify.el`'s negative path.

**The `:ignored` analysis in this record's body is also wrong about today.** It
says `:ignored` requires zero focus segments and therefore means the keeper was
absent. Because the ack gate never opens, `classify-negative` in fact awards
`:ignored :low` **unconditionally** to every user-facing intervention that fires
no predicate. That is [[ISS-014]]'s blast radius, not this slice's to fix.


## Amendment, 2026-09-23 — predicates are scoped by kind (RV-007 F-21)

For kind `"ask"` the answer predicate is the only positive predicate; the
ambient three (editor focus, git commit, recentf) do not apply, since none is
evidence of an answer and they would mark a never-presented ask `:worked`. The
negative leg is the kind-`"ask"` branch of `classify-negative` (DEC-013
amendment), not the surface-narrowed ack path, which remains withdrawn.
User-accepted 2026-09-23.
