# IMP-028: Move the goad goldens drift check into the corpus; public tests stop reading ~/satan

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Context

`satan-goad-integration/goldens-match-backend` (SL-016 PHASE-08 VT-43) runs
the live corpus `~/satan/goad/goldens.py` against `backend.py` and compares
the output with the goldens committed here. So a public test depends on
private, freely-edited code: any protocol change in `backend.py` fails SATAN's
gate until the goldens are regenerated. The user's stance (2026-09-24): tests
that break whenever production code or data is updated are not wanted.

Done so far (option A, `69bc33d` / corpus `390df05`): `goldens.py` swaps in
a stand-in checklist, so checklist *data* edits no longer break the test and
no private checklist reaches the public fixtures. Protocol *code* edits still
do.

## Proposal (option B)

- The public repo tests against the frozen goldens only; no public test reads
  `~/satan`. The corpus-integration tests that `skip-unless` the corpus
  (VT-1, VT-42, VT-61 also run the live backend) need the same treatment
  — decide per test whether it is a contract test (frozen goldens) or a
  corpus test (moves to `~/satan`).
- The drift check moves to the corpus: e.g. `just goldens-check` in
  `~/satan` regenerates into a temp dir and diffs against
  `~/dev/satan/satan/test/goad-fixtures`, run when `backend.py` changes.
- Regenerating the goldens stays a deliberate act that names the producing
  corpus commit.

## Related

- Git history on the public `origin/main` still holds the old real checklist
  ids (`528079c` … `d14deca`); no labels or medication names. The user has
  not asked for a history rewrite.
