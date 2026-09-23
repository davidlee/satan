# Review RV-014 — reconciliation of SL-018

Adversarial-review ledger (ADR-007). Structured findings live in the sister
ledger toml; this prose companion carries the reviewer's framing.

## Brief

<!-- Pre-reading + lines of attack: what this review is probing, the invariants
     it must hold the subject to, and where the bodies are likely buried. Seeded
     at `review new`; the reviewer fills it before raising findings. -->

**Mode:** conformance (self-audit; raiser and responder driven with `--as`).
**Surface:** main tree at 2cdae19, i.e. the SL-018 code delta e3faba6^..7d8b90d plus
PHASE-08 evidence (73fbb9b). SL-018 was not dispatched, so there is no
candidate branch.

**Lines of attack**

1. Code against design sec-2..sec-8: the seam's error boundary (no backend
   signal escapes), acquire-before-allocate ordering, `run_busy` precedence,
   policy/escalation arithmetic, eviction trigger, sentinel reset, patch
   peek → ready → claim → resolve.
2. Fail closed (REQ-010, ADR-017 §4): no `op://` ref reaches a child on any
   path; the no-backend path defers or records unavailability.
3. Conformance algebra (`doctrine slice conformance 18`): undeclared and
   undelivered paths.
4. Live evidence (PHASE-08) against the design's stated consequences, in
   particular DEC-020's "a prompting mode waits for the keeper".
5. Closure preconditions: RV-013 terminal, REQ-010 coverage, and the truth of
   the backlog items /close will resolve (ISS-012, ISS-020, IMP-021).

**Evidence gathered**

- `just check`: 1145 tests, 1139 as expected, 0 unexpected, 6 skipped.
- `doctrine slice verify-vt 18`: every VT PASS; VT-25/VT-26 waived
  (out-of-repo, `~/.emacs.d` suite 8/8).
- `doctrine slice conformance 18`: 11 conformant, 5 undeclared, 1 undelivered.
- `doctrine check gate`: unavailable (no `gate` recipe in this project's
  justfile); `just check` is the project gate.

## Synthesis

**Closure story.** SL-018 delivers what its design locked. The credential seam
(`satan-credential.el`) owns reference recognition, acquisition, scrubbing and
eviction, and no backend signal escapes it. The broker acquires before it
allocates the run, so a late-accepted prompt gets a fresh run id. The gate
precedence is perceive_failed > session_blocked > run_busy > budget_denied >
credential verdicts, as sec-3 specifies. An `auth` failure evicts exactly the
refs the run used. The sentinel always clears `spawn-running` (ISS-020). The
patch runner peeks, checks readiness, claims, then resolves leniently. No
`my/*` symbol remains in the broker or the pi adapter. Every VT passes, the
suite is green (1139/1145, 6 known skips), and PHASE-08 passed VH-2 and VH-3
live.

The code has no defect. The findings are about recorded truth:

- **F-1 (major):** DEC-020 assumed a prompting run waits for the keeper. In
  fact 1Password's dialog expires in about 1–2 minutes and `op` reports that
  as a dismissal. The keeper accepts the outcome: an unattended motd/morning
  now fails loudly and with a label instead of silently. The residual (the
  day's run is lost) is ISS-023. ISS-012 closes as fixed.
- **F-2 (major, fixed in audit):** RV-013 had been left active with two
  answered blockers. It is verified and done, so the close-gate is clear.
- **F-3 (minor):** escalation, and its "full threshold later after a
  dismissal" guarantee, is per mode. The keeper tolerates the rare double
  prompt, and the design prose must say "per mode".
- **F-4/F-5/F-6/F-7:** selector registry and coverage bookkeeping.

**Standing risks.**

- ASM-002 (a read inside a live session never prompts) is held, not
  validated. VH-1 is a watch armed on ASM-002, and closure does not wait on it.
- RV-013 F-9 (DST skews the escalation age by up to 1 h) and F-12 (patch
  readiness spans all seven Pi key vars) remain tolerated.
- DEC-023: a daily mode whose trigger queued behind another run's prompt loses
  its day to `run_busy`.
- ISS-022 (found in PHASE-08, outside the slice): the tick timer fires only
  once, at boot. Until it recurs, the defer → escalate path has no unattended
  driver in production.

**Tradeoffs consciously accepted.** Loud failure over waiting for
prompt-policy modes (F-1, ISS-023). Per-mode escalation (F-3). A rejected
PHASE-05 review point (F1: a ref, which is a vault path and not a secret,
appears in the rendered error), kept as the locked design's choice.

## Reconciliation Brief

### Per-slice (direct edit)

- **RV-014 F-1: design.md sec-3, "Consequences".** Qualify "A prompt accepted
  at 11:40 yields an 11:40 run id … No expiry exists". SATAN imposes no
  expiry, but 1Password's dialog expires in about 1–2 min and `op` reports
  that as a dismissal, so an unattended prompt-mode run records
  `credential_unavailable` (see ISS-023).
- **RV-014 F-1: design.md sec-9, VH-3.** "Accepting later" is bounded by the
  dialog's lifetime. Record the PHASE-08 observation.
- **RV-014 F-3: design.md sec-4, "Escalation due".** State that the streak,
  and "the next escalation is a full threshold later", hold per mode. Each
  defer mode (tick-pulse, tick-agent) escalates independently, so a dismissal
  quiets only the mode that prompted. Tolerated by the keeper, 2026-09-23.
- **RV-014 F-4: selector registry (load-bearing).**
  `doctrine slice selector add` re-intents `satan/satan-tick.el` from
  `design-target` to `scope-relevant`. It was read and tested (VT-17) but
  needed no edit. There is no prose mirror in design.md.
- **RV-014 F-5: selector registry (load-bearing).**
  `doctrine slice selector add` adds `design-target` selectors for
  `dev/satan-test.el`, `satan/test/satan-credential-fixture.el` and
  `satan/test/satan-mode-test.el`.

### Governance/spec (REV)

- **RV-014 F-1: DEC-020** (knowledge record). The context says a prompt-mode
  read "already waits for the keeper", and the choice/rationale says "no
  expiry exists". Append a dated note: the wait is bounded by 1Password's
  ~1–2 min dialog expiry, and an unattended prompt-mode run fails as
  `credential_unavailable`. Link ISS-023. Edit the record through its own
  surface (`/knowledge`), append-only, as DEC-022's RV-013 F-8 note was.
- **RV-014 F-7: REQ-010 coverage.** Record SL-018's observation
  (`doctrine coverage record`, a VT recipe citing VT-11 and VT-12). The
  authored status stays `pending`.

### For /close (not reconcile writes)

- Resolve ISS-020 (fixed, 1a201a6), ISS-012 (fixed; residual ISS-023) and
  IMP-021 (done).
