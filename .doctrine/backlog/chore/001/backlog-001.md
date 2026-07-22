# CHR-001: Flip ~/flakes satan input path: -> github:davidlee/satan after push

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Context

Surfaced by the SL-012 conformance audit — RV-012 finding **F-2** (major,
follow-up).

The `~/flakes` satan flake input is currently `path:` (host-local, local-ahead of
origin/main). This is *correct while the satan repo is unpushed*, but it means the
flakes repo cannot build SATAN reproducibly from a clean clone — only on the
author's host, from the local checkout.

## Action

Once `~/dev/satan` is pushed to `git@github.com:davidlee/satan`, flip the flakes
satan input from `path:` → `github:davidlee/satan`, then `home-manager switch` and
confirm the jailed-satan-gptel-harness still resolves.

## Gate

Blocked on: `git push` of the satan repo to origin.
