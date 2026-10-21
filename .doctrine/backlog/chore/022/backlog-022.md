# CHR-022: pi/mcp tests: fold the other suites' wire and rig helpers into test-rig.ts

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Follow-up to CHR-021, which created `pi/mcp/test-rig.ts` for the spawn and
gate suites. Better done before IMP-051 (pi-mcp extraction).

Duplicates left in the other suites (found by a `pi_agent` design review,
2026-10-21; not re-verified line by line):

| helper | where | duplicates |
|---|---|---|
| `attemptLines` | server.test.ts:138, policy.test.ts:53, profiles.test.ts:418, session.test.ts:215 | `jsonLines` |
| `line` / `toolCall` | server.test.ts:59, profiles.test.ts:364 | `line` / `callLine` |
| `converse` | server.test.ts:87, profiles.test.ts:367 | `openServer` + `waitForReplies` + `closeServer` |
| `payload` | server.test.ts:146 | `document` |
| `validPolicy` / `workspace` / `basePolicy` / `mintWire` | server, policy, profiles | `newRig`'s default policy |

Naming, from the same review:

- `Session` (the in-process server handle) collides with the session domain
  that `session.ts` owns and with the `session:` call argument. Rename the type
  and its `session` variables, e.g. `LiveServer` / `server`.
- `document` → `resultDocument`; `marker` → `markerText`.

Rejected in that review: splitting test-rig.ts into wire, rig and driver modules.
The claim that gate needs no rig is false: `unitGate` reads `rig.policyPath`.

## Done 2026-10-22

Added to `test-rig.ts`: `validPolicy`, `launchEnv`, `workspace`, `attempts`,
`converse`, and `LiveServer.send`, which writes raw bytes. `converse` uses
`send`, so an unterminated final record still reaches the server. Removed the
local copies from server, policy, profiles and session. Renamed `Session` to
`LiveServer` (its variables to `server`), `document` to `resultDocument`, and
`marker` to `markerText`. Suites: 254 pass, 0 fail.

Behaviour notes, all accepted:

- `attempts` reads a missing ledger as `[]` where three of the old copies threw.
  `server.test.ts`'s spawn-failure test no longer implies that the ledger
  exists. Its stated intent is "no ledger line", which still holds.
- `converse` now has `waitForReplies`' 10 s deadline, where the old helpers had
  none. A lost reply now fails instead of hanging.

Dogfooded as in CHR-021: a pi worker in a worktree, two `pi_agent` behaviour
reviewers each given a diff slice, and pre-batched prompts to fit
`requests: 6`. Both finished inside the budget. New friction:
`.pi/agents/dispatch-worker.md` is a symlink into `.doctrine/agents/pi/`, which
is also gitignored. A worktree needs `cp -L` of `.pi/agents`, not a plain copy.
