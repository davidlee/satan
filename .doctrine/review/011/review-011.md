# Review RV-011 — reconciliation of SL-017

Adversarial-review ledger (ADR-007). Structured findings live in the sister
ledger toml; this prose companion carries the reviewer's framing.

## Brief

Conformance audit of SL-017 PHASE-01..07 (commits 7069160..82de4c5, main
worktree, capsule-driver run). PHASE-08 (deploy + live checks, VH-1) is not yet
run and is out of this audit's evidence; its criteria stay open.

Lines of attack:

- **Design conformance** — each phase against `design.md` sec-2..sec-6 and the
  invariants (one emit seam; record before emit; one tool-ctx; spawn never
  fails silently; announce policy keyed on `final.json` `:reason`). Every
  recorded deviation in `notes.md` is dispositioned here, not left in notes.
- **Path conformance** — `doctrine slice conformance 17`: undeclared
  (`docs/governance.md`, `notes.md`) and undelivered (three test files).
- **Evidence** — full gate run by the auditor (`SATAN_DB_HOST=/run/postgresql/
  just check`: 1085 ran / 1081 expected / 1 unexpected / 3 skipped; the
  unexpected is the pre-existing env-dependent
  `satan-db/test-db-available-p-probes-test-host`, tracked by ISS-008/ISS-009);
  harness `python -m unittest` 54 OK; `verify-vt 17` 16/16 PASS;
  `doctrine coverage verify 17` verified. `doctrine check gate` is not wired
  here (no `just gate` recipe; project gate is `just check`).
- **Code review** — PHASE-04/05/06 reviewed separately on RV-012 (RV-010's
  recommendation); its findings are dispositioned there.
- **Test hermeticity** — design R8 and the live-state/production-DB leaks
  (ISS-018, ISS-019 filed during execution).
- **Reconcile follow-ups carried from plan.md** — the ADR-017 authority-ledger
  row 4 standing note REV and the `session_blocked` correction to
  mem_eb8e5cff794c48bd86597f94fa50b0ac.

## Synthesis

**Verdict: PHASE-01..07 conform to the locked design.** Every deviation the
phases recorded was a local ruling that keeps the design's intent; none
changes an invariant. Evidence at 2d6c0da: full gate 1088 ran / 1084
expected / 1 unexpected / 3 skipped (the unexpected is the pre-existing
env-dependent `satan-db/test-db-available-p-probes-test-host`, ISS-008 /
ISS-009); harness unittest 54 OK; `verify-vt 17` 16/16 PASS; `coverage
verify 17` verified; `just lint` clean; no new byte-compile warnings.

What the slice now guarantees (design sec-2..sec-6):

- **One emit seam.** Only `satan-announce.el` calls `notifications-notify`
  or `logger` outside tests; the suite runs against a recorder and writes
  nothing to the journal.
- **Record before emit.** `notify_send` appends `intervention.created`
  before any pop. An undelivered pop is marked `undelivered:` and, since
  RV-012 F-2, projected with its verdict in one transaction. The cooldown
  arms on the record.
- **One tool-ctx**, built from the run struct; the sensor-alert builder is
  gone.
- **A spawn cannot fail silently.** A pre-child error ends `failed` /
  `spawn_failed`, renamed and announced; a post-child error is re-raised
  and finalised once by the sentinel. The lock clears on every path.
- **Persistent failures stay loud.** Per-mode, same-cause streak walked
  from run outcomes, keyed on `final.json` `:reason` (never the display
  reason). Pops at positions 1, 2, 4, 8…; `auth` always; budget once;
  `session_blocked` / `credential_deferred` transparent.

Code review (RV-012, PHASE-04..06): no blocker or major. Five findings were
fixed in audit (2d6c0da): undelivered projection atomicity, two tests
reading the live corpus, an over-reporting crash-context flag, a weak ctx
guard, and duplicated no-child records. The audit's own F-10 (announce tests
depending on the quiet-hours default) was fixed in 417a831.

**Standing risks**

- **Not live yet.** PHASE-08 (push, `nix flake update satan`, home-switch,
  VH-1 live check) is outstanding. Until the live Emacs reloads, ISS-012's
  silent `motd`/`morning` failures are fixed only in the repo.
- **On reload**, pre-spawn sensor alerts start writing intervention rows to
  the live `satan_memory` and arming their cooldown (the ISS-016 fix).
- **The test suite reaches production.** `SATAN_DB_HOST=/run/postgresql/`
  slips past the production-socket guard (ISS-009), and existing classify /
  manual-writer / observer tests enqueue into production
  `satan_outcome_inbox` (ISS-019). The live ingest cursor was reachable
  from spawn tests until PHASE-05 (ISS-018). SL-017 adds no new leaks;
  it doesn't close these.
- **REQ-003 is partly met.** Only the notify path records before its side
  effect; sway / inbox / proposal / patch are PHASE-08 EX-2's backlog item.

**Tradeoffs consciously accepted**

- F-4 / F-5: two plan criteria (PHASE-04 VA-2, PHASE-02 VT-2) can't be
  amended in place. Their intent is evidenced by named tests and an
  auditor `rg` check.
- F-12: `:dispatched_at` records dispatch, not delivery; nothing reads it.
- Doctrine tooling friction (observations recorded): subagent hand-backs
  misrouted throughout the capsule run; `verify-vt` needs `record-delta`
  per phase; `coverage show` reads stale after a verified re-derive;
  `doctrine check gate` has no `just gate` here.

## Reconciliation Brief

### Per-slice (direct edit)

- **design.md sec-4** (F-1): the spawn-failure handler kills the stderr
  buffer only when no child exists. With a live child, the stderr-flush
  sentinel wrapper (installed right after `make-process`) owns it.
- **design.md sec-5** (F-2): `:id :null` for an undelivered pop. The
  intervention and its verdict project in one transaction
  (`satan-intervention-project-with-verdict`, RV-012 F-2), which supersedes
  the "skip the verdict if the intervention projection fails" ruling.
  `satan-intervention-create` takes an explicit keyword list. The
  undelivered verdict's `evidence_json` is JSON null.
- **design.md sec-6** (F-3): parameter `mode-slug`; with both kill switches
  off `satan-announce` is not called.
- **Selector registry** (F-7): `doctrine slice selector add` a design-target
  selector for `docs/governance.md`. Mirror in the design.md sec-6 file
  table.
- **Selector registry** (F-9): `doctrine slice selector rm` the three
  undelivered selectors (`satan/test/satan-context-test.el`,
  `satan/test/satan-intervention-mark-test.el`,
  `satan/test/satan-tools-atsatan-test.el`). Mirror in design.md sec-6, with
  the id-parser row pointing at IMP-022.

### Governance/spec (REV)

- **ADR-017 authority-ledger row 4 standing note** (F-13): REV naming the
  two operational alarms, failure announcements and listener death reports,
  as non-intervention emits outside the single audit writer.
- **REQ-003** (F-11): status stays `pending` (partial: notify path only).
  Optionally, a REV adding an acceptance criterion (plan.md Notes).

### Memory

- **mem_eb8e5cff794c48bd86597f94fa50b0ac** (F-14): replace the global
  failure-streak counter claim with the per-mode, same-cause streak walked
  from run outcomes. `session_blocked` and `credential_deferred` are
  transparent.
