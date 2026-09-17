# Review RV-005 — reconciliation of SL-015

Adversarial-review ledger (ADR-007). Structured findings live in the sister
ledger toml; this prose companion carries the reviewer's framing.

## Brief

**Subject.** SL-015 — the three-root corpus relocation. Four phases complete,
lifecycle at `audit`. **Surface reviewed:** the main worktree at `7f8969d`
(clean); not a dispatched slice, so there is no candidate branch — `review/*`
and `phase/*` do not apply.

**Verification environment.** The suite was run as design §9.2 mandates:
`SATAN_DB_HOST=/run/postgresql/ just check` → **1044 ran / 1040 expected / 1
unexpected / 3 skipped**, the one unexpected being the known
environment-dependent `satan-db/test-db-available-p-probes-test-host`. That is
exactly the bar PHASE-04 recorded. `doctrine check gate` does not run here
(§F-7). Exit status carries no signal (ISS-008), so green means the counts, not
`$?`.

### Lines of attack

1. **Did the ground actually move?** Every phase exit criterion that names a
   filesystem, repo, or defcustom fact, checked directly rather than read out of
   the notes: `~/notes/satan` absent with no symlink standing in (D4/EX-9), the
   corpus repo's history and remote, the state root's contents, the two retired
   workarounds, the jail binds.
2. **Is the mechanical drift signal real?** `doctrine slice conformance SL-015`
   against the recorded source-deltas — the one check that does not take the
   slice's own word for its scope.
3. **Does the design still describe what was built?** SL-015 corrected itself
   five times in flight (three recounts, two false premises). The hazard is the
   opposite of the usual one: not that the design is unrealistic, but that the
   *record* of it is stale where execution overtook it — settled open questions
   still written as open, and facts the ground disproved still asserted.
