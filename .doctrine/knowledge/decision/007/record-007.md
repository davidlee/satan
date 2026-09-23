## The gate, and why hoping is not a strategy

```
satan-observer-classify-for-motives      (satan-observer-classify.el:544)
  │
  ├─ handles ← satan-observer--intervention-percept-handles   (:500-509)
  │             reads run_dir/bundle.json → :percept → :handles
  │             ── and NOTHING else. Not cue_handles. Not percept_handles.
  │
  ├─ ranked  ← satan-observer--rank-motives-by-overlap
  │             |cue ∩ handles| descending, file order breaks ties
  │
  └─ (null ranked) ⇒ :unknown :confidence :low :reason :no_correlation
                      └─ satan-observer-classify IS NEVER CALLED
                         no predicate runs · classify-negative never runs
```

Everything SL-016 wants to demonstrate lives on the far side of `ranked` being non-nil.

## Why the emit-time check is exact

The same list flows to all three places:

```
satan-percept-build ──→ percept :handles
     │
     ├─→ run ctx :percept-handles          (satan-run.el:250)
     │      └─→ ask tool reads it here, at emit
     │      └─→ satan-intervention-create reads it here too
     │            (satan-intervention.el:386) → percept_handles column
     │
     └─→ bundle.json :percept :handles
            └─→ the correlator reads it here, at maturity
```

So `|cue ∩ ctx:percept-handles|` computed at emit and `|cue ∩ bundle-handles|`
computed thirty to sixty minutes later are the same arithmetic over the same
numbers. The only free variable is the motive file.

## What `:cue-handles` is actually for

Worth stating plainly, because it is the obvious wrong turn. `satan-intervention-create`
accepts `:cue-handles`, persists it to `cue_handles_json` (`:385`, `:168`), and
**no production call site passes it**. It is tempting to read that as the hook the
correlator forgot to use.

It is not. The correlator never reads the column. `cue_handles` feeds
`satan-intervention--counter-memory-handles` (`:518-532`) — the resonance path, so a
counter-memory inherits the intervention's handles. Passing it is worth doing for
auditability and resonance. It will never make an ask correlate.

## The suppression signal

The fail-closed branch deserves more care than a `nil` return. RFC-016's diagnosis
is that SATAN has *no sense organ for being ignored*. An ask tool that quietly
declines to ask whenever no motive correlates creates the same blind spot one level
up: the system would be mute and unable to notice its own muteness, and the symptom
— nothing in the goad window — is indistinguishable from a keeper who answers
everything promptly.

So suppression is an outcome to record, not an early return. Where it lands is
inq-6's business; that it must land somewhere is settled here.

## The race this leaves open

`tick-pulse` carries `motive_read` **and** `motive_replace`, and `motive-write`
among its capabilities. Between an ask at T and its maturity at T+30..60min, SATAN
may rewrite the motive that justified the ask. The correlator then finds no overlap
and returns `:no_correlation` — the ask is orphaned by its own author.

Nothing in this slice can prevent that without changing the correlator, which is out
of scope. What this decision does is make it **visible**: `related_motive_id` and
`cue_handles` recorded at emit are the before-picture, and the verdict's `:motive_id`
is the after. A verifier comparing them detects every decorrelation. IMP-002 already
scopes exactly that cross-check and should gain this as a case.

## Amendment — the claim is narrowed, and the gate is made to mean something (RV-007 F-4, F-5)

[[DEC-013]]'s reframe does **not** rescue this decision. A goad-derived predicate
still runs inside `satan-observer-classify`, which still sits behind
`satan-observer-classify-for-motives`, so motive correlation remains the outer
gate on every classification. Both findings survive intact.

### F-5 — the gate did not correlate the question to the motive

As first written, the gate intersected live motive cues against **ambient**
percept handles. Neither the question nor its subject took part. So a generic
`app:goad` cue admitted *any* question on *any* subject, and where several
motives carried the handle, file order picked which was credited
(`--rank-motives-by-overlap` breaks ties by `:order`). The gate proved *some
motive overlaps the ambient percept* — not what this record's title claims.

**The fix is a principle, and the machinery forces it:** *SATAN may only ask
about something already in its perceptual field.* The percept is frozen at spawn,
before any question exists, so a question-specific handle can correlate **only**
if the question is derived from what is already perceived.

Concretely, the ask tool requires:

1. the question to name a handle present in ctx `:percept-handles`; and
2. **that** handle — not merely `app:goad` — to appear in the winning motive's cue.

The gate then proves what it was always claimed to prove, and the tie-break
concern dissolves because the overlap is on a specific subject.

### F-4 — the loop is not closed by construction, and the design will say so

The observer rereads **live** motives on every pass
(`satan/satan-observer.el:383`) and ranks them against the bundle
(`satan-observer-classify.el:584`). It never consults the persisted
`related_motive_id` or `cue_handles`. So an ask that passed the emit-time gate
can still mature `:no_correlation` if `motive_replace` touched the motive in
between — and `tick-pulse` holds exactly that tool.

Recording enough to *detect* a broken loop is not the same as having an unbroken
one, and the original phrasing ("correlate by construction") overclaimed. Two
changes:

- correlation is asserted **at emit** and nowhere else;
- a goad ask that matures `:no_correlation` becomes a **perceptible** event
  through the same channel as suppression ([[DEC-011]]), so a broken loop is
  visible rather than silent — this slice's own thesis applied to itself.

Making the correlator honour the persisted motive id is the real fix. It changes
shared classification semantics for every intervention kind, so it goes to the
backlog as its own item rather than into this slice.


## Amendment, 2026-09-23 — maturity reads the emit-time decision for kind "ask" (RV-007 F-28)

Goad-minted handles (`app:goad`, `topic:<Subject>`) enter later percepts, and
motives may cue on them. Under overlap ranking against the whole percept, such a
motive outranks the subject's motive: at emit it suppresses every ask on another
subject; at maturity it takes the credit (F-5's misattribution again).

So for kind `"ask"` only emit ranks. The tool considers only motives whose cue
holds the subject, ranks them by overlap with the percept (ties by file order),
and records the winner as `related_motive_id` with the subject as `:cue-handles`.
At maturity the correlator credits the live motive with that id when it is not
dormant and its cue still holds the subject; otherwise `:no_correlation`, which is
perceptible. Other kinds keep live ranking; honouring the persisted id for all
kinds stays backlog work. This supersedes the alternative above that called any
use of `cue_handles` by the correlator a cross-kind change: this use is
kind-scoped. User-accepted 2026-09-23.
