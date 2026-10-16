# IDE-009: SATAN modes as events into one durable conversation (pi-durable passive entries)

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

From CHR-012 (RFC-018 F4). RFC-018's durable brief makes modes (`morning`,
`tick`, `@satan`, self-edit) *event classes* delivered to one organism.
pi-durable accepts passive entry writes of custom kinds through the
conversation inbox (they queue, steer or follow up like input). Candidate
carrier for ADR-018 OQ-1. Untested.

Questions: one conversation or one per mode family; how compaction treats
high-volume tick entries; how the persona section changes per event class.
Gated by RSK-018 for any non-interactive delivery.
