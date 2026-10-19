# ISS-041: satan-patcher clones with --branch HEAD; every job since the clone-based worktree fails

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Found 2026-10-16 while diagnosing ISS-030. Verified against the live queue.

`satan-patcher` (`~/dev/satan-patcher`, alias `~/dev/sloptower`) creates each
job's worktree with
`git clone --local --single-branch --branch <base_ref> <repo> <wt>`
(`internal/worktree/worktree.go:57-58`, since commit `3780216`, the
clone-based worktree for bwrap). `--branch` accepts only a branch or tag name.

The producer defaults `base_ref` to `"HEAD"`
(`satan/satan-tools-patch.el:97`), so every job fails at clone with
`fatal: Remote branch HEAD not found`. Affected: all four jobs since
2026-09-25 (`/home/david/dev/satan`, `/home/david/notes`, and two
self-edit-mind jobs on `/home/david/satan-corpus` on 2026-10-14). Only the May
smoke jobs, which passed `main`, got past clone.

This is a contract mismatch: the two sides disagree on what `base_ref` may be.
Fix it on one side: the daemon resolves a symbolic ref to a branch (or clones
and then checks out the ref), or the producer always sends a branch name.

This is the first wall in a stack. After it come the `jailed-pi` resolution
failure and the review cherry-pick bug (both ISS-030). Settle the patcher's
direction first (ISS-030, ISS-039: oubliette rebuild vs fixing in place); this
fix is needed under either.

## Closed by SL-023 audit (RV-029 F-19, 2026-10-19)

The runner contract takes `baseRef` as a real-repo branch (check-ref-format + refs/heads); `HEAD` is refused and the producer sends none by default — the runner uses the repo's `default_branch` (DEC-059; closure jobs' base_oid 6fe3a49).
