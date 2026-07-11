---
name: satan-memory-handover
description: SATAN memory substrate handover — current state, file map, gotchas, working agreements
metadata:
  type: handover
  topic: satan-memory
  status: living
  updated_at: 03398479
  verified_at: 03398479
---

# SATAN — Memory Substrate Handover

SATAN's canonical-handle memory substrate v1 is **complete**. Twelve
implementation steps landed between 2026-05-19 and 2026-05-20; the
broker dispatches `memory_mark` / `memory_resonate` / `memory_show_trace`
from morning, motd, tick-pulse, self-edit-{mech,mind}; `bough_read` is
the only path into bough; `hippocampus_write` emits an `auto_rule`
cross-ref trace per write; grammar v2 fixture + renormalize CLI land
end-to-end. There is no "next step" in the original v1 plan. The
deferred quality sweep is **done** (§1 `b27236ff`, §2 `fb4bbe8a`,
§3 `936a07ed`, §4+§7 `2f8fdc78`, §6 `169da374`); the DR-116 follow-up
landed 2026-05-21. The only work ahead is the explicit v1 non-goals,
if the user wants to start a v2.

## Read in this order

1. `~/.emacs.d/docs/satan/governance.md` — broker invariants, ownership rules, file map
   (now includes the memory modules + migrations + tool handlers).
