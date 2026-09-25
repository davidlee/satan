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
