# IMP-056: malebolge wakes: pre-compact a heavy conversation before a wake (SL-034 inq-9, OQ-5)

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Deferred from SL-034 (inq-9). pi-durable auto-compacts in the background above
`contextWindow − backgroundTokens` (32k) and blocking above `− reserveTokens`
(16k). A wake turn is unattended, so a mid-turn compaction costs only latency.
Do this if wakes into long conversations prove slow or lose too much context:
before submitting the wake, recompute the context size host-side (pi-ai
`calculateContextTokens`; the harness estimator is not exported) and call
`conversation.compact()` above a configured fraction of the window.
