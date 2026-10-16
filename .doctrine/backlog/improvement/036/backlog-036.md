# IMP-036: Make satan a capsule target: tests green inside the oubliette microvm

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Raised 2026-10-16.

## Done already

`flake.nix` exports `packages.<system>.dev-tools`: a `buildEnv` over
`devToolPkgs`, the devshell tool set minus the jailed agents (doctrine's shape;
oubliette's `toolsPackage`). `projectPkgs = devToolPkgs ++ jailed codex/claude`.
`python3` and `ripgrep` were added: the devshell had been borrowing them from
the host (`just test`'s harness unittest; `content_read` search).

## Remaining — oubliette `targets/satan.nix` and what it implies

```
guest /work/satan
  dev-tools (this flake)  +  agents (capsule fragment)
  just test ──▶ PG on 127.0.0.1:54322 ?   (host: supabase in podman — unreachable)
            ──▶ ~/satan-corpus ?          (absent → corpus tests skip-unless)
            ──▶ satan-attrd / goad-emit / jailed-pi  (mocked in tests)
```

- **Test DB.** `just test` refuses unless the three test DBs answer
  (`_require-test-dbs`). Options: run `postgresql_18` in the guest (a seed or
  `baseline` step: initdb on the volume, listen on 54322, create
  `satan_memory_test trace_test patch_live_test`), or `SATAN_TEST_ALLOW_NO_DB=1`
  and accept skipped DB suites. The former keeps the capsule's green meaningful.
- **Target fields.** `baseline = "just check"`; `refresh` = `doctrine install …`
  as doctrine's target (satan is a doctrine repo); `statePaths` as doctrine's
  (`.doctrine/state/slice/{unit}`, `.doctrine/slice/{unit}`); sizes small (no
  cargo) — Emacs + PG, start at 2 vCPU / 4 GiB / 8 GiB volume and measure.
- **`extraTools`.** `git` is guest base. Re-check after a first baseline run for
  any further host-borrowed tool (luau tests, `bin/elisp-locate-paren-error`'s
  interpreter).
- Wrapped Emacs comes from `flakes/emacs`, so flakes IMP-025 (load-prefer-newer
  via site-start) reaches the guest with the next lock bump.
