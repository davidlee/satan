# CHR-017: Package malebolge as a flake input before SL-023 closure

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

**Origin:** SL-023 PHASE-12 deploy-source ruling (user ruling 2026-10-19).
The `satan-runner` user unit runs `src/runner-main.ts` from malebolge's live
working tree (`~/dev/malebolge`) with `nodejs_24`, because malebolge has no
flake and `~/flakes` has no malebolge input.

**Do:** package malebolge (it has no flake yet) and add it as a flake input
in `~/flakes`, so the runner unit runs a pinned build instead of the live
tree; update `~/flakes/SATAN.md` (unit source, pin).

**Why:** a deployed daemon running a mutable working tree changes whenever
the tree does — an uncommitted edit or a branch switch is a deploy.

**Must land before SL-023 closure.**
