# REV REV-003 — reconcile SL-016

Revision (ADR-013) — a pending revise-intent against authored governance/spec
truth. The structured `[[change]]` payload lives in the sister `revision-NNN.toml`;
this prose companion carries the rationale and the free-text before/after excerpts
for prose-body section edits.

## Rationale

POL-001's seat test asks whether a module "uses the editor as an editor", and
its thin-shell rationale rests on "the human's editing surface is where their
output lands and where the keeper approves it". SL-016 added a second human
surface that is not the editor: goad, a standalone GUI in its own window. The
policy does not say how to treat one. SL-016 answered No for its modules
(DEC-008) and deferred the policy text to reconcile instead of widening it in
implementation. The keeper chose to clarify, not widen (2026-09-24, reply
"agreed, A").

### Change — POL-001 `## Scope`, after the seat-rationale paragraph (modify)

Before: *(no text; the paragraph ends "…none of them urgent.")*

After, a new paragraph:

> A human surface outside the editor does not earn the seat. goad (SL-016)
> presents to the keeper in its own window, so its SATAN-side shells —
> `satan-goad.el` and `satan-tools-goad.el` — answer **No** however thin they
> are: recorded tenants, not residents (DEC-008), travelling with the
> observer/memory extraction (IMP-009, IMP-007). Absent a trigger, they stay.

Plus a dated entry under `## Amendments`.

## Reconcile narrative (SL-016)

- [RV-018 F-8]: POL-001's seat clause did not cover a non-editor human
  surface. It is now clarified: such surfaces' shells are No-branch tenants.
  No seat list changes, and no extraction is triggered.
