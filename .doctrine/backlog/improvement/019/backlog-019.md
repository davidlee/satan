# IMP-019: Extend the @satan scan to the relocated corpus at ~/satan

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

SL-015 design **OQ-3**, promoted out of the slice at reconcile (RV-005 F-5).

`satan-tools-atsatan-root` defaults to `satan-notes-root` — the whole user notes
corpus — and the `@satan` scan sweeps it for markers the user has left for
SATAN. Until SL-015 that scan reached SATAN's own corpus too, by accident of
nesting, and had to carry an `'("!**/satan/**")` exclude glob to undo it. SL-015
moved the corpus to `~/satan` and retired the glob (design D8).

So the scan now covers exactly the user's notes, which is coherent. The question
is whether it *should* also cover `~/satan`.

**The argument for.** `proposals/` and `motives.org` are precisely where an
`@satan` marker would be dropped — they are the working surfaces between the
user and SATAN, and both are now outside the scanned tree. A marker left there
is invisible.

**The argument against.** `@satan` is a channel *from the user to SATAN*, and
`~/satan` is SATAN's own corpus. A marker SATAN wrote to itself is not a
message; folding the corpus back into the scan risks SATAN answering its own
notes.

**Shape of the work.** Not a default change: `satan-tools-atsatan-root` is one
root and the scan walks one tree. Covering both means either a list-valued root
(and every consumer of the singular updated) or a second scan pass unioned at
the call site (`satan-tools-atsatan.el:154`). Decide the semantics first — which
of the two trees a found marker is attributed to, and whether corpus markers are
answered differently — then the mechanism.

Relates to [[POL-001]] only insofar as `@satan` is broker-side today; it is not
an extraction question.
