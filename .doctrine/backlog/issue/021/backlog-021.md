# ISS-021: Observer crosses_midnight guard compares UTC row dates, tripping for every intervention emitted 00:00-09:59 local

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Defect

`satan-intervention-pending` selects `ts::text`, which psql renders in the
session TimeZone. The `satan_memory` server is `GMT` (`show timezone` → `GMT`;
`now()::text` → `...+00`), so `:intervention_emitted_at` is a UTC string.
`satan-observer--window-end-iso` formats the window end in **local** time
(`format-time-string "%Y-%m-%dT%T%:z"`), and
`satan-observer--window-crosses-midnight-p` (`satan/satan-observer-classify.el:87-96`)
compares `(substring start 0 10)` against `(substring end 0 10)`. Under AEST
(+10), any intervention emitted 00:00–09:59 local has a UTC start date one day
behind its local end date, so the guard returns t and the intervention matures
`:unknown :crosses_midnight` without any predicate running. Confirmed by an
`emacs --batch` probe during SL-016's RV-007 round 3 (F-33).

The same UTC/local mix reaches `satan-memory-evidence-assemble-with-bounds`,
which keys the panopticon day file by `(substring END 0 10)` (`:506`).

## Fix direction

Compare instants, or derive dates with `format-time-string "%F"` over the parsed
time in local zone; never slice a date out of a timestamp string whose zone
came from the database session. Related: [[ISS-004]] (relax the guard).
SL-016 fixes its own `"ask"` path by construction and exempts asks from this
guard; other kinds are this issue.
