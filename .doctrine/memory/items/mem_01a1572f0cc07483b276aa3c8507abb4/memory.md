A slice whose design-target selectors include governance or spec paths (e.g. `.doctrine/adr/017/authority-ledger.md`, `.doctrine/spec/tech/002/**`) delivers them at /reconcile, through a REV, not in any phase. `doctrine slice conformance <N>` folds only the per-phase delta registry, so those selectors still read **undelivered** after the reconcile commit lands.

Check them instead with `doctrine slice conformance <N> --against <C>^..<C>`, where C is the reconcile commit; it should list them as conformant. Do not `slice record-delta` the reconcile commit under a phase: that misattributes it.

Seen at SL-027 reconcile (commit 798b064; RV-039 F-7 tolerated the rest as cross-repo).