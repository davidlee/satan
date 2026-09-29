# ISS-035: Content captured_at switched from UTC-Z to local offset; sensor-content and ingest-cursor still assume UTC-Z string order

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Found 2026-09-29 while surveying panopticon content for IDE-001. Verified
against live data; the misbehaviour itself is not reproduced in a test yet.

## Drift

Both readers document `captured_at` as a single **UTC-millis-Z** format and
compare it with `string<`:

- `satan/satan-sensor-content.el:6-13,73-75` — backlog count + watermark.
- `satan/satan-ingest-cursor.el:14,27` — `:content` cursor, "`string<` on the
  single UTC-millis-Z `captured_at` format".

panopticon commit `55212c4` ("TZ and content collection") switched the host to
local-offset stamps (`firefox_host/__main__.py:141`). Live
`articles.jsonl`: ~35 rows `…Z` (May 2026), 2344 rows `…+10:00`.

## Consequence

`string<` across mixed formats misorders any pair straddling the switch (a
`Z` instant sorts as up to 10 h off). Among same-offset strings it happens to
work, so the damage is at the boundary and around any DST offset change. A
stale `Z` watermark mis-counts the backlog.

## Fix direction

Compare parsed instants, as `satan-memory-evidence--newest-segment-end` already
does for segments (see mem.pattern.satan.sensor-watermark-format); keep storing
the watermark verbatim. Test with a mixed-format fixture.
