# Notes SL-011: SATAN tick performance: observe and bound

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## Implementation via /dispatch (PHASE-01..04 landed on `dispatch/011`)

Driven through the claude dispatch arm; workers self-commit via `worker_commit`,
orchestrator lands via `dispatch_import` → `dispatch_conclude_phase` → reap. Per-
batch verify beat = coord-tree `just check` (the `check regression` harness is
unconfigured here — defaults to cargo; `check prove` ⇒ absent `just prove`). Test
postgres must be up or `just check` is red and blocks `worker_commit`. See memory
`dispatch-prereqs-emacs-d`.

## Reconciliations for /audit (design §2 named some sites by shorthand)

- **PHASE-03 F-a**: bough choke is `dl-satan-bough--invoke` (tools-bough.el), not
  the elisp wrapper `--bough-call`/`bough-read` the design named. Real subprocess
  routed.
- **PHASE-03 F-b**: sway fn is `dl-satan-sway--swaymsg` (design said
  `tools-sway--call`); defcustom `dl-satan-sway-timeout-seconds` uses the file's
  existing `dl-satan-sway-` prefix (not design's `dl-satan-tools-sway-`).
- **PHASE-03 F-c**: `dl-satan-bough--invoke` captured stderr to a temp file;
  `trace-call` returns only `(:exit :stdout :timed-out)`. Concession: bough now
  routes with COMBINED stdout+stderr in `:stdout`; error text may include both. No
  VT asserts exact bough error text.
- **PHASE-03 adaptations**: git sites resolve the program via `executable-find`
  (absolute path) so the `timeout` wrapper resolves it via PATH — keeps the
  PHASE-01 stub-git test green under the folded `:env`. `test-sway-border.el` stub
  reseated from `call-process` → `dl-satan-trace-call` (the routing wraps argv in
  `timeout`, so the raw-argv seam moved). migrate `--fetch-traces` passes explicit
  `nil` INPUT before `:timeout-secs nil` (cl-defun `&optional`+`&key` ordering).
- **PHASE-02→04 seam**: PHASE-02 built `with-tick` flushing a placeholder
  `"ok"/"error"` outcome; PHASE-04 added `dl-satan-trace-outcome` + threaded the
  domain outcomes (`spawned|budget_denied|session_blocked|perceive_failed`). Clean
  phase split, not a PHASE-02 miss.
- **PHASE-04**: `dl-satan-db.el` `db-query`/`db-psql` are now `cl-defun` with
  `&key label (timeout-secs dl-satan-db-timeout-seconds)`; all pre-existing
  positional callers unchanged. 3 broker gate tests bind `dl-satan-trace-enabled
  nil` (write hygiene — avoid real tick rows into `~/.local/state/satan/` when the
  suite runs unjailed).
- **PHASE-04**: `dl-satan-trace-subprocess` gained a trailing optional `label`
  arg (reconciles the "reuse for the row" + "label on the row" mandates).

## PHASE-05 (tick wall budget) — landed on `dispatch/011`

Wired the pre-built budget primitives (`-stage-optional`, `--budget-exhausted-p`,
`:budget-ms`) into the 5 optional stages. Reconciliations:

- **`with-tick` seeded `:budget-ms` from `dl-satan-trace-tick-budget-seconds`**
  (new defcustom, default 10s, nil=unbounded) — PHASE-02 built it hard-nil.
- **sensor_status `:content` degrade** keyed on `content-probe` being nil:
  both non-optional branches (cue-only, probe-ran) return a cons, so nil ⟺
  budget-skip → `"budget_skipped"`. No accumulator re-read.
- **resonance degrade via `or`-fallback** — `dl-satan-resonance-derive` never
  returns nil, so `(or (stage-optional …) (list :status 'budget-skipped …))`
  fires only on skip. `render-block` emits only on `:status ok` → any other
  status self-suppresses (nil block). Kept the macro generic.
- **5th optional `recent_runs`** was UNWRAPPED (PHASE-04 wrapped only 4) —
  added `-stage-optional "spawn.recent_runs"` in `--recent-runs-for-spec`,
  nested under core `spawn.bundle`. `render-recent-runs` already nil-tolerant.

## PHASE-06 (confinement + patch ledger) — landed on `dispatch/011`

- `dl-satan-patch-worktree--assert-owned` — `file-truename` prefix guard, hard
  `error` (tree write = corruption, not a degrade). Called before the two
  mutating git ops (`worktree add`, `worktree remove --force`). `branch -D`
  left unguarded (mutates a ref, not a tree). Read-only ops exempt.
- `--git` routed through `trace-call` (`:label "patch.git"`, `:timeout-secs`
  from new `dl-satan-patch-worktree-timeout-seconds`=30), NO `GIT_OPTIONAL_LOCKS`
  (patch ops exempt, EX-2). Contract-neutral: `trace-call` uses the SAME
  `call-process … nil t nil` combined-buffer capture as the old `--git`, so
  `(ok . STDOUT)/(error . MSG)` is preserved; timeout surfaces as
  `(error "git exit 124: …")` on the existing error path.

## PHASE-07 VA-1 residue sweep — CLEAN (agent verification)

No unaccounted direct psql/git/bough/swaymsg subprocess outside the choke
points. Only design-sanctioned direct git is `dl-satan-tools-vcs.el:64`
`--git-repo-p` (read-only `rev-parse --git-dir`, inline `GIT_OPTIONAL_LOCKS=0`,
design §2-exempt). Async daemon NOTIFY streamers (attribute/patch listeners)
are `make-process` of custom rust binaries, not psql, not per-tick chokes.
Everything else swept is rg/fd/calendar/logger/harness-child.

## PHASE-07 VH-1 live run (2026-07-11) + FINDING-1 (ledger fix)

Real `dl-satan-broker-run "tick-pulse"` in the live image → **tick row perfect**
(full attributable stage map, budget fields, `outcome:"spawned"`, `skipped:[]`).
`with-tick` binds correctly; the transient "0 tick rows / run_id:{}" scare was
background-daemon activity outside any tick (correct pass-through).

**FINDING-1 (VH-1, confirmed + fixed):** the subprocess ledger was LOSSY —
`json-serialize` throws `json-value-p` on a **unibyte** argv string (a
`payload={…—…}` psql persist arg carrying raw UTF-8 bytes), swallowed by the
never-fail-the-tick writer → row silently dropped. Root cause was pre-existing
in the shared `dl-satan-jsonl-prepare` (symbols/alists coerced, unibyte strings
not); SL-011's ledger was the first caller to feed it unibyte argv at volume.
Fix (corrective on `dispatch/011`): add
`((and (stringp v) (not (multibyte-string-p v))) (decode-coding-string v 'utf-8))`
+ 3 tests. `jsonl.el` + test declared design-target. Multibyte strings pass
through untouched. Awaits live re-verify before PHASE-07 conclude.

**FOLLOW-UP (cosmetic):** unbound-tick subprocess rows render `"run_id":{}`
(nil→`{}`) not `null` — backlog, not slice-blocking.

## Selectors

Declared design-target selectors from design §5 mid-drive (were empty at plan
time — declare BEFORE `dispatch_import` or its classify belt rejects
`undeclared-scope`). 21 selectors now cover the §5 targets + touched test files.
