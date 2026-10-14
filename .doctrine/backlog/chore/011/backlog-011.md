# CHR-011: docs/protocol.md documents log kind budget_warning; the harness emits tier_changed instead

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

`docs/protocol.md` § `log` lists `budget_warning` (emitted once on crossing
`SATAN_BUDGET_TOKENS`). The harness no longer emits it: `runloop.py` emits
`tier_changed` (from/to tier, trigger, tools removed), which `satan-tank.el`
consumes. Update the catalogue (and fixtures if they carry `budget_warning`).
Found while authoring SPEC-003, whose D2 makes `docs/protocol.md` the message
catalogue.
