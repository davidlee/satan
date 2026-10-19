git 2.55 `fetch` starts auto-maintenance **detached**. In a test that fetches
into a temporary bare repo and removes it in teardown (`rmSync`,
`onTestFinished`), maintenance may still be writing, giving `ENOTEMPTY` — a
flake of roughly 1 in 15 runs in malebolge's runner tests (SL-023 PHASE-15 A).

Fix: run test git with `maintenance.auto=false` (malebolge
`test/runner/git-fixture.ts` `ISOLATED_ENV`, e.g. `GIT_CONFIG_COUNT`/`-c`).
0 failures in 40 runs after. Applies to any fake channel that fetches per
probe (PHASE-16 runs its fake `gitStep` under the same env).
