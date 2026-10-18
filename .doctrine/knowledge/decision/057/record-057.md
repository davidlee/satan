# DEC-057: SL-023 runner owns per-job ceilings with a pre-abort warning, and its own append-only job audit

<!-- Knowledge record body — context, detail, links. The structured, queried
     fields live in the sister `record-NNN.toml`; this prose is free-form and is
     never structurally parsed (the storage rule). -->

Revised 2026-10-18 before design lock, after an informal critical review (gpt-6-sol; no RV ledger) — finding 1: beforeRequest sees spend already incurred, and long calls never reach a hook; strictness now comes from per-request output caps plus an independent deadline. User accepted the triage.


Revised 2026-10-18 at design review (RV-025 F-1, F-6, F-8; Codex gpt-6-sol), adjudicated against pi-durable 1.3.0: no hook can deny a request or set its options (beforeRequest returns messages only; a throwing hook is skipped), and pi.usage has no request count. Denial, a durable attempt counter and the output cap therefore sit in a model gate, a Models view wrapping the provider stream, demonstrated before ceilings build on it; on failure the user's ruling applies (amend to the weaker guarantee). The guarantee is defined as: spend exceeds a ceiling by at most one request, output capped, input that of its prompt. The deferred warning mechanism is settled: an idempotent queued submission (requestId warn-<job id>) whose job_events row is the receipt of its admission.


Revised 2026-10-18 at RV-025 verification (F-8, F-15): the warning is a steer, admission and delivery are distinct, and the gate wraps completeSimple (compaction) as well as streamSimple.

Revised 2026-10-18 at RV-025 third pass (F-8): warning placement is read from its submission record (Harness.submission(id).status(), id stored in the warning receipt), not the active transcript; a job resuming past the threshold with no placed warning on record, including a crash before the receipt, gets the warning in its resume message.



Revised 2026-10-18 at SL-023 PHASE-01 (user ruling, "DEC-057 - yes"): EVD-006 proved the gate on streamSimple/completeSimple; the spike found two paths outside it — deferred polling/cancellation (fetchDeferred, cancelDeferred) and a tool's runtime.models ungated entry points (complete, stream, classify, generateImages, streamDeferred; reachable from codemode). Both are gated and counted. The refusal must avoid pi-ai's retryable wording so the retry policy does not re-ask a refusing gate.



Revised 2026-10-19 (user: 'i'll take the recommendations'): cancelDeferred always passes uncounted, even when exhausted — refusing it leaves an admitted request billing; the gated view refuses getAuth/login/logout, conditional on pi-durable never calling them through the job's view (else escalate).