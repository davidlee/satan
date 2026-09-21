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