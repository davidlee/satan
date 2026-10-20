Open at the SL-029 plan round; owned by `/reconcile`, not by the phases. DEC-103
already carries the three wire-contract additions the plan implements (tools-not-allowed,
request-invalid, cancellation/Eof). These four corrections remain, each a place where
the plan's reading and the locked design's text (revision 80) differ, recorded in
plan.md § "Wire contract additions" so an auditor reads them as accounted-for:

1. **`final` is derived in the server, not the reducer.** Design §7 lists `final` among
   the reducer's new fields; §5's success predicate needs `agent_settled` + exit 0 +
   known accounting, and the reducer never sees the exit status. The plan derives it
   once, in PHASE-08.
2. **§5's reconciliation sentence still names `backstop`** among stream-external causes
   while the enum and the timeout rows say `timeout` — residue of RV-046 F-6's repair.
3. **§5 says `session` is "always present"; a refusal mints none.** The plan's refused
   result carries `session: null`.
4. **The reducer's status schema id advances** (`pi-run-status/1` → `/2`) because
   PHASE-01 adds requests, requests_unmeasured, cache_write and the accounting signal;
   the status-line consumers (`cli.ts`'s `statusLine`, `scripts/lib/pi-report.sh`) are
   re-checked.

Resolution: one REV at reconcile folding 1–4 into design.md (and 5c/REQ-004 where
DEC-097's limits are restated), or an explicit decision that any of them stays as-is
with the plan's reading recorded instead.
