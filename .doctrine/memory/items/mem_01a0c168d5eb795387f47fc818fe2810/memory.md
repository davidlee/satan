# How an intervention actually reaches a verdict

Three facts about `satan-observer-classify*` that are easy to get wrong
together, found while researching SL-016 (goad elicitation surface). They
compose: each one gates the next.

## 1. Correlation is the outer gate — and it silently swallows everything

`satan-observer-classify-for-motives` (`satan/satan-observer-classify.el:544`)
ranks motives by intersecting each motive's `:cue` against the **intervention's
percept handles**. When nothing overlaps — *or the motives list is empty* — it
returns `:unknown :reason :no_correlation` and
**`satan-observer-classify` is never called** (`:587-599`).

So an intervention with no correlating motive gets *no* classification at all:
not `:worked`, not `:ignored`, not `:neutral`. No predicate runs. The negative
path does not run.

Compounding it: **no production call site passes `:cue-handles` or
`:related-motive-id`** to `satan-intervention-create` — both default to
`(vector)` / `:null` (`satan/satan-intervention.el:384-385`). Correlation rides
entirely on `percept_handles`, which is auto-populated from ctx
(`satan/satan-intervention.el:386` ← `satan/satan-run.el:250`).

**Consequence:** "user-facing kinds classify `:ignored` when unanswered" is
true only *past this gate*. Do not plan an engagement/disengagement signal on
the negative path without first deciding how the intervention correlates.

## 2. Predicates run first; the negative path is the else-branch

`satan-observer-classify` (`:430`) maps over `satan-observer--predicates` and
short-circuits (`:487-494`):

```elisp
(if firers
    (list :classification :worked
          :confidence (if (> (length firers) 1) :high :medium) ...)
  (satan-observer-classify-negative intervention after))
```

`satan-observer--predicates` (`:409-419`) is an **ordered alist of keyword →
function**, uniform signature `(baseline after motive intervention) → boolean`,
first-fire-wins for the recorded `:predicate` slot. Three today:
`:editor_edit_in_window`, `:git_commit_observed`, `:fs_recent_delta`.

**Adding a positive signal = one alist entry + one function of that signature.**
Confidence rises to `:high` automatically when two or more fire.

This matters because `satan-observer--count-ack-events` (`:279-290`) counts
**any** focus segment after the emit — *"v1 does not narrow by surface"*. So on
the negative path, a user who *did* engage lands `:unknown :low`
(`:330-335`), not `:worked`. A new predicate short-circuits past that entirely.

## 3. The manual writer cannot express a positive outcome

`satan-intervention-write-manual-outcome`
(`satan/satan-intervention.el:582`) enforces two closed sets at entry:

- `satan-intervention--manual-classifications` = `("harmful" "contradicted")`
  (`:484-488`), enforced `:614-616`.
- `satan-intervention--manual-marked-by` = `("interactive-command"
  "notes-directive")` (`:490-492`), enforced `:617-619`.

Its docstring is the rule: *"Auto kinds (`worked`/`neutral`/`ignored`/`unknown`)
belong to the auto classifier and must not reach here."* Downstream
`--manual-evidence` (`:494-516`) and `--counter-memory-payload` (`:534-549`)
both hard-`cond` on those two, so a `"worked"` write fails three times. The
disjointness is guarded on the other side too, by
`satan-observer--assert-auto-classification`
(`satan/satan-observer-classify.el:354-360`).

**So: route a negative human override through the manual writer (adding a
`marked-by` member is cheap and correct). Route a positive signal through a
predicate.** Reaching for the manual writer to record success means amending an
invariant that exists specifically to keep the two apart — and touching
authority-ledger row 4 (append-only audit), already flagged ⚠ as a latent
dual-write hazard.

## Related

- [[mem.pattern.satan.sensor-watermark-format]] — the adjacent trap in the
  probe family.
- [[mem.fact.satan.green-is-not-green]] — a test that never runs reports green;
  the same shape of silent success as the `:no_correlation` swallow.
