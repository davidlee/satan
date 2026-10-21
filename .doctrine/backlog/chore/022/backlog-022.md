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
