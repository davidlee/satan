## Decision

- **Identity.** A caller may pass `session`. If none is passed the server mints one and **returns it in the result** (`session`), so continuation does not require the caller to have planned for it.
- **Binding.** A session is bound on first use to (canonical root, filesystem capability). Resuming with a different root or capability is refused: `session-root-mismatch`, `session-capability-mismatch`. This stops a session becoming a cross-call privilege channel (a writer's context resumed under a reader profile, or vice versa).
- **Concurrency.** Same-session calls are **serialised by refusal** (`session-busy`), not queued. Queuing hides ordering bugs and doubles spend behind a driver's back.
- **Storage.** A server-owned session directory per session under `PI_MCP_RUN_DIR/sessions/<id>`, bound rw into the jail *by the wrapper form* (a contract item for the flake, alongside inq-5). Never inside the target repo: that would pollute a read-only root and land in a dispatch worker's imported delta.

## Amendment to DEC-089

DEC-089 said the session dir "must sit inside the bound root" because `/tmp` is a per-run tmpfs. That was a false dichotomy — the wrapper can bind a narrow, separate writable directory — and it pulled in two problems the review named: a read-only root cannot host a session dir, and artefacts inside the repo contradict the delta-cleanliness goal. The corrected rule: the session dir is server-owned, outside the tree, and bound narrowly by the wrapper. DEC-089's root-per-call decision is unaffected.

## Consequence

The session directory becomes part of the wrapper contract: the flake form must accept one extra rw bind. That is a second delivery dependency (with inq-5), and it should be a single flake change rather than two.


## Addendum (2026-10-20): the session home is outside the jail, and bindable

An external reviewer read this decision as "the session dir has to sit under the
repo, which the jail mounts". That is not required, and it is worth stating the
mechanism, because the wrapper's bind set is otherwise assumed fixed at build
time.

The wrapper is a generated shell script, and its raw bwrap args are expanded at
run time. `satan/flake.nix:161` already binds `"$SATAN_RUN_DIR"` that way. So a
per-call form can bind a **shared, persistent session home outside the tree**
(`PI_MCP_SESSION_HOME`, default under `PI_MCP_RUN_DIR/sessions`) with a raw
`--bind "$PI_MCP_SESSION_HOME" …` plus `--setenv`, and follow-on turns resume
across runs without the repo hosting anything.

Why this matters beyond tidiness: it is a reason for the server to exist. It
mints the session id, binds the home, keeps the audit and the transcript beside
it, and returns the id — so a reader-capability run on a read-only root can still
carry a conversation forward, which no bare `jailed-pi` invocation can do.

What is *not* optional: the bind must come from the flake form (raw arg plus
`--setenv`), because the server does not assemble bwrap. That is a contract item
on the per-call forms, recorded with the capability forms in DEC-098/DEC-100.


## RV-043 F-10: the grammar pi actually accepts

pi requires a session id to start **and** end with a letter or number
(`docs/cli.md` §Sessions). The first grammar allowed trailing `.`, `_` and `-`,
which pi then refused *after* the server had accepted the request. Corrected:
alnum at both ends, 1–64 characters, single-character ids valid:

```
^[A-Za-z0-9]([A-Za-z0-9._-]{0,62}[A-Za-z0-9])?$
```

Tested on trailing period, underscore and hyphen (refused `session-invalid`
before spawn) and on a valid one-character id.
