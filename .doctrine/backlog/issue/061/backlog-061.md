# ISS-061: satan-activity presence tests fail 00:00-01:00 local under AEDT: fixture zone pinned to +10

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Observed

SL-032 audit gate, 2026-10-27 00:35-00:40 AEDT (+11): `just check` →
3 unexpected / 1378:

- `satan-activity/current-carries-recent-presence` (test.el:329)
- `satan-activity/recent-browser-segments-carry-presence` (:290)
- `satan-activity/recent-focus-is-a-timeline-with-presence` (:255)

Presence/keyrate read nil/"missing". The same file passes 18/18 under
`TZ=Australia/Brisbane` (+10) at the same instant.

## Inference (unverified)

`satan-desktop-fixture-zone` pins the reader to +10 (36000), while the
test writes keyrate minutes into the file for "today"
(`satan-tools-activity-test--today`), apparently by host-local date. In
the hour after local midnight under DST the two dates differ, so the
reader looks in the previous day's file. Which side should move is open.

Related: ISS-036 (tests depend on host time zone; different root cause).
