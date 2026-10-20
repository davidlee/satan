# Review RV-048 — design of SL-029

Adversarial-review ledger. Structured findings live in the sister
ledger toml; this prose companion carries the reviewer's framing.

## Brief

Raiser continuation against materialised SL-029 revision 62 and the latest responses on RV-043/RV-046. Read all seven sections, the synthesized scope, amended DEC-097/099 and IDE-015. This is the managed run's current pass; existing charges remain on their original ledgers, rather than being duplicated here.

Lines of attack: compare the amended request-accounting map to actual pi 0.99.1 events; check cross-process lock admission and recovery separately; confirm unsupported-posture refusal, switch-source failure, startup profile freezing and canonical outcome vocabulary are now explicit; distinguish accepted accounting concessions from ungranted ones and future instrument evidence from completed verification.

Operator acceptance of unmeasured failure usage and nested-spend scope is now recorded in DEC-097 and the scope; those choices were respected, not re-opened. The source/evidence critique concerns counting claims that remain stronger than the mechanism, not the accepted spend-attribution limits.

Read-only probes: extracted AgentSession._checkCompaction emitted an overflow-recovery compaction_end diagnostic for zero new provider sends, so the new unconditional compaction_end counter is not exact. An isolated temporary-file interleaving showed two dead-lock reclaimers both succeeding with O_EXCL after the second deleted the first's live replacement. These counterexamples were recorded as contests on RV-043 F-6 and RV-046 F-3; no new sibling findings were minted.

The other amended mechanisms have concrete design repairs, but their demonstrate-routed findings remain answered until the obligations are transcribed into phase criteria. No implementation, model/gateway calls, design edits, responder acts or user acceptance were performed. Priming updates the selector cache, not the separate managed-run STALE binding. Concluding this examination does not clear the inherited findings or certify the design ready to ship.
