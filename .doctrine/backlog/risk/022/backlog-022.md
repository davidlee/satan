# RSK-022: malebolge room tools without a per-call deadline: bash, grep (a hung call holds a wake's turn)

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Source: SL-034 design § Risks and follow-ups ("A hung tool call inside a turn"
— implementation check), done in PHASE-06 (2026-10-28).

A hung tool call holds its turn, and a wake waiting on its placed input,
until it returns or the daemon restarts; the model stream deadline (SL-034
PHASE-03) bounds model streams only. Findings (malebolge b1ac1d9 + pi 1.4.0):

| tool | per-call deadline |
|---|---|
| satan-mcp tools (`src/satan-tools.ts:55-64`) | yes: pi-mcp's default request timeout, 30 s, re-armed on each progress notification (`pi/packages/mcp/src/client.ts:38,420,554-559`); malebolge sets no `requestTimeoutMs` |
| `bash` (pi-durable CodingTools) | **no**: model-supplied `timeout` only, "no default timeout" (`dist/tools/bash.js:8,12`) |
| `grep` (`src/grep.ts`) | **no**: aborts only on its output caps or the caller's signal (`grep.ts:328-360`) |
| `read` / `write` / `edit` / `image` | no timer; local fs, bounded in practice (inferred) |
| wake tools (SL-034) | `wake_cancel` waits on the abort handler, which runs no unbounded wait |

Candidate fix: a malebolge wrapper (`wrapTool`) giving `bash` a default
timeout and `grep` a wall-clock abort, configurable per profile.