2. `~/.emacs.d/memory.brief.md` — substrate principles ("memory is
   handle collision"), grammar policy, persistence addendum.
3. `~/.emacs.d/docs/satan/memory/design.md` — implementation target.
   Settled decisions §0; schema §6.2; tool surface §5; canonicalizer
   interface §3 incl. purity boundary §3.5; acceptance §9; open
   questions §10. §6.1 (psql R3) and §10.2 (bough CLI mapping)
   recorded as part of steps 1–2.
4. `~/.emacs.d/CHANGELOG.md` — chronological substrate narrative
   2026-05-19 → 2026-05-20.
5. `~/dev/panopticon/HANDOVER.md` (skim) — producer of
   `~/.local/state/behaviour/` which the evidence assembler reads.
6. `~/dev/vk/BRIEF.md` (skim) — bough's data model; traces address
   bough nodes by nanoid.
7. `~/.emacs.d/docs/satan/bough-gaps.md` — B1 / B2 upstream-pending bough
   CLI gaps. **B1 has DR-116 in flight; SATAN follow-up sequence is
   captured there.**

## Status

| Item                              | State                                          |
|-----------------------------------|------------------------------------------------|
| Design doc (`design.md`)          | Complete; §6.1 R3 + §10.2 mapping recorded     |
| Persistence brief                 | Authored upstream (`memory.brief.md`)          |
| Step 1 — bough CLI mapping        | Done · `b13ff975`                              |
| Step 2 — migrate runner + schema  | Done · `22c79f44`                              |
| Step 3 — `bough_read` tool        | Done · `be4227f6`                              |
| Step 4 — grammar constants + sync | Done · `b6566a1f`                              |
| Step 5 — canonicalizer + lint     | Done · `0424aed1`                              |
| Step 6 — evidence assembler       | Done · `43e9e718`                              |
| Step 7 — store backend            | Done · `ee384c81`                              |
| Step 8 — memory_* handlers + desc | Done · `6046db78`                              |
| Step 9 — aggregator + allowlists  | Done · `cbb80d22`                              |
| Step 10 — renormalize CLI         | Done · `53ebd992`                              |
| Step 11 — acceptance §9 + docs    | Done · `7e5fdbce`                              |
| Step 12 — hippocampus cross-ref   | Done · `8253a5a1`                              |
| `satan_memory` PG database        | Created; migrations 0001–0003 applied; 0004 pending (operator-applied) |
| `satan_memory_test` PG database   | Created; migrations 0001–0004; used by all DB ert |
| Tests at memory subsystem HEAD    | 119/119 ert (9 mig · 6 gram · 33 canon · 16 ev · 18 store · 28 tool · 6 renormalize · 3 hippocampus); §9.10 bough-isolation lint is canon test #33 |
| Phase-3 ert                       | 87/87                                          |
| Integration ert                   | 1/1 against jailed fake harness                |
| Bough gap brief                   | `../bough-gaps.md` — B1 has DR-116 in flight |

## Settled decisions (mirror of design §0)

1. SATAN canonicalizes deterministically; no LLM inference in handle
   assignment. Model supplies typed *hints*; canonicalizer validates.
2. Traces may originate from `llm_mark`, `auto_rule`, or `external`.
   v1 ships `llm_mark` via tools and `auto_rule` via the hippocampus
   cross-ref hook.
3. Hippocampus directory was empty at start; cross-ref writes now
   land there alongside org files.
4. Storage: PostgreSQL, `satan_memory` (prod) + `satan_memory_test`
   (ert). Socket auth, no FDW.
5. Bough is read-only via `bough --json` exclusively. Enforced by
   `dl-satan-memory/bough-isolation` lint (acceptance §9.10) — refuses
   `bough_production`, `bough_agent`, `dl-satan-bough-program`,
   `dl-satan-bough--invoke` in any `dl-satan-memory-*.el`.
6. Grammar evolves at boundary. Every trace carries `grammar_version`;
   replays from `metadata_json` + per-handle `source`. v2 fixture
   shipped (`0004_grammar_v2_fixture.sql`); renormalize CLI lands
   handle-set diffs idempotently.

## Quality sweep — actionable now

Surfaced across steps 7–12. None block the substrate; each is a
small, well-scoped cleanup. Pick any without coordination needed.

1. ~~**`:items` schema accepts only scalar types.**~~ Done · `b27236ff`
   (sweep §1): `:items` now accepts a constraints plist (incl
   `:type 'object` + `:shape`) and the validator has a `:type 'array`
   branch that rejects non-arrays and validates each element.

2. ~~**Tool-ctx lacks evidence-assembly fields.**~~ Done · `fb4bbe8a`
   (sweep §2): `--tool-ctx` now exports `:run-started-at` and
   `:time-now`; memory + hippo handlers consume them and forward
   `:run_started_at` to `evidence-assemble`. Wall-clock fallback
   preserved for older fixtures.

3. ~~**`canonicalize-from-raw` drops normalized hint scalars.**~~ Done ·
   `936a07ed` (sweep §3): result plist gains `:normalized PLIST`;
   `--mark-impl`, `--derive-cue-handles`, and hippo `--cross-ref`
   each now run a single `canonicalize-from-raw` and read kind /
   valence off the result.

4. ~~**Store-mark `:source` docstring drift.**~~ Done · `2f8fdc78`
   (sweep §4): docstring says `:source PLIST` now.

5. ~~**Outcome canon path dormant.**~~ Done · documented
   dormant-by-design (sweep §5): `design.md` §8.1 records the
   v1 split — outcome traces belong to the future scorer lane
   (`trace_origin = auto_rule`), not the LLM `memory_mark` lane.
   No canon rule, no hints-shape entry, no handler plumbing.
   Server-side §9.12 invariant remains load-bearing for the v2
   scorer.

6. ~~**`memory_resonate.cue` derives full evidence even for cue-only
   paths.**~~ Done · `169da374` (sweep §6): assembler accepts
   `:cue_only t`; cue derivation skips `focus_segments`,
   `browser_segments`, `bough_recent`, `bough_day`. Keeps
   `current_window`, `bough_active`, `git_state`, `fs_state`.
   `--derive-cue-handles` opts the cue path in; `--mark-impl`
   stays full-window.

7. ~~**`dl-satan-tool--validate-arg` missing `:type 'number` branch.**~~
   Done · `2f8fdc78` (sweep §7): validator rejects non-numeric values
   on `:type 'number`; `memory_resonate` handler check dropped.

## DR-116 follow-up — DONE 2026-05-21

Bough DR-116 shipped (`node status-history <NANOID>`,
`node status-transitions`, `node created`).  SATAN follow-up landed
on 2026-05-21:

1. `dl-satan-bough--scope-recent-changes` now invokes
   `node status-transitions --since` + `node created --since`,
   returns `:transitions` / `:created` peer arrays.  Old
   `node tree --after updated_at=…` proxy retired.
2. `dl-satan-memory-evidence--bough-recent` synthesizes
   `:event "status_changed"` per transition row and
   `:event "created"` per created row.  Wakes the previously-dormant
   canon rule `bough.recent_status_change`.
3. `node created` composed alongside `status-transitions` for the
   full "what's new + what moved" view (DR-116 D18).
4. `../bough-gaps.md` B1 closed; `design.md` §10.2 mapping
   row updated.

`bough_read project_subtree` also still post-prunes depth in elisp
(bough gap B2 — `--max-depth N` flag absent). Unlikely to move soon;
no canon rule depends on it.

## v1 non-goals (open candidates for v2)

All admitted by the schema and design; deferred by policy. See
`design.md` §10 and §8.

- **Decay daemon.** `traces.strength` + `base_strength` admitted
  with `recency_decay = identity` in v1; no scheduler runs.
- **`memory_touch_traces` / `memory_reinforce`.** Read tools are
  read-only in v1 (no `access_count` / `last_accessed_at` mutation).
- **Auto-marker rules** (`trace_origin = 'auto_rule'` writers other
  than the hippocampus cross-ref hook). Hippocampus is the only
  auto-marker today. Next obvious targets per design §10.9: bough
  `status: todo→done` transitions; explicit user-keystroke marker;
  editor compile/test failure hook.
- **Outcome scorer.** A predictor + scorer that emits paired
  `prediction` + `outcome` traces; design §8 sketches the mapping.
- **Bias-into-prompt.** Tick-pulse system prompts could auto-inject
  top-k resonance matches — composes above the substrate, not part
  of it.
- **Payload privacy redaction.** Per-mark regex pass over `payload`.
  Pattern list lives notes-side (TBD).
- **Cross-DB FDW / bough_mirror tables.** B1 forbids; defer until a
  recurring "resonate where bough_node is active" need appears.
- **`note` kind.** Curated semantic notes promoted to structured
  traces; for now `hippocampus_write` handles that surface and
  cross-refs via auto_rule.

## Standing verification

```sh
# Memory subsystem (DB-touching ert skip-unless `satan_memory_test'
# reachable; lint-only ert always run).
emacs --batch -L core -L lisp -L org -L satan -L satan/test \
  -l satan/test/dl-satan-memory-migrate-test.el \
  -l satan/test/dl-satan-memory-grammar-test.el \
  -l satan/test/dl-satan-memory-canon-test.el \
  -l satan/test/dl-satan-memory-evidence-test.el \
  -l satan/test/dl-satan-memory-store-test.el \
  -l satan/test/dl-satan-tools-memory-test.el \
  -l satan/test/dl-satan-memory-renormalize-test.el \
  -l satan/test/dl-satan-tools-hippocampus-test.el \
  -f ert-run-tests-batch-and-exit
# → 119/119

# Phase-3 unit ert.
emacs --batch -L core -L lisp -L org -L satan -L satan/test \
  -l satan/test/dl-satan-test.el -f ert-run-tests-batch-and-exit
# → 87/87

# Integration ert (boots the broker against the fake harness).
JAIL=$(nix build .#satan-jailed-fake-harness --no-link --print-out-paths)/bin/jailed-satan-fake-harness
SATAN_TEST_JAIL_BIN=$JAIL emacs --batch -L core -L lisp -L org -L satan -L satan/test \
  -l satan/test/dl-satan-integration-test.el -f ert-run-tests-batch-and-exit
# → 1/1

# Real-harness rebuild (also runs ruff).
nix build .#satan-jailed-gptel-harness --no-link --print-out-paths

# Operator-side renormalize status on the prod DB.
emacs --batch -L core -L lisp -L org -L satan \
  --eval "(require 'dl-satan-memory-migrate)" \
  --eval "(message \"%S\" (dl-satan-memory-renormalize-status))"
# → (:by-version ((1 . N)) :stale-traces 0) at v1 HEAD; bumps to
#    include (2 . M) after the operator applies 0004 + renormalizes.
```

## File map (substrate)

```text
~/.emacs.d/satan/
  dl-satan-memory.el                   aggregator + my/satan-memory-* commands
  dl-satan-memory-grammar.el           closed-world enums; v1 alias seed; default weights
  dl-satan-memory-canon.el             canonicalizer; rule registry (PURE — grep-lint)
  dl-satan-memory-evidence.el          evidence-window assembly (impure)
  dl-satan-memory-store.el             DB connection; mark/resonate/show backend
  dl-satan-memory-migrate.el           migration runner + renormalize CLI
  dl-satan-tools-memory.el             memory_mark / memory_resonate / memory_show_trace
  dl-satan-tools-bough.el              bough_read tool (shell-out)
  dl-satan-tools-hippocampus.el        hippocampus_write + auto_rule cross-ref hook
  memory/migrations/0001_init.sql      schema per §6.2
  memory/migrations/0002_grammar_v1.sql v1 grammar seed
  memory/migrations/0003_memory_functions.sql  memory_mark_trace + resonate + show + handle_weight_for
  memory/migrations/0004_grammar_v2_fixture.sql  operator-applied v2 fixture (planning -> phase:orientation)
  test/dl-satan-memory-migrate-test.el  ert (9)
  test/dl-satan-memory-grammar-test.el  ert (6 — pure + DB sync)
  test/dl-satan-memory-canon-test.el    ert (33; rules + golden fixtures + purity + §9.10 bough-isolation)
  test/dl-satan-memory-evidence-test.el ert (16)
  test/dl-satan-memory-store-test.el    ert (18)
  test/dl-satan-tools-memory-test.el    ert (28; mark/resonate/show handlers + dispatch)
  test/dl-satan-memory-renormalize-test.el ert (6; no-op / bump / idempotent / per-trace-tx / status / §9.8)
  test/dl-satan-tools-hippocampus-test.el  ert (3; cross-ref soft-fail / gated / present)
  test/canon-fixtures/                 JSON fixtures for golden canon tests
  ../bough-gaps.md                     upstream brief (B1 DR-116 in flight, B2 deferred)
  design.md                            design doc — implementation target
~/notes/satan/tools/
  bough_read.md
  memory_mark.md
  memory_resonate.md
  memory_show_trace.md
```

Naming (per [docs/emacs/naming.md](../../emacs/naming.md)): module symbols `dl-satan-memory-*`, public
internals `dl-satan-memory-<name>`, private `dl-satan-memory--<name>`,
user commands `my/satan-memory-*`.

## Gotchas worth remembering

### psql plumbing (step 7)

- `psql -c "SQL"` does NOT perform `:'var'` substitution. Variables
  bound via `-v` only expand when SQL is read from a file or stdin
  (`-f -`). Store + renormalize feed via stdin.
- `psql -A -t` defaults the field separator to `|`; multi-column
  selects use `-F` with a literal tab.
- `||` against a `text[]` column is array-prepend, not string concat.
  Cast to text explicitly.
- `(json-encode plist)` is ambiguous between list-of-plists and
  plists. `json-serialize` is typed; the store uses it exclusively.
- `json-serialize` treats `nil` as `{}` (empty object). For NULL
  fields, pass `:null` explicitly. `--prep-plist` /
  `--null-if-nil` handle this in the store.
- `boolean::text` in PG yields `'true'/'false'`, not `'t'/'f'`. The
  renormalize-test handle parser learned this the hard way.

### store `--prep-value` (step 12)

- Previously only handled plists and lists-of-plists. Lists of
  scalars (e.g. `:tags ("ux")` from real bough nodes) tripped
  `json-serialize`. Step 12 generalised: any non-plist list →
  vector; symbols → strings. Latent since step 7; first surfaced by
  the hippocampus cross-ref reaching real evidence.

### Canon (steps 5, 8, 10)

- Purity boundary is grep-lint enforced. Adding any of
  `shell-command` / `call-process` / `insert-file-contents` /
  `url-retrieve` / `current-time*` / `dl-satan-bough-*` to
  `dl-satan-memory-canon.el` fails `canon/purity-grep-lint`.
- `dl-satan-memory-canon-canonicalize-from-raw` drops the normalized
  hint scalars (sweep §3 above). Callers that need `kind` / `valence`
  call `normalize-hints` + `canonicalize` directly.
- Aliases (`dl-satan-memory-grammar-aliases`) are resolved ONLY for
  the `phase` hint field — open-world fields (topic, focal_app) are
  slugged and pass through unchanged. The v2 fixture
  (`planning -> phase:orientation`) exploits this.

### Renormalize (step 10)

- `dl-satan-memory-renormalize` is idempotent: skips the per-trace
  transaction when the new handle set equals the currently-active
  set. Always opens a separate BEGIN/COMMIT per trace via stdin to
  psql — one failing trace cannot abort the rest.
- Adding the v2 fixture migration (`0004`) means every test reset
  applies it; tests that need v1-shaped output mark traces with
  `:grammar-version 1` explicitly. Tests that exercise v2 `cl-letf`
  the grammar constants — the elisp `defconst`s rebind cleanly via
  `(symbol-value ...)` under dynamic scope.

### Hippocampus cross-ref (step 12)

- Cross-ref is gated on the calling mode holding `memory-write`
  capability. Without it, the org file is written but no trace is
  emitted (existing hippo ert with `:capabilities (hippocampus-write)`
  only stay green this way).
- Cross-ref errors are soft-logged via `message`; the file write is
  load-bearing and never gated on substrate availability.

### Schema gaps (step 8)

- `dl-satan-tools.el` `:type 'object` validation walks `:shape`
  recursively but has no `:type 'number` branch (sweep §7); handlers
  validate numerics themselves.
- The schema validator short-circuits on nil values regardless of
  `:shape`; optional object args (`memory_mark.hints`,
  `memory_resonate.cue`) get no validation when absent. Safe for the
  two current consumers; reconsider if a non-optional object lands.
- The broker's tool-ctx now carries `:run-started-at` and
  `:time-now` (closed by sweep §2 · `fb4bbe8a`). Memory + hippo
  handlers consume them and forward `:run_started_at` to
  `evidence-assemble`; the 10-minute fallback only applies when
  the tool-ctx omits the field (older fixtures and unit tests
  that build a tool-ctx plist by hand).

## Working agreements

- TDD per project CLAUDE.md: red, green, refactor. Lint as you go.
- Two-space indent in elisp; convention `dl-satan-*` / `my/*`.
- Wired into Nix. Adding a new `.el` file requires `git add` +
  `home-manager switch --flake ~/flakes#david` before the
  `use-package` form is parsed. See [docs/emacs/traps.md](../../emacs/traps.md).
- `:ensure nil` is a "don't install" signal for the Nix overlay
  parser. If you need a package not in `extraEmacsPackages`, add it
  to `~/flakes/modules/home/emacs.nix`.
- Native-comp vars must be `append`-ed, never `setq`.
- DB work: socket connection (`host=/run/postgresql`), owner
  `david`. Test DB pattern: `<thing>_test`. Reset macro lives in
  each `*-test.el` that touches a DB.
- This file (`handover.md`) is now tracked in git as of the docs reshape
  (was gitignored at `satan/HANDOVER.md`). Committed counterparts:
  `governance.md`, `CHANGELOG.md`, `design.md`, `../bough-gaps.md`.

## Closed risks (history)

- **R1. Bough CLI scope gaps.** Closed; `design.md` §10.2
  records the mapping. Two scopes shipped with loosened semantics
  (`recent_changes` proxies via `updated_at`; `project_subtree`
  post-prunes in elisp). Both captured in `../bough-gaps.md` for
  upstream filing; DR-116 in flight for B1.
- **R2. Bough JSON output stability.** Addressed; pinned via
  `dl-satan-bough-program` defcustom; fail-fast on parse error in
  `dl-satan-bough--invoke`. Integration tests skip-unless `bough`
  is on PATH.
- **R3. Emacs PG client choice.** Closed; `psql` subprocess (§6.1).
  Migrations + store + renormalize all shell out.
- **R4. Grammar drift elisp vs DB.** Closed;
  `dl-satan-memory-grammar/db-sync` ert asserts
  `MAX(grammar_versions.version) ==
  dl-satan-memory-grammar-current-version` and that aliases +
  default weights match.
- **R5. Migration runner skip-version + checksum.** Closed;
  refuses tampered, missing, and out-of-order versions; per-file
  body + bookkeeping insert in one `--single-transaction`.

## Commit log (substrate)

- `b13ff975` — §10.2 bough scope mapping recorded
- `22c79f44` — migrate runner + 0001/0002 SQL + both DBs created
- `be4227f6` — `bough_read` tool with six scopes
- `b6566a1f` — grammar v1 elisp constants + drift detector
- `0424aed1` — canonicalizer + purity grep-lint + golden fixtures
- `43e9e718` — evidence assembler + 16 ert
- `ee384c81` — store backend + migration 0003 + 18 ert
- `6046db78` — memory_mark / memory_resonate / memory_show_trace + 28 ert
- `cbb80d22` — aggregator + mode allowlist wiring (first shared-file touch)
- `53ebd992` — renormalize CLI + 0004 fixture + 6 ert
- `8253a5a1` — hippocampus cross-ref hook + store `--prep-value` fix + 3 ert
- `7e5fdbce` — acceptance §9.10 bough-isolation lint + SATAN.md / bough-gaps.md docs
- `2f8fdc78` — memory quality sweep §4 (docstring) + §7 (number validator)
- `b27236ff` — memory quality sweep §1 (:items SHAPE + :type 'array validator)
- `936a07ed` — memory quality sweep §3 (canonicalize-from-raw returns :normalized)
- `fb4bbe8a` — memory quality sweep §2 (tool-ctx :run-started-at / :time-now)
- `169da374` — memory quality sweep §6 (:cue_only evidence knob)
