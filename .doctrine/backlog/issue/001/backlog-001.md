# ISS-001: Evidence truncation hard cap is documented as mandatory but never enforced

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

`satan-memory-evidence--truncate` documents HARD-CAP as "mandatory", but the
pass chain cannot enforce it: passes 1–4 shrink specific fields (bough_day,
browser/focus segments, bough_active annotations) and pass 5 only drops
`:bough_recent`. An evidence object whose excess lies in any other field
(e.g. `content_recent`, `git_commits`) returns above HARD-CAP with no final
reducer. The existing hard-cap test only proves populated `:bough_recent` is
removed; it never asserts final encoded size.

Surfaced by SL-001 design inquisition round 2 (RN-7, codex; adjudicated D7).
SL-001 narrows the documented contract to best-effort and keeps pass 5
conditional on a non-nil payload; the real fix — a general final reducer (or
a redesigned pass chain) that guarantees the cap plus a test asserting
encoded output bytes ≤ HARD-CAP — belongs here.

Pointers: `satan/satan-memory-evidence.el` (`--truncate`, pass 5),
`satan/test/satan-memory-evidence-test.el` (hard-cap coverage),
`.doctrine/slice/001/design.md` §10 RN-7 / D7.
