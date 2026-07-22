# SATAN sensor watermark format

# SATAN sensor watermark must match the source timestamp format

## Summary

A backlog sensor that advances a watermark by lexical `string<` comparison MUST
store the **source record's timestamp verbatim**, never a formatted `now()`.
Mixing timestamp formats across the comparison makes `string<` meaningless.

## Context

`dl-satan-sensor-content` (DE-005 / DR-005 DEC-5) partitions captures by
`(string< watermark captured_at)`. The content store's `captured_at` is
UTC-millis-`Z` (`2026-05-31T05:25:45.968Z`). The sibling it was cloned from,
`dl-satan-sensor-curiosity`, advances its watermark with
`mark-inspected` defaulting to `(format-time-string "…%:z")` → local-offset
form (`+10:00`, no millis). A `string<` between `…Z` and `…+10:00` compares `Z`
vs `+` and millis vs none — garbage.

So `dl-satan-sensor-content--count-uninspected` returns
`(count . high-water)` where `high-water` is the **max `captured_at` string
seen**, and the probe calls `mark-inspected high-water` — NOT the broker's `ts`
(`(plist-get prepare :time_now)`, which is broker-generated, not a panopticon
`captured_at`). `ts` is used only in the attribute payload.

**Why:** the curiosity clone is correct for segments (it reads segment end-ts in
its own format), but copying its `mark-inspected now()` default into a sensor
that reads a *differently-formatted* source silently breaks watermark advance —
no error, just a sensor that re-fires or never advances.

**How to apply:** when cloning a sensor, check the source timestamp format
before reusing the watermark-advance call. Store the source's own max timestamp;
do not format your own. Guard it with a test that seeds a source-format
watermark and asserts advance (see
`dl-satan-sensor-content/dec5-watermark-is-captured-at-not-ts`).

Verified by VT in DE-005; conformance-audited in AUD-007 (F-: all watermark
items CONFORM).
