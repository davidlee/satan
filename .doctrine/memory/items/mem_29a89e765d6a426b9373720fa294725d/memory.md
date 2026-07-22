# satan-attrd sqlx socket host trap

# sqlx ignores libpq socket host param

## Summary

`sqlx::postgres::PgConnectOptions::from_str("postgres:///db?host=/run/postgresql")`
**does not** carry the libpq `?host=` socket path. `get_host()` returns sqlx's
compiled default (`/var/run/postgresql`) or `$PGHOST` — not the URL's value.
(sqlx 0.8; verified by live connect probe in DE-002 P01, 2026-05-30.)

## Context

- It still connects correctly **on Sleipnir only** because `/var/run` is a
  symlink to `/run`, so the defaulted `/var/run/postgresql` is the same socket
  dir as the URL's `/run/postgresql`. Verified: a connect via `with_db(prod_url,
  "postgres")` reached `SELECT current_database()` → `postgres`.
- **Portability / CI:** a host without that symlink (or a different socket dir)
  will connect to the wrong place silently. There, set `$PGHOST` or use a tcp
  `DATABASE_URL` (`postgresql://user:pass@host:5432/db`), which sqlx parses
  faithfully (host/port/creds preserved).
- Consequence in the satan-attrd test harness (`~/dev/satan-attrd`, separate
  repo): `with_db()` in `tests/common/mod.rs` returns `PgConnectOptions` and the
  VT-with-db socket test asserts only the **database swap**, not a literal host.
  Real socket reachability is proven by VT-no-prod (`shared_pool()` +
  `current_database()` guard), not by the unit test. See `[[DE-002]]` / DR-002.

## How to apply

- Don't assert `get_host()` equals a socket path parsed from a URL — it won't.
- For a guaranteed connection target in tests, prove it at runtime with
  `SELECT current_database()`, not by inspecting parsed options.
