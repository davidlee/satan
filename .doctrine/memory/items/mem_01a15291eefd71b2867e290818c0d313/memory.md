`doctrine review amend RV-NNN --finding F-n --route <r>` requires `--response`, and that text **replaces** the finding's existing response — it does not append.

**Why it matters:** routing a batch of answered findings with a short generic response silently erases the detailed adjudication (seen on RV-031, 2026-10-19; restored by a second amend).

**How to apply:** when only the route must change, pass the finding's current response verbatim (read it with `doctrine review show RV-NNN -f F-n`) plus any route note. Better: set `--route` at `review dispose` time so no amend is needed. A severe (major/blocker) finding needs a route before a design run's review-disposed act clears.