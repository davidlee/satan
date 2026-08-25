# ISS-009: production-socket batch guard is defeated by a trailing slash

Found discharging SL-015 PHASE-01 EN-1 (2026-08-26).

`satan-db-resolve-host` (`satan/satan-db.el:62`) refuses the production socket
in batch by string equality:

    (when (and noninteractive
               (equal h "/run/postgresql")
               (not (getenv "SATAN_FAILOVER_TO_SYSTEM_DB")))
      (error ...))

`SATAN_DB_HOST=/run/postgresql/` is not `equal` to `/run/postgresql`, so the
guard passes — while libpq resolves the identical socket directory. The
pre-flight in `dev/satan-test.el:74` has the same hole from the other side: it
only checks that `SATAN_DB_HOST` is *set*, never what it points at.

Severity is bounded today because every DB-touching suite targets a `*_test`
database by defconst, and the one suite that defaults to production
(`satan-memory-grammar-test.el:23`, a drift detector) issues SELECTs only. But
the guard exists precisely so that bound does not have to hold, and a future
write-side test would land on production data with no warning.

Note: SL-015 PHASE-01 deliberately *uses* this hole as its documented suite
invocation (design §9.2) because it is the only route on this machine that
reaches a live Postgres while leaving the guard's own tests intact. Fixing this
issue will invalidate that invocation — the two must be reconciled together, and
the replacement should be a first-class opt-in rather than a second loophole.

Fix sketch: compare canonicalised paths (`file-name-as-directory` /
`file-truename`) rather than the literal, in both `satan-db-resolve-host` and
`satan-test-run-batch`'s pre-flight.

Related: SL-015 design §9.2, ISS-008.
