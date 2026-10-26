# The test DB's container runtime

As of 2026-10-26 on Sleipnir: `just check` needs Supabase Postgres at
`127.0.0.1:54322` (`_require-test-dbs`). `just db-start` is `supabase start`,
which follows `DOCKER_HOST`. satan's `.envrc` exports
`DOCKER_HOST=unix:///run/user/1000/podman/podman.sock`, but podman is not
installed; the host runs rootless docker (`~/flakes/features/virt.nix`,
`virt.docker` vs `virt.podman` are exclusive; a `Sleipnir+podman` variant
exists in `hosts.nix`).

Working recipe:

```
systemctl --user start docker
DOCKER_HOST=unix:///run/user/1000/docker.sock supabase start
just db-setup
```

Gotcha: `supabase start` failing at "Initialising schema" with
`exec /usr/bin/tini: no such file or directory` meant a corrupt shared base
layer in the rootless store (the realtime image had no `/bin`, `/lib64`).
Re-pulling one image reuses the broken layer; `docker system prune -a`
(user-approved; deletes every image) fixed it.

The `.envrc` drift itself is unresolved — an operator decision (switch the
host to podman, or repoint `.envrc`).
