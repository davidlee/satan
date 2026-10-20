# Review RV-046 — design of SL-029

Adversarial-review ledger. Structured findings live in the sister
ledger toml; this prose companion carries the reviewer's framing.

## Brief

Raiser continuation first against SL-029 revision 48 (the amended revision-46 sections plus the static-build deferral), then reassessed against revision 56. RV-046 is the current managed pass; answered findings are on RV-043. Verification/contests belong on RV-043 and new findings here. RV-044 was inspected and contains no findings. Re-priming refreshed the code-selector cache; it is not an assertion that the managed design run's STALE binding has been refreshed.

Lines of attack:
- Check each RV-043 response against the materialised design and the amended DEC-093/094/096/097/099/100, without treating a promised implementation probe as completed evidence.
- Respect the operator's accepted retrospective-accounting concession and static-build deferral; test whether the remaining build contract actually expresses those decisions fail-closed.
- Examine indirect root/home/session binds, policy-read failure during an active run, per-client server/session concurrency, result finality and post-settlement failure precedence.
- Check current pi 0.99.1 JSON events and reducer semantics for the actual observability of provider requests, retries and compaction usage.

This is a design-only pass: no implementation, model calls, design edits, responder dispositions or user-acceptance acts. Instrument-routed findings remain unverified until their obligations are transcribed into phase criteria, as required by the review-ledger protocol.

## Revision-56 reassessment basis

Re-read the materialised seven sections, the synthesized SL-029 scope, amended DEC-092/093/095/097/098 and the latest RV-043 responses. The original four RV-046 findings still require responder dispositions: static-policy refusal, failed switch-policy reads and cross-process session locking remain unspecified; the nested-spend limitation is now disclosed but has not received the requested explicit disposition/acceptance.

For the accounting dispute, inspected the installed pi 0.99.1 executable's embedded AgentSession event forwarding/retry functions and pi-ai retryAssistantCall, then exercised the extracted control flow with stubbed sends, persistence and delays. Both assistant retry and compaction retry produced overlapping events that the revision-56 table counts as three requests for two sends. No provider/network calls occurred. The reusable fact and source locations are recorded as mem.fact.pi.retry-events-overlap-completions; RV-043 F-6 carries the specific contest.

The phase-routed evidence-isolation, argv and termination-domain obligations were reviewed as planning obligations, not falsely certified as implementation evidence. The new live-profile authority exclusion and the narrower timeout/backstop vocabulary discrepancy are recorded as findings on this pass.
