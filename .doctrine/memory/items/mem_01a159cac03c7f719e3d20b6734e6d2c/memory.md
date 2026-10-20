`/nix/store` here is a transplanted snapshot with an empty `/nix/var/nix`; there is no `nix` binary on PATH, so `nix build`, `nix eval`, `just check-jails` and any check reading a built launcher cannot run. The llm-gateway socket (`/run/llm-gateway-client`) is absent and no pi key is present, so a live run against a real model cannot be executed either.

An unprivileged `bubblewrap` binary from the store does work, but hand-building a jail is a second confinement story and must not be used to stand in for the flake form.

Consequence: any phase whose criteria are empirical under the real wrapped form lands `blocked` here, with the operator sequence recorded for a host that can build.
