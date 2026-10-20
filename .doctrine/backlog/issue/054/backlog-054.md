# ISS-054: pi-mcp: a switch or timeout crossing during a cancellation's grace period is recorded nowhere

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

From RV-053 F-16 (the original detail of item 5); not covered by the text
settled at SL-029 reconcile.

`gate.fire` passes only the cause to `config.abort` (`pi/mcp/gate.ts`). On an
already-aborted signal, `AbortController.abort()` emits no second event, and
`terminate` in `pi/mcp/spawn.ts` returns early once `abort` is set. So a
`switch` or `timeout` crossing during a cancellation's grace period is recorded
nowhere. The audit says `cancelled` while the operator's kill switch also fired.

There is no state impact (`switch` → `cancelled`), but it breaks design sec-5's
rule that a later cause is never hidden behind an earlier one, and the audit
loses fidelity.

Fix (cheap either way): append an `abort` record per trigger, or add the extra
cause to the latch so `causes` carries it. Test: cancel a run, flip `enabled`
inside the 2 s grace period, and assert both causes are in the audit (and in
`causes`, if that route is chosen).
