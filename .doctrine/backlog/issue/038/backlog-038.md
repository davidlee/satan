# ISS-038: Patch adapter resolves jailed-pi from the calling buffer's PATH; jailed-pi is not installed globally

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Same class as ISS-037 (split from it, 2026-10-14). `satan-patch-adapter-pi`
runs `satan-patch-adapter-pi-program` (default `"jailed-pi"`) via
`executable-find` over the calling buffer's `exec-path`, and spawns with the
calling buffer's `process-environment` / `default-directory`. `jailed-pi` is
not on Emacs's global PATH (only the `~/dev/satan` devshell provides it), so
the adapter resolves only from devshell buffers, and which build runs depends
on the buffer.

Undecided: where `jailed-pi` should come from (pinned `home.packages`
install, or retired in favour of `satan-patcher`, which is running as a
user service). Resolve as part of the harness spec's provenance section
before touching code.

## Closed by SL-023 audit (RV-029 F-19, 2026-10-19)

`satan-patch-adapter-pi.el` is deleted (satan 01dab54); the runner runs pi's tools in the oubliette room through pi-env under its own unit PATH (SL-023 PHASE-12/13).
