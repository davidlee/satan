# ISS-037: SATAN harness has no single source of authority; satan-repo buffers run the devshell build with dev mounts leaked in

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Problem

No single authority decides which harness binary a SATAN run executes, or
which host paths its jail mounts. Today the answer is "whatever the calling
buffer's environment says":

```
calling buffer's process-environment
  └─ satan-broker--direnv-env: direnv export of satan-direnv-dir (~/dev/satan)
     merged over it  ──> PATH  ──> executable-find "jailed-satan-gptel-harness"

  buffer outside ~/dev/satan ──> ~/.nix-profile/bin/…   (pinned github input;
                                                          intended mounts)
  buffer inside  ~/dev/satan ──> devshell-dir/bin/…     (working tree, impure
                                                          eval; dev mounts)
```

Verified 2026-10-14 by resolving the way the broker does from `satan/flake.nix`
(→ `/nix/store/i4dayx…-devshell-dir/…`) and from `dl-org.el`
(→ `~/.nix-profile/…`). Timers fire in whatever buffer is current, so a
scheduled tick can take the dev path too.

### 1. Mount leak (trust boundary)

`satan-jailed-gptel-harness` declares `workspaceDeps = []` (`flake.nix:289`),
but `~/flakes/agents/jailed-agents.nix:378` unconditionally merges
`builtins.getEnv "JAIL_WORKSPACE_DEPS"` at (impure) eval time. The dev
`.envrc` sets that var for dev jails, so the devshell-built prod harness gets
rw binds of `~/notes`, `~/flakes`, `~/dev/panopticon`, `~/.config/emacs`.
That contradicts the `~/flakes/SATAN.md` jail table and ADR-017's
trust-boundary invariants.

### 2. Not theoretical: it already broke runs

2026-10-14: tick-agent `20261014T135311-tick-agent-7b87b5` died at spawn,
`bwrap: Can't find source path /home/david/.emacs.d` — a stale dev `.envrc`
entry, baked into the devshell harness, killing a prod run.

### 3. Why it has persisted

Authority is smeared across five places, none of which owns the answer:
the mode's `:harness :cmd` (a bare name), `PATH` (buffer-dependent),
`satan-direnv-dir` (the dev `.envrc`), the flake's `workspaceDeps`, and the
impure `JAIL_WORKSPACE_DEPS`. The mode's `:jail-profile` is recorded in the
manifest but enforced nowhere. Nobody can answer "what does this run mount?"
without reproducing the resolution.

## Mitigation sketch (cheapest first)

| | Change | Closes |
|---|---|---|
| A | `jailed-agents.nix`: an opt-out flag (e.g. `envWorkspaceDeps ? true`); SATAN harness jails set it `false`. Default preserves every other jail | 1 |
| C | Broker builds the child env from `(default-toplevel-value 'process-environment)`, not the calling buffer's | buffer dependence |
| B | Harness runs by **absolute path** from a defcustom pointing at the pinned profile install; drop `satan-direnv-dir` / PATH lookup for the harness | single authority; dev shell can no longer alter prod |
| D | Map `:jail-profile` → harness binary as the one source, so the mode spec states its sandbox | dead `:jail-profile` |

B is the target (aligns ADR-018: lifecycle authority outside the editor).
A has independent value as defence in depth. Sequencing TBD.

Related: `mem.fact.satan.runtime-jail-deploys-from-github-input` (now
caveated with the buffer-dependent path).

## Agreed design (2026-10-14, user: "yes")

Small-work path: agreed sketch + work off this card (no slice). Scope: B + C.

Findings that shaped it:
- Provider key refs (`*_API_KEY`) are already in Emacs's global env; the
  harness reads only broker-set `SATAN_*` + forwarded keys. Direnv supplies
  nothing the harness needs except a `PATH` — the bug.
- The direnv merge's only load-bearing role is SL-018 RV-013 N5: credential
  lookup uses exactly the env the child receives. N5 needs *one* base env,
  not direnv.
- `satan.nix` already installs the harness via `home.packages` and states the
  intent: on the broker's exec-path "independent of any devshell/direnv".

```
before:  base = direnv-export(~/dev/satan) ⊕ calling buffer's env
         cmd  = executable-find over PATH taken from base
after:   base = (default-toplevel-value 'process-environment)
         cmd  = executable-find over (default-toplevel-value 'exec-path)
```

