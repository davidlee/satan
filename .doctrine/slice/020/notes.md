# Notes SL-020: notes_read and notes_grep

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## Inquiry dispositions (inquiring, 2026-09-25)

Seven blocking inquiries, all disposed in the design run.

| node | disposition | outcome |
|---|---|---|
| inq-1 confinement | create | **DEC-029** — `notes_read :path` is notes-root-relative only; absolute, `..`, truename-escape, the root itself, missing and non-file all *error*; resolution via `expand-file-name` + `file-in-directory-p`, never a regex |
| inq-2 probe failure | create | **DEC-030** — missing/failing `fd`/`rg`, and any exit > 1, is an error; rg exit 1 is a clean empty result. Explicitly *not* `content_read`'s soft-fail-to-empty |
| inq-3 body size | create | **QUE-002** — this slice ships cap + `:truncated` + `:chars`/`:total-chars`; whether a single over-cap note needs offset pagination is deferred on the user's steer (2026-09-25) until a real note proves the flat cap useless |
| inq-4 grep shape | non-durable | single line per hit `{:path :line :text}`, `--max-count 10 --max-columns 200 --ignore-case`, total cap with `:truncated`; no ±N context (±N belongs to `notes_at_satan_scan`, where the directive is the query) |
| inq-5 tier placement | create | **CON-001** — every registered tool must be classified in the harness tier ladder; `notes_grep` → tier 1, `notes_read` → tier 2, `docs/resilience-design.md` §2.2 updated in the same commit |
| inq-6 handler rename | non-durable | in scope: `satan-tool/notes-read` → `satan-tool/notes-recent`, registration + test call sites |
| inq-7 interactive surface | create | **DEC-031** — the tools are exposed on the `interactive` MCP surface by registration, ungated; the consequence is that the corpus descriptions are load-bearing for MCP startup |
| inq-8 door width | create | **DEC-032** (user-directed) — `.org`/`.md`/`.txt` only, never a hidden path component; overlap with `org_read_context` is allowed *on the condition* that both descriptions name the equivalent reads |
| inq-9 grep scope | create | **DEC-033** (user-directed) — `notes_grep` searches exactly the file set `notes_read` can open, so every hit is actionable; recalled loss of non-note files is accepted and stated in the description |

Durable records: DEC-029, DEC-030, DEC-031, DEC-032, DEC-033, CON-001, QUE-002
(all `shapes: [SL-020]`).

Both user-directed dispositions came from real questions put to the keeper on
2026-09-25 (door width; grep scope) — the first two ask_user calls of this run
were gate signatures rather than questions, and inq-8/inq-9 exist because that
was the wrong way round.

## Harvest

