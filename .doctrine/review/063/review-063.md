# Review RV-063 — reconciliation of SL-034

Adversarial-review ledger. Structured findings live in the sister
ledger toml; this prose companion carries the reviewer's framing.

## Brief

<!-- Pre-reading + lines of attack: what this review is probing, the invariants
     it must hold the subject to, and where the bodies are likely buried. Seeded
     at `review new`; the reviewer fills it before raising findings. -->

Mode: **conformance** (self-audit; one agent drives raiser and responder via
`--as`). Surface reviewed: the primary trees — satan @ 1d44fb4, malebolge @
578761c, satan-corpus @ a8b2db2. Not a dispatched slice.

Lines of attack:

1. **Design departures.** Every D-numbered departure in the phase sheets
   (`.doctrine/state/slice/034/phases/phase-0{1..8}.md`) and the live-check
   fix 578761c, against `design.md` sec-2/3/4/5/11/13. Behavioural departures
   (journal wording, rendered times, config validation, start failure) are
   design text to reconcile; user-accepted ones (PHASE-04 D10, PHASE-07 D9)
   only need the text.
2. **Journal table (sec-4) as the audit record of ledger row 4d.** Every line
   the code emits must appear in the table, or the table is wrong.
3. **Conformance algebra.** `doctrine slice conformance 34`: undeclared
   `justfile`, `test/flake/forms.test.ts` (1441304), `notes.md`; undelivered
   = the malebolge and corpus selectors (cross-repo).
4. **Verification evidence.** malebolge VTs read UNATTRIBUTABLE in
   `slice verify-vt`; evidence = per-sheet test→VT maps, negative controls,
   and a fresh `just check` in both repos at the heads above.
5. **Live behaviour (PHASE-08 VA-1/VH-1)** against sec-4 and sec-13,
   including the two-line tool cancel and the absent-`after_minutes` default.
6. **Governance writes (sec-6)**: ledger rows 4d/6d/7b, token, row 3b
   evidence, docs sentences; SPEC-002 REV owed at reconcile.

Invariants held: W1–W10 (design sec-1 Invariants), ADR-017 §3 (one owner
per duty) and §4 (fail closed), DEC-136 (governance lands with the change).

## Synthesis

**Closure story.** SL-034 delivered what the locked design asked: SATAN
schedules its own turns in the malebolge room daemon as pi-durable
`satan.wake` tasks. The host clamps them (WakePolicy v0), keeps one heartbeat,
sweeps blocked wakes at start, bounds every wait by one ceiling, and fails
closed behind `MALEBOLGE_WAKES`. All eight phases completed TDD with recorded
red evidence and negative controls. Gates re-run by this audit at satan
1d44fb4 / malebolge 578761c: malebolge `just check` exit 0 (lines 98.56%);
satan `just check`, `doctrine check gate` and `nix flake check` exit 0. Live
since 2026-10-28 09:47, with wakes on and accepted by the user (PHASE-08 VH-1).
The journal shows ensure, cancel, presence defer, fire and done; one more
fire/done in topic `default` at 10:08.

**No code defects found.** Every finding is design text lagging the code
(F-1…F-5), owed governance (F-9), tooling limits (F-7), an aligned live
observation (F-6), out-of-slice hygiene (F-8), or a known risk (F-10,
RSK-022). Nothing gates close.

**Standing risks.**
- RSK-022: room `bash`/`grep` have no per-call deadline, so a hung tool holds
  a placed wake input until the daemon restarts (F-10).
- No spend or rate limit in v0 (DEC-137); the gateway key cap is the backstop.
- `satan.wake` v1 input/checkpoint shapes are frozen by live rows. Any shape
  change needs a pi-durable task migration. PHASE-07 review m6: a
  migration-failed heartbeat leaves none until the next start.
- Not exercised live: heartbeat fire (first due ~11:47), failure path, sweep of
  a blocked wake. Tests cover all three (PHASE-04..07).
- Room VM runs UTC until the user's `/srv/fleet` change, so `localIso`
  renders `Z` there today. That is correct output for the zone, but the quiet
  window is evaluated in UTC until then (outside this slice).

**Tradeoffs accepted.** Cross-repo VT attribution is replaced by phase-sheet
test→VT maps plus re-run gates (F-7). The stale forms suite was deleted rather
than rewritten; its property lives in `quotient-forms` (F-8, user to confirm).
The PHASE-08 procedure predicted the floor for an absent `after_minutes`;
design sec-13 and the code both give one ceiling. The procedure note was
wrong; the sheet is disposable, so nothing is reconciled.

