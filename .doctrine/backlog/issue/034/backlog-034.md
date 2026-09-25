# ISS-034: notes_recent lists files notes_read cannot open, with no openability tell

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Raised by the SL-020 PHASE-02 VH-1 live verification (2026-09-25).

## The observation

```
notes_recent(72h) -> journal/20260925T000000--2026-09-25-friday__journal.org
                     justfile
                     flake.lock
notes_read("justfile")   -> (error . "not a note file: justfile")
notes_read("flake.lock") -> (error . "not a note file: flake.lock")
```

The two discovery doors disagree about what a "note" is: `notes_recent` surveys
**everything that moved** under the root, `notes_read`/`notes_grep` open only
`.org`/`.md`/`.txt` (**DEC-032**). Following the top hit on faith can therefore
land on `not a note file`.

## Why this is not simply "filter notes_recent"

Filtering by extension would **hide** the user's own non-note work in the notes
repo (a `justfile`, a lock file, a script they just wrote) from the tool whose
entire job is to say *what they touched*. The narrower door is right; the
missing thing is the **tell**.

Nor is `:ext` the tell it looks like: it is `nil` for an extensionless name
(`justfile`) but `"lock"` for `flake.lock`, so the caller has to know the
extension allowlist to interpret it — i.e. it has to already know the answer.

## Options

1. **`:openable` (boolean) per entry** — one predicate, derived from the same
   `satan-tools-notes--openable-extensions` list the read door uses, so the two
   surfaces cannot drift. Preferred: it makes the door's rule visible at the
   point of discovery instead of inferable.
2. **A warning sentence in `~/satan-corpus/tools/notes_recent.md`** — cheaper,
   but leaves the model to pattern-match filenames against a rule stated
   elsewhere, which is the failure mode DEC-032's equivalence sentences were
   meant to end.

Doing both is defensible; doing (1) without (2) is probably enough.

## Related

Touches the SL-020 pair (`notes_read`, `notes_grep`) and **DEC-032**'s door width.
The `satan-tools-notes.el` module stays the single owner of the extension list —
whatever is done here must consume it, never restate it.
