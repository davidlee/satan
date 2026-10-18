# ISS-044: Intermittent 'error in process sentinel: Opening output file' for /tmp/satan-spawn-*/run/stderr.log aborts just test

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Context

Seen once in five `just check` runs during SL-022 CHR-009 (whitespace-only
commit, so pre-existing). The sentinel's `write-region` to the run dir's
`stderr.log` signalled because the dir no longer existed — a race between the
sentinel flush and the test's (or finalize's) rename/cleanup of the run dir.

## Consequence (RV-024 F-2)

Before 2243b41 the failed flush also aborted the refusal record, so a refused
child hit by the race closed as an untyped `failed` (violating SL-022 I4).
2243b41 makes the flush fail soft (logged via `message`), so I4 holds; what
remains is the lost `stderr.log` and the race itself. Find who removes or
renames the dir before the sentinel runs (finalize's `.FAILED` rename vs the
stderr pipe sentinel ordering) and order them.
