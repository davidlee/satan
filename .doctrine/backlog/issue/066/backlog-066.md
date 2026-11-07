# ISS-066: Curiosity is pinned at its ceiling: the attribute no longer carries signal

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Measured 2026-11-07 from `satan_attribute_events`: Curiosity reached 1.000 on each of
the prior 15 days and stands at 0.975. `segment_backlog` fires about 23 times a day and
`trace_marked` about 18; 309 of 690 Curiosity events in 30 days carried a cap.

Curiosity is not in `DECAY_TARGETS`, so nothing but `trace_marked` pulls it down. The
"+0.025/day net" in contract §6H footnote 6 and §8 assumes a daily cadence that no longer
holds. The attribute now reads as a constant near 1.0.

`SL-037` adds `content_backlog` at about 9 events a day, which adds pressure (`DEC-149`).
Likely owner: the decay work (contract §8), or a re-think of the per-event rows.
