# satan-attrd devshell toolchain

# satan-attrd cargo tooling via flake devshell

## Summary

The repo `~/dev/satan-attrd` (separate from `~/.emacs.d`) builds via a Nix flake
devshell. The **system `cargo`** (`/run/current-system/sw/bin/cargo`) has **no
`fmt` / `clippy`** components — `cargo fmt` fails with `no such command: fmt`.
Run all cargo tooling through the devshell.

## Context

- `.envrc` is `use flake`; it provides `cargo`/`rustfmt`/`clippy` from the
  devshell **and** exports `DATABASE_URL=postgres:///satan_memory?host=/run/postgresql`
  (the **prod** socket — deliberate; the test harness self-provisions a throwaway
  DB and never writes prod, see [[mem.fact.satan-attrd.sqlx-socket-host]]).
- Run commands with the env applied:

  ```sh
  cd ~/dev/satan-attrd
  direnv allow .          # once
  direnv exec . bash -c 'cargo fmt --all --check'
  direnv exec . bash -c 'cargo clippy --all-targets --all-features -- \
    -D clippy::unwrap_used -D clippy::expect_used -W clippy::pedantic -A clippy::too_many_lines'
  direnv exec . bash -c "cargo test --test '*'"
  ```

- `just check` (= `lint format test`) also works but its recipe **overrides
  `DATABASE_URL`** to the supabase-local tcp URL (`…54322/postgres`); to prove the
  prod-leak guard, run the suite under the `.envrc` prod-socket env instead.
- clippy uses `-W clippy::pedantic` (warn, not deny): pre-existing pedantic
  `cast_possible_wrap` warnings exist and do **not** fail the gate; only
  `-D unwrap_used`/`-D expect_used` are denials.
- Verified 2026-05-30 during DE-002 P02 (see [[DE-002]]).
