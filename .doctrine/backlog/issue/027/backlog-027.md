# ISS-027: Observation trace predicates serialise as a JSON object, outcome evidence as an array

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Observed live in SL-016 PHASE-08 (VH-1). Observation trace
`20260924T174554-cobp4g` carries `"predicates": {"goad_answer": {}}`, while the
outcome row's `evidence_json` for the same verdict holds `["goad_answer"]`.

The positive trace's metadata puts the verdict's `:predicates` list straight
into a plist (`satan/satan-observer.el`, `--persist-positive`, `:predicates
firers`). That line dates from b2f0da11 (2026-07-12), so this affects every
intervention kind, not only asks. Likely cause (unverified): the JSON encoder reads the list of
symbols as an object rather than an array.

**Fix:** encode `:predicates` as a vector (or through the helper the outcome row
already uses), and add a test that pins the trace shape to the producer's own
output.

Found by RV-017 and carried to RV-018 F-10(d).
