# SL-020 — plan

## Why two phases, and why the seam is here

Two read-only tools over the user's notes corpus, plus the wiring that makes them
reachable and the prose mirrors that keep the system's inventories honest. That
is one coherent change, but it is not one coherent *commit* — and the seam is
chosen where the repository is independently green rather than where the file
boundaries happen to fall.

**PHASE-01 — the tools and their descriptions.** The module, its tests, and the
corpus files a registration obliges. Two facts fix its boundary:

- A tool's description is *load-bearing at two hard-failure points*: the manifest
  build signals on a missing description file, and MCP startup fail-fasts on one.
  Because `satan-mcp--interactive-tools` is the union of every registered tool,
  the second fires whether or not the tool is ever allowlisted. So descriptions
  cannot be a later phase: a registration without them is a broken tree.
- Nothing else needs to move for this phase to be safe *and* useful. Registering
  without allowlisting means the tools are not yet reachable from `morning`,
  `motd` or `ruminate` — they are reachable from the interactive session, which is
  the surface that reads the descriptions at startup — and the notes module's
  existing tests keep passing.

**PHASE-02 — the wiring.** Allowlists, the token-tier ladder, four doc mirrors,
the `ruminate` prompt. This is the phase that makes the capability *used* rather
than merely present, and every one of its edits is a foreign file (a mode spec, a
Python set, two docs, a corpus prompt) whose correctness is judged against the
registries PHASE-01 established.

The alternative seam — one phase — was rejected because it would bundle a
correctness-critical, self-contained module change with six foreign files whose
only failure mode is *drift*: stale inventories, a missing prompt line, a tool
available past its tier. Those are exactly the errors that hide in a large diff
and that a reviewer of the module would not be asked to look at. Splitting also
means PHASE-01's verification is entirely automated (16 tests, one agent-read of
four corpus files) while PHASE-02 carries the one human acceptance, which is
honest about where judgement is actually required.

## Phase-01 in detail

Design sections 2–4 plus 6, and the mind half of 5.

Order inside the phase matters and is the design's own:

1. **Descriptions first.** `tools/notes_read.md`, `tools/notes_grep.md`, and the
   two corrections (`notes_recent.md`'s two falsified sentences;
   `org_read_context.md`'s pointer) land before the registrations exist, so the
   tree is never in the state where a registered tool has no description.
2. **The module.** One subprocess helper (`--run-fd` → `--run`), program
   resolution (`--resolve-program`, so a missing binary produces the module's own
   message rather than a `file-missing` signal), the root helper, the resolver,
   the capped reader, two handlers, one rename, two registrations. The rename
   (`satan-tool/notes-read` → `satan-tool/notes-recent`) is mechanical and must
   land with the registrations or the two meanings sit on one symbol.
3. **Tests**, written against behaviour and in the design's named set of 16 — the
   confinement table exercised case by case, including the symlink that escapes
   the root (the only case that tests truename containment) and the directory and
   root refusals, which is where the design's own first draft was wrong.

The risk this phase carries is *scope trust*: the resolver is the slice's only
security-relevant code, and the temptation is to simplify it back to a string
check on the grounds that the handler refuses non-files anyway. The design says
why not (a `..`-free string check does not follow symlinks); the tests are what
make the difference visible.

## Phase-02 in detail

Design section 5 plus the tail of 6.

1. **Allowlists** — `morning`, `motd`, `ruminate`. `tick-*` deliberately not.
2. **Tier ladder** — `notes_grep` to `TIER_1_DROP` (survey), `notes_read` to
   `TIER_2_DROP` (focused read), with the harness test asserting both. The sets
   are *drop* lists, so an unclassified tool stays available at every tier; that
   is why CON-001 exists and why this step is not optional.
3. **Doc mirrors and prompt** — governance `## Tools` and `## File map`;
   resilience §2.2 and its §3 per-tool inventory; `prompts/ruminate.txt`.

The failure mode here is drift, not breakage, with one exception: the `morning`
manifest build is gated by the broker test's description fixtures, so those two
fixtures must carry the new names or the suite goes red — which is the test doing
its job, and the reason the fixtures are in scope rather than an afterthought.

## Verification posture

| | automated | agent-read | human |
|---|---|---|---|
| PHASE-01 | 6 VT groups over 16 cases | the four corpus files | — |
| PHASE-02 | 3 VT groups | the four doc mirrors + the prompt | the end-to-end reachability claim (VH-1) |

Each VT row in `plan.toml` carries a structured mandate (`test_file` +
`keywords`) so `doctrine slice verify-vt` has signal rather than reporting
`UNCHECKABLE` — the mandate points at the test file the phase writes, and the
keywords are the behaviour names that must appear in it.

## What this plan does not do

- It does not implement the `docs_*` rename (June proposal part 2), `notes_list`,
  or pagination (**QUE-002**, deferred by the user).
- It does not touch the jail's dead `/satan/notes` bind, the note-body retention
  question, or the write path into `~/notes` (forbidden outright).
- It does not add a slice-level requirement link: SPEC-001's requirements are
  `pending`, so `[requirements]` stays empty rather than citing inert ids.