1. Delete `satan-broker--direnv-env`, `satan-direnv-dir`,
   `satan-broker--exec-path-from-env`. Base env + exec-path come from the
   global values, computed once in `--acquire` (N5 preserved).
2. `:harness :cmd` stays the knob. Global PATH → `~/.nix-profile/bin` (the
   pinned home-manager install) is the single source. Dev builds are opted
   into by an absolute `:cmd`.
3. Tests: VT-20 restated (key ref in base env acquired; child receives
   exactly that base); new VT — the calling buffer's buffer-local
   `process-environment` / `exec-path` do not reach the child; drop the
   `satan-direnv-dir` default test.
4. Docs/memory: `~/flakes/SATAN.md` jails, memory caveat, this card.

Cost accepted: working in `~/dev/satan` no longer silently runs the dev harness.

Then: sweep for collateral (other `envrc`/direnv consumers, patch adapter,
MCP, `satan-run` wrapper, systemd units), and plan a harness Spec as the
home for binary provenance, env contract, and mounts.

Deferred: A (`envWorkspaceDeps` opt-out in `~/flakes/agents`) — next time
that lib is touched; D (`:jail-profile` → binary) — when a second profile
exists.

## Implementation (2026-10-14)

- `satan-broker.el`: `--acquire` takes `(default-value 'process-environment)`
  as base; `--spawn` binds `exec-path` to `(default-value 'exec-path)`.
  `default-value`, not `default-toplevel-value`: it ignores the buffer-local
  binding but still honours a dynamic `let` (which binds the default when
  no local binding exists) — callers and tests can still inject env.
  Removed `satan-direnv-dir`, `--direnv-env`, `--exec-path-from-env`.
- Tests: VT-20 restated (`key-ref-from-global-env-is-acquired`); new
  `base-env-ignores-buffer-local-env`, `harness-resolves-on-global-exec-path`
  (red first, then green); dropped the `satan-direnv-dir` default test.
  `just check`: 1358 ran, 0 unexpected.
- Live check (reloaded broker, from `flake.nix` buffer whose PATH carries the
  devshell): base env has no devshell PATH; harness →
  `~/.nix-profile/bin/jailed-satan-gptel-harness`.
- Docs/memory: `docs/governance.md` (harness resolution section replaces
  "direnv-driven exec-path", which also wrongly claimed no `home.packages`
  install); runtime-jail memory; green-check memory clause.

## Collateral sweep

- Pinned harness = `6d9608c`; only harness delta to HEAD is the retired
  `agenda_read` tier entry. Installed binary's `runloop.py`/`__main__.py`
  match the pin. No regression from losing the working-tree harness.
- Harness needs nothing from direnv: jail forwards only broker-set
  `SATAN_*` + key vars; keys are in Emacs's global env.
- No other consumer of the removed symbols (elisp, `~/.config/emacs`,
  `~/flakes`). `satan-run` wrapper is a bare `emacsclient --eval` — fine.
- **Same class, not fixed — cwd bind.** The jail binds `$PWD` rw at
  `/workspace/<basename>` (`jailed-agents.nix:148`) and the broker never sets
  `default-directory`, so the calling buffer's directory becomes a writable
  mount (from a `~/notes` buffer: notes rw despite the `/satan/notes`
  ro-bind; from `~`: all of home). Already listed in `~/flakes/SATAN.md`
  known gaps. Fix candidate: bind `default-directory` to the run dir in
  `--spawn`.
- **Same class, not fixed — patch adapter.** `satan-patch-adapter-pi`
  resolves `jailed-pi` via the calling buffer's `exec-path`; `jailed-pi` is
  not on the global PATH, so it only resolves from devshell buffers.

## Cwd leak fixed (2026-10-14)

`--spawn` binds `default-directory` to the run dir, so the jail's `$PWD` bind
is `/workspace/<run-id>` (already the run's own dir, also at `/satan/run`)
instead of the calling buffer's directory. Harness reads no cwd-relative
paths. Test `harness-cwd-is-run-dir` (red → green); `just check` 1359 ran,
0 unexpected. Broker reloaded live. `~/flakes/SATAN.md` known-gap removed
and jail table row updated; `docs/governance.md` notes it.

Patch adapter leak split out → ISS-038. Deferred A/D remain as noted above.
