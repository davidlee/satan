# ISS-052: Delegated pi runs mutate state outside their mandate

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

A delegated pi run should read, answer and — at most — write source in the tree it
was pointed at. Three ways it does not, observed on 2026-10-20 while wiring
`scripts/pi-agent` up as the delegation path:

## 1. The doctrine pi extension runs in the child and installs

`pi-agent` did not pass `--no-extensions`, so every `pi-scout` / `pi-research` run
loaded this repo's doctrine pi extension. Started from inside the jail, a scout
rewrote `.doctrine/state/boot.md` to name the jail's doctrine binary
(`/run/doctrine-bin/doctrine`). That path is wrong for every host session until
`doctrine boot` is re-run, and the failure is silent: the scout's answer was
correct, the state file was corrupted underneath it. On the host the same
extension fails the other way — that path does not exist there.

Underlying defect is in the extension, not the runner: it performs install/
bootstrap side effects in whatever tree it is started in, and rewrites authored
runtime state (`boot.md`) rather than refusing outside an explicit install.

## 2. Doctrine version drift is unfiled

`doctrine boot` warns: this checkout was installed by doctrine **0.46.7**, the
running binary is **0.46.8** — "run `doctrine install` and commit to move the repo
up, or use 0.46.7". Until that is done, state regenerated on one side is not
trustworthy on the other. This is the same install problem as (1) seen from a
different angle.

## 3. Profiles granted `write`, so scouts left brief files

`scout.md` and `researcher.md` declared `write` in their tool lists. A scout ran
from another repo left `.scout-brief-registry-install.md` in `~/dev/malebolge`
(deleted). The runner captures the answer on stdout, so the tool was never needed;
a prompt saying "read-only" does not help, because the profile grants the
capability.

## Landed mitigations (this repo)

- `scripts/pi-agent` passes `--no-extensions`; verified by re-running a scout and
  confirming `.doctrine/state/boot.md` kept its host path.
- `scout.md` and `researcher.md` no longer declare `write` (`.pi` is gitignored —
  local to each checkout, so this fix does not travel; it wants a tracked
  mechanism or a note in CLAUDE.md).
- `doctrine boot` re-run on the host; `boot.md` names
  `/home/david/.local/share/doctrine/bin/doctrine` again.

## Still open

- `doctrine install` to clear the 0.46.7 → 0.46.8 drift, and commit the result.
- The extension's side effects (upstream, doctrine): it should not rewrite
  authored state outside an explicit install, and should name a refused reason
  when it cannot resolve its own binary for the current context.
- Deciding where profile tool lists live so a per-checkout `.pi/agents/` is not
  the only home for a security-relevant restriction.
