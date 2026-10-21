# IMP-049: pi-mcp: an operator-facing policy schema and worked example outside slice notes

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

From the review of SL-029's reconcile arc (point 6). The policy schema refuses
everything over one missing or malformed field: all four `maxima` units are
required and positive, along with `mode`, `roots`, `profiles`, `forms`,
`child_binds` and `enabled`. Yet the only worked example lives in
`.doctrine/slice/029/notes.md` (§ PHASE-09 evidence). An operator on a new host
should not need a slice history to publish a policy.

Shape: a short operator doc beside the server (e.g. `docs/pi-mcp.md`, indexed
from `docs/INDEX.md`). It should cover every field with its type and refusal, a
minimal valid per-call policy, the publish rules (read-only, outside every root,
atomic write-then-rename), and the `child_binds` trap in IMP-048. Optionally,
the example policy can be checked by a test, so the doc cannot drift from
`validatePolicy`.

## Done 2026-10-22

Agreed sketch, implemented:

- `pi/mcp/README.md`, the operator guide, sits beside the server rather than
  under `docs/`, so it travels with the IMP-051 extraction. `docs/INDEX.md` has
  a new "pi delegation" section that points to it. It covers:
  - the launch environment, three absolute paths, which are the server's whole
    configuration surface (IMP-051's survey point);
  - a field table giving each field's type, whether it is required, and the
    refusal a bad value raises;
  - a minimal per-call policy;
  - profiles and forms;
  - publishing, which separates what the server enforces from what the operator
    must do;
  - the `child_binds` limitation (IMP-048);
  - a refusal table.
- The drift test is `pi/mcp/readme.test.ts`, written before the doc, so it
  started red:
  - Every `json` block must pass `readPolicy`.
  - Every schema field must appear in the doc backticked. The field-name
    constants are now exported from `policy.ts`.
  - The three launch variables must appear.
  - Every refusal reason must appear. The union reasons are read from the
    sources' `export type …Refusal… =` declarations, not from a hand-copied
    list, so a reason added to a union fails the suite until the doc names it.
- The `research` reviewer checked the doc against the code. It found one error:
  the README gave a single step for `profile-invalid`, but it is raised in three
  places — before every call when the start-up snapshot failed to load, at
  step 3 for the name grammar, and at step 5 for the extension check. The README
  row is fixed. `server.ts`'s order comment had the same gap, and now names the
  snapshot check first. Every enforcement claim in "Publishing" was traced to
  code.
- Suites: 262 pass, 0 fail.

Dogfood: a pi worker in a fork made by `doctrine worktree fork` (again
"0 copied", so `.pi/agents` was copied in with `cp -rL`), and the `research`
profile as reviewer: 6 requests, final, $0.019.
