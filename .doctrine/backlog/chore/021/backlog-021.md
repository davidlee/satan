# CHR-021: pi/mcp tests: extract the spawn/gate test harness duplicated across spawn.test.ts and gate.test.ts

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

From RV-053 F-15 (follow-up, dedupe). About 450 lines of test-harness setup (a
stub launcher, a stub `pi`, policy and run-dir rigs) are duplicated between
`pi/mcp/spawn.test.ts` and `pi/mcp/gate.test.ts`. Extract one shared helper
module (e.g. `pi/mcp/test-rig.ts`) and keep both suites' assertions unchanged.
The pi suites must stay at 254 pass / 0 fail (or more) and offline.

## Done 2026-10-21

`pi/mcp/test-rig.ts` holds the shared rig, stub launcher, in-process server
driver and wait/read helpers. Both suites import it. Suites: 254 pass, 0 fail.
Assertions are unchanged, except that six gate sites now read
`markerPids(rig)[0]` where they read `markerPid(rig)`.

`isAlive` now asserts that it was given a real pid. Before, a missing pid marker
made "the child is gone" pass: `process.kill(undefined, 0)` throws, so
`isAlive` returned false. This affected spawn's `const [pid] = markerPids(…)`
sites. Gate's old `Number('')` gave 0, and `kill(0)` signals our own group.

Dogfooded. A jailed pi worker (`scripts/pi-agent dispatch-worker`,
deepseek-flash) implemented it in a git worktree. Two `pi_agent` read-profile
reviewers (behaviour and design) reviewed it. Friction found:

- `.pi/` is gitignored, so `scripts/pi-agent` run from a fresh worktree finds no
  agent profiles. Workaround: run the main checkout's script from the worktree cwd.
- In `jailed-pi`, git is unusable from a worktree: its `.git` file points into
  the main repo's `.git/worktrees/`, which is not mounted.
- The `pi_agent` policy roots name only the main checkout, so reviewers cannot
  see a worktree's delta until it is imported.
- The read form has no `node` on PATH, so a reviewer cannot run the suites.
- A `requests: 6` ceiling ran out while the behaviour reviewer was still
  exploring. Continuing its `session` with "no more tool calls, answer now" got
  the findings.

Follow-up: CHR-022 (the other suites' helpers, naming).
