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