4. **Is the inventory honest about its own misses?** R5 ("a consumer missed
   from §2.4") is the risk this slice was most exposed to. It fired. The
   question is whether the design says so.
5. **Did the invariants survive?** I1 (no `satan/` literal in a root-anchored
   join, modulo the D10 allowlist), I2 (`satan-custom.el` a zero-dep leaf), I3
   (notes read-only to SATAN), and the §2.2b ownership line that keeps
   panopticon's `behaviour/` tree out of the state class.
6. **Are the follow-ups real, and are they closed?** Seven items were filed
   across PHASE-02/03/04. A follow-up that is discharged but still `open`, or
   one that was never filed at all, both defeat the purpose.
7. **Governance untouched?** The slice declares POL-001 / ADR-017 §3 unaffected.
   Verified by grep over `.doctrine/{adr,policy,standard}`: zero references.

## Synthesis

**The slice did what it set out to do, and the ground proves it.** SATAN now
resolves every owned path through one of three named roots. `~/notes/satan` does
not exist; nothing stands in for it. `~/satan` is a standalone repo carrying 32
commits of real pre-split history, remoted and pushed. Runtime state — 9.4k run
bundles, the wpm telemetry, the sensor cursors, 70 tick traces — sits under
`~/.local/state/satan`. Both nesting workarounds are gone: the denote exclusion
regexp and the atsatan `!**/satan/**` glob had no referent left and were
retired. The invariants hold: `satan-custom.el` is still a zero-dependency leaf,
the D10 allowlist survives at exactly the two expressions it names, and
panopticon's `behaviour/` tree stayed out of the state class at all three sites.
Governance is untouched, as declared — zero references under
`.doctrine/{adr,policy,standard}`.

Eleven findings. **No blockers.** Six go to `/reconcile`, one was fixed here,
two are tolerated with rationale, two are aligned observations.

### What the findings are actually about

They are not about the change. They are about the **record of it**.

The slice corrected itself five times in flight — three recounts, two false
premises (D1's trailing-slash rationale, D5's non-existent systemd pin). It
corrected them well: each correction was written into the design in place,
struck through, dated, with the evidence. That discipline is why this audit
found nothing broken. But the same discipline was applied unevenly at the end.
OQ-1 got its resolution written into §6; OQ-4 and R7 were settled just as firmly
in PHASE-03 and still read as open (F-4). F1 names the wrong process as the wpm
writer, four weeks after PHASE-02 proved on the ground it was `wpm-daemon`, not
waybar (F-2). §2.4 is still called "the scope boundary" and D4 still rests on
its completeness, though it was two consumers short and the sweep is what
covered them (F-3). `slice-015.md` §Summary is an empty heading and §Follow-Ups
lists the three items known at design lock, not the eight actually filed (F-5).

The pattern is consistent: **execution outran the documents, and the delta
lives in `notes.md`.** That is the correct place for it during a slice and the
wrong place for it after one. `notes.md` is the scratchpad; `design.md` is what
the next migration reads.

F-1 is the same failure in mechanical form. The `design-target` selector
registry declares two paths against 28 the slice edited, so `slice conformance`
reports 59 undeclared / 2 conformant — the one check that does not take the
slice's word for its own scope is inert here. Nothing was hidden by it; the 28
are all legitimately in scope and were verified by hand. But the signal was
unavailable for the whole slice, and the fix is a registry call, not prose.

### Standing risks

- **The gate cannot fail.** `doctrine check gate` does not exist here (F-7), and
  the thing it would delegate to exits 0 regardless of failures (ISS-008). With
  lint being paren-balance only, ~130 tests skipping silently without DBs, and
  now concurrent runs corrupting the shared schema (F-8 → ISS-013), this repo
  has **four independent ways to report a false result**. Every gate claim in
  SL-015's record is therefore a claim about *counts under a named invocation*,
  and it has to stay that way until ISS-008 lands. Adding a `gate` recipe before
  then would convert a loud absence into a silent pass.
- **The documented invocation depends on a defect.** `SATAN_DB_HOST=/run/postgresql/`
  works only because the trailing slash slips past a guard comparing with
  `equal` (ISS-009). Fix the guard and every gate in this slice's record becomes
  unreproducible (F-9). They move together.
- **Open follow-ups are real work, not bookkeeping.** CHR-004 (self-edit prompts
  still describe the pre-SL-012 layout) is a live correctness gap in
  model-facing text — the same class F2 exists to prevent. ISS-012 (motd and
  morning runs failing at turn 0 on an expired key) means two of the three
  scheduled modes have not produced a real result since late August, and
  `status: invalid` says nothing.

### Consciously accepted

- **Prose in the code repo was not part of the cutover** (D9). 16 `docs/` files
  still name `~/notes/satan`; the 17 production docstrings were fixed, and
  rewritten to name the defcustom rather than the path — text that cannot rot
  on the next move. The residue is CHR-006, on the record, not forgotten.
- **Historical run bundles keep stale absolute paths** (A2). 2,292 of the 2,835
  sweep hits are frozen evidence. Rewriting them would falsify the record.
- **No transitional symlink** (D4), and the bet paid: both missed consumers
  surfaced within the phase rather than months later, because the old path
  failed loudly.
- **`satan-patcher` stays punted** (D5/CHR-003), with its real editable surface
  — the flake module's `systemPromptFile` — fixed outside the punted repo.

### Closure position

Implementation is complete and verified. The reconciliation brief below is all
documentation: six per-slice edits, no governance REV, no code. Nothing gates
`reconcile`.

## Reconciliation Brief

### Per-slice (direct edit)

- **`slice-015.toml` selector registry — F-1.** Add intent `design-target` for
  the 28 source paths the slice edited: 19 `satan/*.el`
  (`satan-context`, `satan-ingest-cursor`, `satan-mode`, `satan-motive`,
  `satan-patch-prompt`, `satan-patch-worktree`, `satan-percept`,
  `satan-resonance`, `satan-sensor-alerts`, `satan-sensor-content`,
  `satan-sensor-curiosity`, `satan-sensor-wpm`, `satan-tools-atsatan`,
  `satan-tools-docs`, `satan-tools-hippocampus`, `satan-tools-inbox`,
  `satan-tools-org`, `satan-tools`, `satan-trace`), 7 `satan/test/*.el`
  (`satan-context-test`, `satan-custom-test`, `satan-integration-test`,
  `satan-run-test`, `satan-tools-atsatan-test`, `satan-tools-memory-test`,
  `satan-tools-patch-test`), `flake.nix`, `docs/perceptual-design.md`.
  Verb: `doctrine slice selector add SL-015 --intent design-target <paths>`.
  This is the load-bearing change — it is what `slice conformance` reads. Re-run
  `doctrine slice conformance SL-015` after: expect ~30 conformant, 0
  undelivered, and ~31 undeclared `.doctrine/**` bookkeeping (the house
  tolerance, cf. SL-013). This design template carries no §6 selector mirror,
  so there is no prose counterpart to update.

- **`design.md` §3 F1 and §5.4 S0 — F-2.** The wpm TSV writer is
  `wpm-daemon.service`, not "the waybar wpm module"; waybar's `custom/wpm` only
  reads `$XDG_RUNTIME_DIR/wpm.json`, so stopping waybar does not quiesce the
  writer. Correct both mentions. `~/.config/waybar/wpm-status.py` remains the
  correct file — it is what the daemon runs. Do **not** touch PHASE-02 EN-2,
  which carries the same wording: plan criteria are immutable-append and off
  this write surface.

- **`design.md` §2.4 and §8 R5 — F-3.** Add the two consumers the survey missed
  and PHASE-03 found on the ground: `~/nushell/config.nu` (nu is the login
  shell; the survey checked zsh only) and `~/notes/.pi/SYSTEM.md` (a tracked,
  generated build artefact inlining the old path). Mark R5 as **fired**, naming
  what it caught and the generalisation — a path sweep must cover every shell's
  config and generated-and-committed files. Temper the sentence in D4 that rests
  on "the surface inventory (§2.4) is complete enough not to need a net": the
  conclusion stands, but it was the mandated sweep, not the inventory, that
  caught these two.

- **`design.md` §6 OQ-4 and §8 R7 — F-4.** Both were settled in PHASE-03 and
  still read as open. Give them OQ-1's treatment. OQ-4 → RESOLVED: `~/satan`
  carries its own `justfile commit` recipe and no `.gitignore`; P5 holds because
  PHASE-02 left only authored content (`0634e37`). R7 → SETTLED: no
  `workspaceDeps` entry (the `satan` basename collision stands); dev jails get a
  raw rw bind at `/workspace/corpus` via a named `corpusJailOptions` list
  (`flake.nix:96`, verified 2026-09-17).

- **`design.md` §9.2 — F-9.** One line: the documented invocation
  `SATAN_DB_HOST=/run/postgresql/` is load-bearing on **ISS-009** — the guard it
  slips past compares with `equal` against the bare literal — so fixing ISS-009
  invalidates this invocation and the two must move together.

- **`slice-015.md` §Summary and §Follow-Ups — F-5.** §Summary is an empty
  heading; write what the slice delivered (three named roots with their
  ownership classes, runtime state split out, the corpus a standalone repo with
  history, both nesting workarounds retired). Rebuild §Follow-Ups from what was
  actually filed: CHR-003, CHR-004, CHR-006 open; CHR-005 resolved/done;
  ISS-008, ISS-009, ISS-010, ISS-011, ISS-012 open; ISS-013 raised in this
  audit. **Decide OQ-2 and OQ-3 here** — file each as a backlog item or record
  it as consciously dropped. A live open question on a closed slice is neither.

### Governance/spec (REV)

None. The slice declared POL-001 and the ADR-017 §3 authority ledger unaffected
and moved no authority item; verified by grep — zero `notes/satan` references
under `.doctrine/{adr,policy,standard}`. No spec or requirement registry exists
in this project yet (`plan.toml [specs]` empty by design).

### Handled in audit scope (no reconcile action)

- **F-6** — CHR-005 transitioned `resolved`/`done`; `~/satan` has remote
  `satan-corpus` with `HEAD == origin/main` at `0634e37`.
- **F-8** — filed as **ISS-013** (concurrent `just check` runs clobber the
  shared test databases), tagged, linked to ISS-008.
