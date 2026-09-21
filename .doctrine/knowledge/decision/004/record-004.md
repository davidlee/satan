## Why the cheap routes cannot substitute

The chain that produces a percept handle is short and entirely determined:

```
satan-percept-build            (satan/satan-percept.el:65-67)
  └─ satan-memory-evidence-assemble ctx opts   → evidence window
       └─ satan-memory-canon-canonicalize      → (:handles … :handle_sources …)
            └─ dispatches satan-memory-canon--rules over the evidence
```

and the chain that consumes one, at classification time:

```
satan-observer-classify-for-motives   (satan-observer-classify.el:544)
  └─ satan-observer--intervention-percept-handles   (:500-509)
       └─ reads run_dir/bundle.json → :percept → :handles
  └─ intersect against each motive's :cue → highest overlap wins
       └─ no overlap ⇒ :unknown :no_correlation, and
          satan-observer-classify is NEVER CALLED
```

A probe writes numeric pressure to Postgres through `satan-attribute-enqueue`; nothing it reads enters the evidence window. A tool result is produced during the run, after the percept is already frozen. Neither can put a token in `:handles`.

## The correction this makes to the research round

Research delta 4 and X3 say PERCEIVE is a three-way route choice with different costs, and that the three "are not exclusive". True as far as it goes, and it misses that **only one of the three is load-bearing**. The evidence route is not the expensive option among equals; it is the only option that makes the slice's keystone demonstrable.

It also narrows X2. X2 says "the design must decide how a goad ask correlates". The decision space is smaller than it looks, because:

- **`:cue-handles` does not help.** `satan-intervention-create` accepts `:cue-handles` and persists it to `cue_handles_json` (`satan/satan-intervention.el:385`), and the correlator does not read that column — it reads `bundle.json`. The field feeds resonance via `satan-intervention--counter-memory-handles` (`:518`), not classification. Passing it on the ask changes nothing about whether the ask classifies.
- So correlation can only be arranged by **putting goad-shaped handles in the percept**, which is this decision, or by **changing the correlator**, which is a different slice.

## Leftover for inq-1

This decision creates the substrate; it does not by itself guarantee an ask correlates. A live motive still has to carry a `:cue` token that matches a goad handle. Whether the ask tool should *check* that at emit time and fail closed is inq-1.

## Correction — the handle namespace is not free (2026-09-21, same design run)

As first recorded, this decision's consequences said a new `goad:` prefix would
join the thirteen namespaces in use. That is wrong, and the consequence list has
been corrected in place.

`satan-motive--admitted-namespaces` (`satan/satan-motive.el:83-92`) is a **closed
allowlist**:

```elisp
'("app" "surface" "surface_transition" "domain_kind" "domain_transition"
  "bough_event" "bough_node" "bough_project" "artifact"
  "topic" "phase" "focal_app")
```

`satan-motive--cue-admittable-p` (`:147-156`) requires at least one cue handle
whose leading namespace is in that set. The docstring gives the reason: *"Without
≥1 handle from this set a motive triggers on every tick — defeats the cooldown
floor."* A motive whose cue names only `goad:` handles is `:invalid-cue`, parses
dormant, and never reaches the correlator at all.

So the canon rule this decision calls for must emit into an already-admitted
namespace. `app:goad` and `surface:goad` both name the surface honestly and are
admitted; per-item subject matter goes to `topic:`. Minting `goad:` is only
admissible as a *supplementary* handle alongside an admitted one, never as the
sole basis a motive can cue against.

Two further points the correction pins:

- **Cue tokens are full canon handles, not bare words.** `satan-motive--parse-cue`
  (`:132-137`) splits the `:cue:` footer on whitespace, and
  `--cue-handles-well-formed-p` (`:139-145`) requires every token to match the
  canon handle regex. A motive cues `app:goad`, not `goad`.
- Widening the allowlist is an edit to a closed set that exists to protect the
  cooldown floor. It is not a slice edit, and this slice does not need it.

## Amendment — the handle's trigger moves to the queue file (RV-007 F-6)

The route decision stands: only the evidence assembler plus a canon rule can put
a handle in the percept, and that is what correlation needs.

Two corrections from the adversarial review.

**The trigger was deadlocked.** This decision's body said the canon rule must
emit its goad handle from *the presence of the day record*, so it would not
depend on window focus. But `backend.py` `load()` returns `{}` when the file is
absent (`:69-74`) and `save()` runs only on a `respond` request (`:153`) — so no
day record exists until the keeper answers something. SATAN could therefore never
be the first goad interaction of the day, which is most of what an autonomous
producer is for.

The rule now keys on **SATAN's own queue file**, which exists exactly when there
is something to ask. The handle then means *"SATAN has a question outstanding"*
rather than *"goad has state today"* — the more useful thing for a motive to cue
on in any case.

**One sentence was overstated (F-16).** "Handles exist only for what reaches the
evidence window and has a rule to name it" is false as an absolute: canon also
emits context- and hint-derived handles (`satan-memory-canon.el:429` and the
normalized-hints path). The claim that carries the route decision is narrower and
is the one to rely on — *no probe and no post-percept tool can contribute a
handle for that run*.