fresh-as-of: 2026-09-25 · PHASE-02 implementation complete, awaiting VH-1 ·
mechanism head 21a50d8 · mind head 5d67b78 (corpus: prompts/ruminate.txt;
PHASE-01's four tool descriptions under 1d122dc).

### Produced

- **`notes_read` / `notes_grep`** in `satan/satan-tools-notes.el` (commit
  `124c268`), with 27 tests in `satan/test/satan-tools-notes-test.el`. The
  `notes_recent` handler is now `satan-tool/notes-recent`; its registered name is
  unchanged.
- **Durable decisions** (all `shapes: [SL-020]`): **DEC-029** path confinement,
  **DEC-030** probe failure is an error, **DEC-031** interactive-surface
  exposure accepted, **DEC-032** `.org`/`.md`/`.txt` + no hidden component
  (user-directed), **DEC-033** grep searches what read opens (user-directed;
  amended in place with a dated correction — the guarantee is one-way, rg's
  ignore rules narrow the search set), **CON-001** every registered tool is
  classified in the harness tier ladder.
- **QUE-002** — whether `notes_read` should paginate when a note exceeds the cap.
  Open by the user's own instruction; `:total-bytes` at least shows how much is
  not being seen.
- **RV-019** — the design review, concluded: 17 findings, all `fix-now`, all
  verified. Five `major`, all of one species: a design claim the code or the
  toolchain contradicts.

### Produced (PHASE-02)

- **Reachability** (`21a50d8`): `morning`, `motd`, `ruminate` allowlist `notes_read`
  and `notes_grep`; `tick-*` deliberately untouched. `satan-mode-check-tool-references`
  passes at load, so the allowlists cannot outrun the registry.
- **Tier ladder** (`satan/harness/runloop.py` + `test_gptel_harness.py`):
  `notes_grep` → `TIER_1_DROP`, `notes_read` → `TIER_2_DROP`. The red run is the
  demonstration: before the sets changed, both tools were present at their tier.
- **Broker fixtures** (`satan/test/satan-broker-test.el`): both description alists
  and the manifest-shape assertions. Red without them — `satan-broker/manifest-tools-shape`
  and `run-emits-one-tick-row-outcome-spawned` both failed on the missing lookups.
- **Doc mirrors**: `docs/governance.md` `## Tools` (both rows) + the
  `satan-tools-notes.el` `## File map` row (now all three names);
  `docs/resilience-design.md` §2.2 (both drop lists) + §3 (both inventory rows).
- **Prompt** (`5d67b78`, corpus): `prompts/ruminate.txt` gather step 1 names the
  find-then-read pair.
- **IT-011's diff went 15 → 13**: `comm -23` of registered names against the
  `## Tools` rows drops exactly the two new names and loses none.

### Learned (PHASE-02)

- **A single broker test run in isolation reports `credential_unavailable`.**
  `satan-broker/run-emits-one-tick-row-outcome-spawned` passes in the full suite
  and fails when run alone — an earlier test installs the credential stub the run
  depends on. Not caused by this phase; a test-isolation smell worth its own item.
- **The stale-`.elc` trap is already mitigated at the runner**: `dev/satan-test.el:39`
  sets `load-prefer-newer t` before any `require` (this is what `144247a` fixed),
  so an edited source wins over an older `.elc`. Deleting touched `.elc` is belt
  and braces, not the mechanism.
- **The broker test's manifest gate is reached from two tests**, not one: the
  `morning` manifest is built both by `manifest-tools-shape` and by
  `run-emits-one-tick-row-outcome-spawned` (through the shared description alist).
  A fixture added to one alist only would leave one of the two red.
- **Two entries in the doc mirrors are stale beyond this slice's scope** and were
  left alone: the `satan-tools-atsatan.el` File map row still says `~/notes/`
  "excluding `satan/`" (false since SL-015 — same falsified sentence PHASE-01
  corrected in `notes_recent.md`), and `docs/resilience-design.md` §3 still lists
  `bough_read` and `notes_at_satan_intervention_done`. Drift for a board item, not
  a phase.

### Learned (things a future agent would otherwise rediscover)

- **`file-in-directory-p` counts a directory as inside itself**, so containment
  does *not* refuse the root. The root is refused as a non-file. The design's
  first draft asserted the opposite and RV-019 F-6 executed the code to disprove
  it.
- **rg replaces an over-long match line with the literal `[Omitted long matching
  line]`** — the matching phrase is unavailable, not "truncated with an ellipsis".
  `--max-columns-preview` is what keeps the phrase readable (verified against rg
  15.2.0). Encoded in the argv, the contract and the description.
- **Emacs aligns `insert-file-contents` to a character boundary** when given a
  byte END: reading N bytes of a multibyte file yields ≤ N bytes of whole
  characters, so a byte cap cannot split a character.
- **The notes test suite must not load stale bytecode.** The devshell leaves
  `.elc` files beside the sources and `require` prefers them, so a source edit is
  invisible until `satan/satan-tools-notes.elc` is removed (commit `144247a`
  addressed the same trap in the runner). Three "failures" in this phase were
  the old bytecode answering.
- **`~/satan-corpus` is path-shadowed inside this dev shell.** The corpus is
  reachable only at `/workspace/satan-corpus`; `(expand-file-name
  "~/satan-corpus")` resolves to `/home/david/satan-corpus`, which does not exist
  by path even though `/proc/self/mountinfo` names it as the bind source. So an
  emacs-side check of `satan-tools-descriptions-dir` fails *here* for
  environmental reasons — it must be run where the broker actually runs. (Same
  class as the r3 IT-019 shadowed-bind finding, and as the corpus hippocampus
  entry written today: 20260925T164847.)
- **`just test` needs the test databases**; without them one test
  (`satan-db/test-db-available-p-probes-test-host`) fails. Every run of the suite
  in this session was therefore "1 unexpected, 177 skipped", all notes tests
  green.
- **IT-011's `registered − ## Tools` diff is non-empty before this slice** (15
  names). PHASE-02 must not add to it — that is the check, not an empty diff.

