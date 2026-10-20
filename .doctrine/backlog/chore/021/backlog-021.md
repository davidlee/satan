# CHR-021: pi/mcp tests: extract the spawn/gate test harness duplicated across spawn.test.ts and gate.test.ts

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

From RV-053 F-15 (follow-up, dedupe). About 450 lines of test-harness setup (a
stub launcher, a stub `pi`, policy and run-dir rigs) are duplicated between
`pi/mcp/spawn.test.ts` and `pi/mcp/gate.test.ts`. Extract one shared helper
module (e.g. `pi/mcp/test-rig.ts`) and keep both suites' assertions unchanged.
The pi suites must stay at 254 pass / 0 fail (or more) and offline.
