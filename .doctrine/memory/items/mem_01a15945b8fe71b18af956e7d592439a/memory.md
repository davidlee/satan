Nested fanout is opt-in per agent: a child may spawn its own children only when its
frontmatter `tools` includes `subagent` (or `allowNestedSubagents: true`). The builtin
`worker` and `delegate` allowlists are `read, grep, find, ls, bash, edit, write,
contact_supervisor` — no `subagent` — so a capsule-driver-style tree (super →
orchestrator → worker) needs a custom orchestrator agent declaring `subagent`.

Depth default is 2 below the parent (orchestrator = 1, worker = 2, exactly at the cap);
at the cap fanout is blocked, not silently hidden. Session fan-out cap defaults to 64
launches (`Run fan-out: N/64 used`).