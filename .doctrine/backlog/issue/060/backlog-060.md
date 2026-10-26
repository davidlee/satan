# ISS-060: satan .envrc DOCKER_HOST names a podman socket the host lacks

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Context

`.envrc:10` exports `DOCKER_HOST=unix:///run/user/1000/podman/podman.sock`.
On Sleipnir (2026-10-26) podman is not installed; the host runs rootless docker
(`~/flakes/features/virt.nix`; `virt.docker` and `virt.podman` exclusive). So
`just db-start` fails with "Cannot connect to the Docker daemon" until
`DOCKER_HOST` is overridden. Recipe and gotchas:
mem.fact.satan.test-db-on-rootless-docker.

Operator decision: switch the host back to podman, or repoint/derive
`DOCKER_HOST` in `.envrc` (e.g. prefer whichever socket exists).
