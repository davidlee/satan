# IMP-030: Break the flake composition cycle and retire the pub alias

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Violates SPEC-002 NF-002 (REQ-014). Host detail: `~/flakes/SATAN.md` § Composition quirks.

- satan's `agents` input is `github:davidlee/nix-config?dir=flakes/agents` — the repo `~/flakes` lives in — while `~/flakes` consumes satan. `follows` hides it in the host build; standalone satan builds take a different library rev.
- goad has no `follows` and resolves its own `flakes/pub` copy; satan-attrd, goad and `~/notes` still name the deprecated `pub` alias.

Option: give the jail library its own repo/flake so nix-config and satan both depend on it and neither on the other; migrate every `pub` user; add goad to `just update-local`.
