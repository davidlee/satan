# IMP-022: Fold the two intervention-id to run-id parsers into satan-run-id-from-intervention-id

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Context

Found in SL-017 PHASE-04 (`.doctrine/slice/017/notes.md`, PHASE-04 Findings).
Two functions parse a `<run-id>.ivNNN` intervention id back to its run-id:
`satan-intervention-mark--run-id-of` (`satan/satan-intervention-mark.el`) and
`satan-tools-atsatan--intervention-run-id-of` (`satan/satan-tools-atsatan.el`).

## Detail

- A parallel pair: both encode the intervention-id grammar independently.
- `satan-run.el` already owns the run-id grammar (`satan-run-id-regexp`,
  `satan-run-mode-from-id`, SL-017 PHASE-02).

## Wanted

One `satan-run-id-from-intervention-id` in `satan-run.el` beside
`satan-run-mode-from-id`; both callers use it and the two private parsers are
deleted.
