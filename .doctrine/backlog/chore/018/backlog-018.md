# CHR-018: Move jailed-malebolge out of ~/notes/flake.nix

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

`jailed-malebolge` is defined in `~/notes/flake.nix` (jailPkgs block, shared
`mkJail` helper) but nothing in it is notes-specific: it runs SATAN's session
daemon from `~/dev/malebolge` and binds `~/satan-corpus` plus SATAN runtime and
state dirs. Candidate homes: `~/dev/satan/flake.nix` (already has gateway
clients) or malebolge's own flake (needs `mkJail` as an input; overlaps
CHR-017).

Custody constraint (SL-023 PHASE-18, malebolge 8c93902): the daemon reads its
gateway key only from a file (`~/.config/llm-gateway/keys/malebolge`, override
`MALEBOLGE_GATEWAY_KEY_FILE`) and its catalog from
`~/.config/malebolge/gateway-models.json` (override `MALEBOLGE_GATEWAY_CATALOG`).
`gatewayClient` passes `LLM_GATEWAY_KEY` by env, which the daemon ignores — the
jail must bind both files read-only and set the two env vars.

The gateway switch itself is another agent's work (user ruling 2026-10-19,
outside SL-023); this chore is the relocation.

## Progress (2026-10-19)

Home chosen: `~/dev/satan/flake.nix` (`jailed-malebolge` in `jailPkgs`).
Changes across four repos:

- **satan** `flake.nix`: `jailed-malebolge` on `makeJailedAgent` with
  `gateway = null`, `apiKeys = []`, `useOpEnv = false` (the pinned agents
  input defaults `apiKeys` to *every* provider key when `gateway = null`).
  Binds key file + catalog read-only, sets `MALEBOLGE_GATEWAY_KEY_FILE` /
  `_CATALOG`. Keeps the old binds (malebolge ro, corpus ro, `goad/` rw,
  durable store rw, `/run/user/1000/satan` rw). New `goad` input (same rev
  as `~/notes`, 04147ca) so goad tools/kit stay in the closure for the
  planned `MALEBOLGE_SKILLS` work (malebolge `docs/handover-skills-extension.md`).
  Dropped vs the notes jail: `subagents` pi/claude, the emacs-config
  workspace dep (both incidental to notes' `mkJail`).
- **satan** check `malebolge-jail-profile` (in `just check-jails`). Probe
  strings joined the one I1-excluded binding, renamed `jailProbes`
  (`harness`, `malebolge`); shared `launcherCheck`/`probe` helpers.
  Negative controls red with their own messages, restored green.
  Found and fixed: the `op run` probe never matches the 1Password wrapper
  (it execs `"$op" run`); both checks now also probe `-api-keys.env`.
- **notes**: `jailed-malebolge` + `malebolgeDaemon` removed from
  `flake.nix`; `just hello-durable` runs `nix run ~/dev/satan#jailed-malebolge`
  from `~/notes` (launch dir unchanged).
- **flakes** `SATAN.md`, **malebolge** `docs/internals.md`: jail paragraphs
  updated.

Verified 2026-10-19: the user ran `just hello-durable` in `~/notes` and attached; it works.
