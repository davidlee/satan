# ISS-018: Test suite may write the live ingest cursor file

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Context

Found in SL-017 PHASE-05 (see `.doctrine/slice/017/notes.md`, PHASE-05
Findings). Before that phase, the broker spawn tests (the DEC-8 tests and
PHASE-04's) ran the real `satan-ingest-cursor-advance` and wrote the live
cursor file under `satan-state-root` (`~/.local/state/satan`). A test run could
therefore move the user's real ingest cursor.

## Detail

- PHASE-05's spawn test helper now stubs the cursor advance, so those tests are
  hermetic.
- Other suites that reach `satan-broker--spawn` or the ingest cursor have not
  been audited.

## Wanted

Sweep the suite for writes under `satan-state-root` (and the other live roots),
and bind the roots to a temp dir in a shared test fixture rather than stubbing
per test. A guard that fails the run when a live-root path is written would
keep it fixed.
