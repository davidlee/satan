# Unattended runs acquire credentials by per-mode policy: probe, then prompt or defer

## Context

SATAN's scheduled runs resolve their provider key lazily, inside Emacs, at
spawn time, with no policy for what happens when no 1Password session exists.
ISS-012's motd/morning failures (late Aug – 2026-09-23) came from exactly this.
They fired at 08:15/09:15, into the gap left by 1Password's own session expiry
(`authorized_session.rs:217`, observed 07:00:57), while tick runs happened to
fire while the keeper was present.

How resolution works today:

- **Broker spawn** (`satan/satan-broker.el:704–711`) resolves `key-var`
  through `satan-broker--read-env` → `my/op-read-env` *after* the run dir,
  percept and bundle exist, and wraps it in `(condition-case _ … (error nil))`.
  A failed resolve becomes a missing env var. `my/scrub-op-refs-env` then drops
  the literal `op://` ref, and the harness fails with `init failed: KEY not set`.
- **Patch adapter** (`satan/satan-patch-adapter-pi.el:232`,
  `satan-patch-adapter-pi--resolved-env`) does the same under
  `ignore-errors`. It is driven by an Emacs timer
  (`satan-patch-runner-start-timer`), so it is also unattended.
- Both reach `my/op-read` (`~/.emacs.d/lisp/dl-secret.el`), a synchronous
  `call-process` that blocks the Emacs server while a 1Password dialog is up
  ([[mem.fact.satan.op-read-blocks-emacs-server]]). The results go into
  `my/op--cache`, which is never invalidated
  ([[mem.fact.satan.op-cache-has-no-invalidation]]).
- SATAN reaches these through `declare-function` + `fboundp` on `my/*`
  symbols. The package owns no credential seam of its own.

### Settled before this slice (2026-09-23)

- **No service-account token.** The keeper rejected it. It also conflicts with
  the posture in `~/flakes/agents/jailed-agents.nix:9–26` (secrets off disk
  *and* off argv) and with SPEC-001 REQ-010 / ADR-017 §4 (fail closed), and it
  would delete a human-approval surface that ADR-017 §1 gives the client
  permanently.
- **The prompt belongs to the session, not the read.** `op signin` prompts, a
  read in a live session does not, and `op whoami` is a non-prompting probe
  (exit 1, ~0s, when signed out)
  ([[mem.fact.satan.op-prompts-on-session-not-read]]).
- **The read stays synchronous.** The dialog is now focused and pinned by the
  keeper's window-manager fix, so a block is a visible one-keystroke
  interruption. A timeout-and-kill read would *orphan* the dialog (killing `op`
  does not dismiss it), which is worse.
- **Policy is per mode.** When no session exists, an unattended run either
  **prompts** (reads anyway; the keeper accepts or dismisses) or **defers** (no
  `op` call; the run does not spawn). motd/morning are meant to be seen, so
  they prompt. Tick and the patch adapter defer. A deferring mode **escalates
  to prompting after N consecutive credential deferrals** (keeper,
  2026-09-23), so a vault left locked for days does not silently starve it.

## Scope & Objectives

1. **Credential gate in the pre-spawn cond.** Resolve the key in
   `satan-broker-run`'s gate `cond`, beside DEC-8 `session_blocked` and
   `budget_denied` (`satan/satan-broker.el:536–556`), instead of late inside
   `--spawn`. Order: cached → spawn; `op whoami` live → read → spawn; no session
   → apply the mode's policy. A deferral writes a no-child run with a distinct
   status/reason (e.g. `credential_deferred`), following the `session_blocked`
   precedent. **Acquisition precedes run allocation** (`satan-run-new-ctx`), so a
   late-accepted prompt gets a fresh run id, time and percept (DEC-020).
2. **Per-mode `:credential-policy prompt|defer`** on the mode spec, next to
   `:provider`, with an escalation threshold for `defer`.
3. **Escalation from defer to prompt** when a broker mode's current
   `credential_deferred` streak is older than its `:escalate-after` (DEC-022).
   The streak comes from SL-017's run-outcome walk (DEC-014); this slice
   consumes that contract and does not build its own counter.
4. **Patch adapter under the same policy.** `satan-patch-adapter-pi` resolves
   through the same gate/seam, not a parallel copy. The patch runner checks
   before claiming a job, defers only, and never escalates (DEC-020, DEC-022).
5. **Resolution failures are loud and typed.** Replace `(error nil)` /
   `ignore-errors` with an outcome the run records: `credential_deferred`
   (policy), `credential_unavailable` (a prompting read failed or was
   dismissed; DEC-022), or a failure whose class is `auth` (surfaced by SL-017).
6. **Rotation self-heals.** An `auth`-class run failure evicts that ref from
   the credential cache. The next run re-resolves instead of replaying the
   dead key. This retires the manual `my/op-forget` step.
7. **IMP-021 closes.** Unattended code never *starts* a session unasked, and
   prompting modes carry `my/op-read-context`. Any remaining dialog therefore
   arrives with a label and a cause. The announce that IMP-021 chose is already
   built.