### Open / hand-forward

- **VH-1 (user acceptance)** is PHASE-02's only human criterion, still open: that
  the tools are reachable in the three modes and usable end to end in a `ruminate`
  or `morning` manifest.
- **Suite green here is a partial green**: the test databases are unreachable in
  this dev shell, so the gate is `SATAN_TEST_ALLOW_NO_DB=1 just check` →
  **PASS 1151/1329 (178 skipped)**, lint clean, harness 54 OK. Zero unexpected.
- **The user's uncommitted `satan-mode.el` budget bumps** (`300000` →
  `340000`/`400000`) remain in the worktree, unstaged — PHASE-02's allowlist hunks
  were staged selectively (`git apply --cached` of a filtered diff) so they did
  not ride the commit.
- The corpus's shadowed-bind issue has its own proposal and hippocampus entries
  (20260925T164831, 20260925T164847) — not this slice's business, but it is why
  the description-coverage check could not be run here.
- The corpus commit (`5d67b78`) staged `prompts/ruminate.txt` alone; the corpus
  tree's unrelated in-flight changes (`AGENTS.md`, `flake.nix`,
  `iteration/state.md`) are untouched and still uncommitted.

## Design surface triage (exploring, 2026-09-25)

Evidence base: `research/research.md` (round 1, baseline re-stamped after the
scope was widened to include the harness tier ladder). Line refs there; this
section is the distilled triage the design run consumes.

### Constraining governance

- **POL-001** seats `satan-tools-{atsatan,notes}.el` in the Emacs client ("the
  notes corpus as substrate") — mechanism placement is settled, not a design
  question.
- **The three-roots rule** ([[mem.concept.satan.three-roots]], SL-015 I3): the
  notes root is the user's, read-only to SATAN. Both tools are read-only with no
  capability; the ADR-017 §3 ledger gains no row (a tool is *content of* row 2's
  registry).
- **`satan-tools.el`**: mode `:tools` is the authority; a missing description
  file is a hard error at manifest build *and* at MCP startup.
- **Read broadly, write narrowly**, and SL-015's "a wrong-but-readable path is
  worse than an error" — which is why a missing `rg`/`fd` must error rather than
  soft-fail to empty.

### Shaping decisions (to be locked in design)

- **D-a — confinement rule for `notes_read :path`.** Relative to the root only;
  reject absolute, any `..` component, the root itself, and any path whose
  truename escapes the root (symlink). Refusal is an error, not an empty result.
- **D-b — error policy.** Missing binary / rg exit ≥2 → `(error . msg)`; rg exit
  1 (no matches) → `(ok … :count 0)`. Explicitly *not* `content_read`'s
  soft-fail-to-empty (`satan-tools-content.el:242-260`).
- **D-c — one local subprocess helper.** Generalise `--run-fd` to a
  program-agnostic `--run` serving both `fd` and `rg`; do **not** extract a
  shared rg module across `hippocampus`/`content`/`atsatan` in this slice (it
  would pull three unrelated modules into the touch-set for no behaviour change).
- **D-d — rename `satan-tool/notes-read` → `satan-tool/notes-recent`**, freeing
  the name for the new tool.
- **D-e — caps.** Body char cap with `:truncated`; total match cap with
  `:truncated`; per-file match cap on the rg argv. Values are OQ-1/OQ-2.
- **D-f — tier classification** (`satan/harness/runloop.py`): `notes_grep` →
  `TIER_1_DROP`; `notes_read` → `TIER_2_DROP`; §2.2 of
  `docs/resilience-design.md` updated in the same commit.

### Open questions

- **OQ-1 (body cap).** One default cap + `:truncated`, or offset pagination like
  `content_read`'s `get` scope? Truncate-and-flag is the smaller thing; paginate
  only if a real note proves unusable truncated.
- **OQ-2 (grep match shape).** Single matching line (as `hippocampus_grep`) or
  ±N context lines (as `notes_at_satan_scan`)? Single-line is smaller, and the
  query is model-chosen.
- **OQ-3 (interactive exposure).** Registration puts both tools on the `interactive`
  MCP surface automatically (the union of all registered tools). Intended — but
  it makes the corpus descriptions load-bearing for the keeper's own session, and
  the design should say so rather than leave it incidental.

### Risks

- **R1 token cost** — a read tool pulls arbitrary note bodies into a budgeted
  context. Mitigated by the cap + the tier ladder (D-f).
- **R2 manifest width** — two tools across three modes and the interactive union.
- **R3 mind/mechanism coupling** — the descriptions must land in the same commit
  as the registrations or broker *and* MCP startup fail.
- **R4 doc-table drift** — `docs/governance.md` `## Tools` is under IT-011's live
  two-way falsifier; `docs/resilience-design.md` §2.2 mirrors the tier sets.

### Assumptions

- **A1** `fd` and `rg` are on the broker's host PATH (as `notes_recent` already
  assumes for `fd`).
