# IDE-012: Oubliette rooms honour a per-repo setup step before a job

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Why

Rooms ignore a target's `refresh`/`baseline`/`commands`; only slots run them
(`~/dev/oubliette/docs/contract-target.md:346-351`, `host/refresh.nix`). A
patch job that needs generated, gitignored state (deps, codegen, doctrine's
`boot.md`) has no general way to get it. SL-026 DEC-071 handles doctrine boot
alone by having the runner run `doctrine prompt resolve` in the room during
`preparing`.

## Idea

Rooms honour a per-repo setup command, run in the clone as the repo user with
the repo's `toolsPackage` on PATH — at push, or (better, for freshness) per job
via a runner step. Revisit when a second setup need appears beyond doctrine.
Cross-repo: oubliette contract change, plus the runner's `preparing`.