## Reconciliation Brief

### Per-slice (direct edit)
- design.md sec-2 Fire composition (F-1): `late_by` only on occurrence 0; heartbeat occurrences n≥1 omit it (the checkpoint `at` moves with defers).
- design.md sec-5 Config table (F-2): `MALEBOLGE_WAKE_TOPIC` must be a topic name and not `default` (reserved; start fails).
- design.md sec-4 journal table + sec-2 Failure (F-3): add the abort handler's `cancelled: already fired` and `withdraw failed: <message>`; the sweep's failure line without `n=`; `withdrew <k>` counts aborted answers, logged at 0. Make sec-2 step 1 match sec-4 (`n=<n>`), and name the `SATAN wake unanswered` notify title for a withdrawn heartbeat.
- design.md sec-2/sec-4/sec-13 (F-4): every model- and journal-facing time (`at`, `fired_at`, defer `until`) is local ISO-8601 with ms and offset (`localIso`, src/wake/local-time.ts). `wake_list` `at` is the next fire (the sleep's `until`).
- design.md sec-5 sketch, sec-13, sec-3 (F-5): landed signatures (`wakeSchedule(deps, task)`, `tasksExtension(deps, task?)`, `sweepBlockedWakes(deps, read, ctx)`, `SessionOptions.setTimer`, `StartDeps.now?/environment?`). `wake_schedule` reads the topic index, not `deps.conversations`, and refuses a known topic with no conversation. `wake_cancel` refuses terminal wakes and answers `cancelled` only on `{fired:false}`. A sweep or ensure failure fails daemon start after closing the session.

### Governance/spec (REV)
- SPEC-002 (F-9): REV modify. The interactive daemon (room profile) Owns gains wake scheduling (satan.wake, heartbeat, start sweep, `MALEBOLGE_WAKES`); the satan-mcp transport names the `scheduled` kind (DEC-121/125).

### Not reconcile's
- F-7: no action (tooling limit). F-8: user ruling pending, reported in the audit summary. F-10: RSK-022. At /close: IDE-014 / IDE-017 absorbed; candidate memories from notes § Harvest › Learned.

## Reconciliation Outcome

User agreed to all proposed edits (2026-10-28: "yes apply them").

### Direct edits applied (design.md; run locked, edited directly, not adopted)
- sec-2 Fire composition: `late_by` on occurrence 0 only; `fired_at` local time (F-1, F-4).
- sec-2 Failure: step 1 carries `n=<n>` (none for the sweep's blocked wake); a withdrawn heartbeat notifies `SATAN wake unanswered` (F-3).
- sec-3 Heartbeat: a sweep or ensure failure fails daemon start, session closed first (F-5).
- sec-4 journal table: abort handler `cancelled: already fired` and `withdraw failed`; tool cancel also yields the terminal line; sweep `withdrew <k>` semantics and the blocked one-shot's failure line; all times local ISO-8601 with offset (`localIso`) (F-3, F-4, F-6).
- sec-5: sketch shows `wakeBinding`, `tasksExtension(deps, task)`, `wakeSchedule(deps, task)`; `sweepBlockedWakes(deps, read, ctx)`, `DaemonParts.tasks`, `StartDeps.now?/environment?`; Clock bullet adds `SessionOptions.setTimer`; Config: `MALEBOLGE_WAKE_TOPIC` a topic name, not `default` (F-2, F-5).
- sec-13 Tools: `wake_schedule` reads the topic index (`isKnownTopic`), refuses a known topic with no conversation; `wake_cancel` refuses terminal wakes and answers `cancelled` only on exactly `{fired:false}`; `wake_list` `at` is the next fire (F-4, F-5).

### REVs completed
- REV-015 (`reconcile-sl-034`): done — SPEC-002 Interactive daemon Owns gains wake scheduling; MCP row names the `scheduled` kind (F-9). `doctrine spec validate SPEC-002` clean.

### Tolerated / follow-up
- F-7: tolerated (cross-repo tooling limit). F-8: tolerated; the user's ruling on the forms-suite deletion is still pending (reopen F-8 to rewrite). F-10: RSK-022.

Reconcile pass complete — handoff to /close.