- **A2** `rg`'s default ignore behaviour (gitignore-aware, hidden skipped) is the
  intended filter — the same one `fd` gives `notes_recent`.
- **A3** the notes corpus as seen by the broker equals the corpus as mounted at
  `/satan/notes` in the jail (the mount has no reader today; if a future reader
  appears, the two paths must stay one root).

## Review pass RV-019 (reviewing, 2026-09-25)

Two passes, 17 findings, all `fix-now` and verified; RV-019 concluded. Full
charges, responses and synthesis live on the ledger
(`.doctrine/review/019/review-019.md`); this is the harvest-relevant residue.

- **Self-pass (F-1..F-4, author):** absent notes root misreported as a path
  escape; `--max-columns` truncation undocumented; the containment/shape split
  unstated as an invariant; §2/§4 refusal lists with no stated correspondence.
- **Independent pass (F-5..F-17, fresh-context Inquisitor):** five `major` taints,
  all of the same species — a design claim the code or the toolchain contradicts.
  `file-in-directory-p` does not refuse the root (a directory is inside itself);
  the confinement had no symlink test; rg replaces an over-long match with
  `[Omitted long matching line]` rather than an ellipsis; `--max-count 10` was a
  silent per-file false negative; `--read-capped` was called with one argument
  and defined with two. Plus three missed coupling enumerations (resilience §3,
  governance File map, the `ruminate` prompt), and seven smaller drifts
  (citations off their lines, a test count passed off as a call-site count, an
  example plist the parser cannot produce, "exactly" where the guarantee is
  one-way, a promised refusal with no mechanism, a byte cap named for characters).
- **Design at revision 31**, materialised; every fix verified against the
  materialised text, not the conversation.
- **DEC-033 amended in place** with a dated correction: the guarantee is one-way
  (every hit is openable) and rg's ignore rules make the search set a strict
  subset. A durable claim was wrong; it was corrected where it is owned.

### What a further pass would probe

None is needed, and the reason is specific rather than budgetary: the two passes
covered the two things that can actually be wrong in a design of this size — the
mechanism claims (checked by execution against rg, `file-in-directory-p` and the
denote parser, which is what found the three worst charges) and the coupling
inventory (checked by grepping the repo for every place a tool name is
enumerated, which found three missed sites). A third pass by the same author
would re-read the same sections with the same blind spots; a third pass by a
fresh reviewer would be a second opinion on a 130-line module, which the
implementation's own verification will exercise more cheaply.

If a further pass *were* run, the highest-yield lines of attack would be: (1) the
`--max-columns-preview` behaviour of a *future* rg version, since the contract now
names a marker string; (2) whether the five corpus files say the same thing as the
design's §5 table once written (no mechanism checks that — R5); (3) whether the
bytes-vs-characters decision survives contact with a real multibyte note, which
QUE-002's pagination question will force.
