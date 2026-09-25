# `doctrine backlog new` cannot allocate an id in the SATAN dev shell

```
$ doctrine backlog new issue "…"
Caused by:
    git command failed: fetch origin +refs/doctrine/reservation/*:refs/doctrine/reservation/*:
    fatal: cannot exec '/nix/store/cllg0wr5svsxqvrykv4m1gsrb78lyw78-git-ssh-disabled':
    No such file or directory
    fatal: unable to fork
```

The reservation step fetches the reservation refs through a git wrapper whose
store path is absent from the closure. `doctrine backlog new --help` exposes no
opt-out, and the failure happens **before any write** — `.doctrine/backlog/`
stays clean, so it is safe to retry elsewhere, but a finding captured this way
is silently lost if you do not notice the non-zero exit.

Nothing else observed broken: `doctrine backlog list/show`, `slice`, `design`,
`review`, `memory` all work in the same shell.

**Do:** report the blockage and keep the finding in the governing slice's
`notes.md` until the item can be created where doctrine can reach its git
helper. **Do not:** hand-author a `backlog-NNN.toml` to route around it — id
allocation is the engine's.



## Root cause: a stale `GIT_SSH_COMMAND` in the devshell env

```
$ echo $GIT_SSH_COMMAND
/nix/store/cllg0wr5svsxqvrykv4m1gsrb78lyw78-git-ssh-disabled
```

That store path belongs to a previous devshell closure — the current closure
does not contain it, so **any** git operation through ssh in this shell dies at
`exec`, not at auth. Overriding it reaches github (`GIT_SSH_COMMAND='ssh -o
BatchMode=yes'` gets a transport), but the jail holds no ssh credentials, so the
reservation fetch then fails at auth:

```
fatal: Could not read from remote repository.
```

`doctrine backlog new` cannot be made to work from inside the jail by any
environment override: id allocation is a remote reservation (`refs/doctrine/
reservation/*`), and `doctrine reservation` exposes only `list` — there is no
local fallback. **Create backlog items from a shell with network and
credentials**, or the finding has to live somewhere else until then.

## Correction (same day): there IS an override

The section above concludes "cannot be made to work by any environment
override". That is **wrong** — falsified within the hour by the user:

```
DOCTRINE_RESERVATION_FALLBACK=1 doctrine backlog new issue "…"
doctrine: reservation reach degraded to local (remote origin unreachable: git
  command failed: fetch origin +refs/doctrine/reservation/*:…
  cannot exec '/nix/store/…-git-ssh-disabled': No such file or directory)
Created ISS-032: …/.doctrine/backlog/issue/032
```

The verb warns loudly, degrades the reservation to **local**, and creates the
item — ids allocated locally while offline. So a blocked reservation is a
*degraded* path, not a dead end; the operator names the override, the CLI does
the rest.

**Do:** report the blockage with this flag rather than declaring capture
impossible. **Don't:** conclude from a single failed invocation that an override
does not exist — ask, or read the verb's own output for the escape hatch.
