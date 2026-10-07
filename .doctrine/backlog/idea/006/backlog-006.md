# IDE-006: Emacs coaching nudges driven by the learning skill map

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Idea

The user keeps a private Emacs learning record in `~/notes`: a skill map
(capabilities with levels UNKNOWN / AWARE / USING / FLUENT and evidence
dates), a try-next queue and a dated log. Agents update it through the
`emacs-coach` skill (`~/.emacs.d/.agents/skills/emacs-coach/`).

SATAN already has the loop this needs: interventions with outcome
classification (observer), motives and sensors. It could:

- notice a capability being done the slow way (e.g. a command reached
  via `M-x` that has a key; grep where xref would serve) and offer a
  one-line nudge at that moment;
- classify whether the nudge was taken up, and write the outcome back as
  log / evidence;
- draw candidate nudges from the try-next queue.

## Constraints

- Learning state stays in `~/notes` (private); the package stays
  general.
- Nudges must be rare and well-timed; the user doesn't want drills or
  quizzes.
- Evidence source for "done the slow way" needs a command-usage sensor
  (prescient history is recency-ranked, not counts).
