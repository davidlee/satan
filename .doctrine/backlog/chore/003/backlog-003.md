# CHR-003: Retarget satan-patcher prompt default to the relocated corpus (SL-015 follow-up)

SL-015 moves the model-facing corpus from `~/notes/satan/` to `~/satan/`.
`satan-patcher` (separate repo, `~/dev/satan-patcher`) carries the old path as
its built-in default in five places:

| File | Ref |
|---|---|
| `cmd/satan-patcher/main.go:52` | `getenv("SATAN_PATCHER_PROMPT", "$HOME/notes/satan/patch-agent/prompt.md")` |
| `nix/module.nix:74` | option default `%h/notes/satan/patch-agent/prompt.md` |
| `README.md:115,137` | env table + example config |
| `docs/contract.md:108` | example config |
| `docs/handover.md:213` | prose reference |

**Not urgent, and nothing breaks in the meantime.**
`~/.config/systemd/user/satan-patcher.service:9` pins
`Environment=SATAN_PATCHER_PROMPT=...` explicitly, and SL-015 retargets that
line as part of the config sweep. The daemon therefore keeps resolving its
prompt after the move; only the *unpinned* default (a fresh install, a manual
`satan-patcher` invocation, or the nix module used without an explicit
`prompt =`) would dangle.

Deferred at the user's direction (2026-08-22): the daemon is not in active use
and may be replaced outright, which would make this work moot. Revisit when
satan-patcher is next touched — or close as obsolete if it is replaced
(see IMP-006, the patch-runner extraction that produced it).