8. **Overlap is refused, and the refusal cannot stick** (added in design, RV-013).
   A `run_busy` gate refuses a scheduled run while a child is live (DEC-023). The
   sentinel always clears `spawn-running`, even when finalize signals (ISS-020,
   absorbed).

## Non-Goals

- Service-account tokens or any at-rest credential (rejected).
- Timeout/kill-bounded reads (they orphan dialogs).
- satan-patcher (Rust) and its own resolve/retry loop.
- Jailed agents (`op run --env-file`) and `~/nushell/keys.nu`. These are
  interactive consumers outside the Emacs server.
- Alert/escalation *mechanics*: the emit seam, re-announce cadence and class
  transport belong to SL-017. This slice consumes them.
- A ledger row for credential custody (see OQ-4; the default is a QUE, not a
  row).

## Affected surface

- `satan/satan-broker.el`: `satan-broker-run` gate cond, `--spawn` key
  resolution, `satan-broker--read-env`
- `satan/satan-mode.el`: mode spec `:credential-policy` (+ defaults)
- `satan/satan-patch-adapter-pi.el`: `--resolved-env`
- A new SATAN credential module owning the backend seam (DEC-021)
- `satan/satan-patch-runner.el`: check before `claim-next`
- `satan/satan.el`: `satan-run` binds `satan-run-attended` when interactive
- `satan/test/**`
- Outside the repo: `~/.emacs.d/lisp/dl-secret.el` supplies the 1Password
  backend (`whoami` probe, per-ref forget, registration) — DEC-021

## Dependencies

- **Needs SL-017**: its run-outcome streak (objective 3 here) and `auth`
  class transport (objectives 5–6 here).

## Risks & assumptions

- **A1 (ASM-002):** a read inside a live session never prompts. Observed
  once, not proven ([[mem.fact.satan.op-prompts-on-session-not-read]]).
- **A2:** the whoami→read race (the session expires in between) costs one
  visible prompt. That is acceptable, including for defer-policy modes.
- **R1:** the gate moves key resolution *before* spawn, and perceive already
  runs unconditionally before the gates (ISSUE-001). Check that no prompt can
  now fire earlier than it did, e.g. during perceive.
- **R2:** a probe per run adds an `op` subprocess to every tick. It is cheap
  (~0s), but it is a new dependency on the `op` binary at a path that had
  none when the cache was warm.

## Open questions (for /design)

**All resolved 2026-09-23:** OQ-1 → DEC-020, OQ-2 → DEC-021, OQ-3/OQ-4/OQ-5
and the dismissed-prompt outcome → DEC-022 (QUE-001 extended). Original text
kept below for the record.

- **OQ-1: deferred-run disposition.** For a deferring tick, "skip, the next one
  is in 30 min" is probably enough. Does any deferring mode need catch-up
  (re-fire when a session appears) and an expiry? Who re-fires it: a systemd
  exit code + `Restart=`, an Emacs timer, or fire-on-warm?
- **OQ-2: seam ownership.** Does SATAN own a credential seam (e.g. a
  `satan-credential-function` defcustom that `dl-secret.el` supplies), or keep
  calling `my/op-*` through `fboundp`? This decides whether the probe and
  eviction live in the package or in `~/.emacs.d`, and so whether the slice is
  one repo or two. It also settles the coupling smell.
- **OQ-3: escalation threshold N.** A fixed N, or time-based ("deferred for
  > X hours")? Is it per mode or global? Does quiet hours
  (`satan-tick-quiet-p`) suppress escalation-to-prompt?
- **OQ-4: governance record.** Record the credential policy as a DEC. The gate
  is a pre-spawn lifecycle gate, and like DEC-8 it has no SPEC-001 REQ and no
  ledger row. Extend QUE-001 to cover pre-spawn gates, including this one,
  rather than open a new question or add a row.
- **OQ-5: attended calls.** An interactive `M-x satan-run` should always be
  allowed to prompt. Confirm the policy applies only to unattended entry, and
  settle how that is signalled (`called-interactively-p` exists in
  `satan-run`, but ticks, systemd and the patch timer all enter
  non-interactively). The default should be unattended (fail closed).

## Verification / closure intent

- With no session: a `defer` mode writes a `credential_deferred` no-child run
  and makes **no** `op` call except `whoami`. A `prompt` mode calls `op read`.
- A deferring mode prompts after N consecutive credential deferrals.
- With a live session and a cold cache, a run resolves without a dialog and
  spawns.
- An `auth`-class failure evicts the ref, and the next run re-resolves.
- The patch adapter follows the same policy through the same seam: one
  resolution path, found by `rg`.
- No `(error nil)` / `ignore-errors` around key resolution remains.
- IMP-021 and ISS-012 closed; DEC recorded; QUE-001 extended.

## Summary

Make "can this unattended run get a key?" an explicit, recorded, per-mode
decision taken before spawn: probe the session, then read, prompt or defer.
A locked vault then produces a labelled prompt or a visible deferral, never a
silent turn-0 failure or a replayed dead key.

## Follow-Ups

- Protocol-level home for pre-spawn lifecycle gates (QUE-001 → SPEC-001 REQ).
