# ISS-056: malebolge: a submission the model fails to answer is invisible to the attached client

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Observed (2026-10-21)

DeepSeek ran out of credit. Every input in conversation 1 was recorded in the
`submissions` table of `~/.local/state/satan/durable/room/session.sqlite` as
`status = 'unanswered'`, `reason = 'model_error'`, with `detail` holding
`402 … Insufficient Balance`. The attached client printed only the echoed
`» prompt` lines, so it looked as if the daemon had hung. Nothing was written
to the unit's journal either. `src/` has no reference to `unanswered` or
`model_error`, so no client renders that state.

## Want

- The client renders an unanswered submission inline with its reason, e.g.
  `[unanswered: model_error — 402 Insufficient Balance]`.
- A billing or credit error (HTTP 402) gets a distinct, loud form: a top-up
  warning, and a desktop notification or Emacs message so the cause shows
  without opening the buffer.
- The daemon logs model errors to the journal.
