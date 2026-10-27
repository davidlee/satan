# IMP-058: malebolge: attribute a wake turn's in-turn satan-mcp calls as kind scheduled (SL-034 DEC-133)

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Deferred from SL-034 (DEC-133). malebolge's satan-mcp pool key for tool calls is
fixed to `interactive` (`src/satan-tools.ts:39`), so SATAN's own tool calls inside
a wake turn are attributed `interactive`; only the daemon's percept/presence/notify
calls are `scheduled`. Fix: in the tool's `execute`, detect that the running turn
was started by a `satan.wake` input entry and use kind `scheduled`. Needs a way to
find the turn's triggering entry from the tool API (none direct as of pi-durable 1.4.0).
