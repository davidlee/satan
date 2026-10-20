Bumping an agent CLI in this fleet is **not** one `nix flake update`. Three different
locks can be stale, only one gates a running session, and stopping early looks exactly
like "the fix didn't work" — including after a session restart, which re-execs the same
store path.

## Which hop actually gates the deployed agent

The host-deployed harness and its jail come from the top flake (`~/flakes`), and there
`agents` is **not** read from any lock at build time:

- `justfile`: `tree_override := "--override-input agents path:<flakedir>/agents …"`, and
  `home-switch` / `system-switch` pass `local_override` — so the in-tree
  `~/flakes/agents` (including its `flake.lock`) is what builds, with no push and no
  `nix flake update`.
- The top flake overrides every nested consumer: `satan.inputs.agents.follows = "agents"`,
  `satan-attrd.inputs.agents.follows = "agents"`, `doctrine.inputs.agents.follows = "agents"`.
  A consumer repo's own `agents` pin is therefore bypassed in host evaluations.
- `features/satan/harness.nix` takes the jail from
  `inputs.satan.packages.${system}.satan-jailed-gptel-harness` — satan's flake output,
  evaluated with that overridden `agents`.

Operative sequence:

1. `~/flakes/agents/flake.lock` — bump the `llm-agents` pin (`cd flakes/agents && nix flake
   update llm-agents`).
2. `just home-switch` (and `system-switch` for system-level packages). `tree_override`
   picks the in-tree agents up immediately.
3. Fresh session. The jail command and the binary are baked into store paths at build
   time, so step 2 is the only thing that can change what `jailed-pi` execs.

## What the other locks are for

`agents`/`llm-agents` is also pinned by satan, satan-attrd, panopticon, oubliette,
malebolge, notes, emacs, satan-corpus, and by the top flake itself. Those matter for each
repo's standalone `nix flake check` / `nix build` / devshell and CI — not for the
host-deployed jail, which overrides them via `follows`. When a lock-driven build is in
play (CI, darwin, no read-only recipe), note that `agents` resolves to the **pushed** rev
of `github:davidlee/nix-config?dir=flakes/agents`: an uncommitted sub-lock bump is
invisible there, and a bump run seconds before the push silently locks the previous HEAD.

## Deciding what state you are in

- Taken or not: `echo $PI_PACKAGE_DIR` / `ls -d /nix/store/*-pi-[0-9]*`. If the new
  version is absent from the store, nothing has reached any running agent — no amount of
  session restarting changes that.
- Which revs: dump `nodes.*.locked.rev` from each `flake.lock`, and compare with
  `curl -sS 'https://api.github.com/repos/davidlee/nix-config/commits?path=flakes/agents/flake.lock'`
  — commit timestamp vs a consumer lock's `lastModified` shows whether it was taken before
  or after the push.
- Read the **working tree**, not `git show HEAD:` — consumer locks get bumped uncommitted
  before the parent repo sees them, so committed and on-disk revs routinely differ.

## Blast radius of an `agents` bump

`agents`' own lock moves more than `llm-agents`: its `nixpkgs` pin, `flake-parts`,
`systems`, `treefmt-nix`. Where a consumer sets `agents.inputs.nixpkgs.follows` (satan
does) that pin is neutralised; `llm-agents` deliberately keeps its own nixpkgs so agent
binaries arrive prebuilt from `cache.numtide.com`. Expect a small net build but a real
agent version jump.

## Worked example

2026-10-20, pi: 0.99.1's compiled binary omitted `src/extensions/codemode/worker.js` from
its `$bunfs`, so every codemode script died with
`Cannot find module '/$bunfs/root/src/extensions/codemode/worker.js'`. Upstream fixed it
2026-10-01 (`llm-agents` `d47e048e`, "pi: embed the codemode worker"), yet the fleet stayed
broken because the pin was locked 2026-09-29 — a sequencing lag, not a missing patch. Do
not patch packaging for this class of bug before checking the pin date.

See also [[mem.fact.satan.deploy-provenance-split]] — the harness *code* comes from the
top flake's locked `satan` input, which `tree_override` deliberately does **not** override;
only the agent binaries ride the in-tree `agents`.
