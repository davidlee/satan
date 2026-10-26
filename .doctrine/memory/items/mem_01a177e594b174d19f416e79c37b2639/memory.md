# pi workers run satan tests without the test DB host

Observed SL-032 PHASE-01/02 (2026-10-26). A quotient `pi_agent` worker runs
inside satan's machine form (`quotientFormFamily`, `flake.nix`), whose
environment does not carry `SATAN_DB_HOST`. In there:

- DB-gated suites `skip-unless` (memory-store, intervention, atsatan…), so a
  worker's "green" covers only the non-DB half of those files.
- Some tests fail outright with `satan-db: refusing production host
  "/run/postgresql" in batch` — seen: `satan-motive/capsule-*`,
  `satan-mcp/boot-context-caches-per-session`.
- Workers report these as "pre-existing" failures. They are not red on the
  host: `just check` there runs all of them.

So: never accept a worker's test claim for DB-backed behaviour; re-run
`just check` on the host (the orchestrator's gate anyway). A worker that sets
`SATAN_DB_HOST` by hand trips the `satan-db/resolve-host-guard-*` tests
instead.

Host side: the test DB is Supabase on `127.0.0.1:54322`
([[mem.fact.satan.test-db-on-rootless-docker]]).
