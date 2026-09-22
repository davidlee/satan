# ISS-016: Pre-spawn sensor alerts notify but never record: ctx contract drift leaves cooldown unarmed

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Every pre-spawn sensor alert reaches the user as a desktop notification and is
then recorded as **suppressed**. Observed 2026-09-23 in
`runs/2026-09-23/20260923T074731-motd-3a9448.FAILED/actions.json`:

    {"kind":"sensor_alert","cause":"panopticon_current_stale",
     "suppressed":true,
     "reason":"dispatch_failed: satan-intervention: tool-ctx missing
               :id/:mode-name/:time-now/:audit"}

— while the user simultaneously saw the notification on screen.

## Mechanism

`satan-tool/notify-send` (satan/satan-tools-notify.el) does its two effects in
this order:

    :56   (notifications-notify …)        ← fires; the user sees it
    :65   (satan-intervention-create …)   ← signals user-error; nothing recorded

so the side effect lands and the record does not.

## Root cause: a drifted contract

`satan-tool/notify-send`'s own docstring (:35) documents CTX as carrying
`:id`, `:mode-name`, `:time-now` — precisely the three keys
`satan-sensor-alerts--make-tool-ctx` (satan/satan-sensor-alerts.el:297)
supplies. But `satan-intervention--ctx-required`
(satan/satan-intervention.el:332) enforces a **fourth**, `:audit`.

The synthetic ctx was built correctly against the documented contract. The
enforced contract gained a key and the documentation did not follow. Fixing the
synthetic ctx alone would paper over that; the contract needs one authority.

## Consequences

1. **The cooldown never arms.** `satan-sensor-alerts-check` stamps
   `:dispatched_at` only on dispatch success; a failure records
   `reason: dispatch_failed` instead. With no timestamp, the per-cause cooldown
   window never starts, so the same alert can re-fire on every subsequent run.
2. **The observer is blind to it.** No `satan_interventions` row means the
   outcome of an alert can never be classified — the A13/A16 audit
   cross-checks ([[IMP-001]], [[IMP-002]]) have nothing to match against.
3. **The one-to-one invariant is nominal only.** The code comments claim the
   entry↔dispatch invariant holds independent of dispatch outcome; it holds in
   the pre_spawn ledger but not in the intervention store.

## Decision needed

Either the synthetic pre-spawn ctx gains a real `:audit` sink (a pre-spawn run
already has a run-dir, so this is plausible), or `satan-intervention` relaxes
its requirement for pre-spawn callers. These differ in what the audit trail
ends up containing — not a free choice.

Related: [[ISS-012]] (auth failures went unsurfaced for ~3 weeks) — the same
theme: SATAN's ability to report on SATAN. Candidate for a shared slice.
