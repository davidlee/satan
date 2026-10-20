## Decision

- **Identity.** A caller may pass `session`. If none is passed the server mints one and **returns it in the result** (`session`), so continuation does not require the caller to have planned for it.
- **Binding.** A session is bound on first use to (canonical root, filesystem capability). Resuming with a different root or capability is refused: `session-root-mismatch`, `session-capability-mismatch`. This stops a session becoming a cross-call privilege channel (a writer's context resumed under a reader profile, or vice versa).
- **Concurrency.** Same-session calls are **serialised by refusal** (`session-busy`), not queued. Queuing hides ordering bugs and doubles spend behind a driver's back.
- **Storage.** A server-owned session directory per session under `PI_MCP_RUN_DIR/sessions/<id>`, bound rw into the jail *by the wrapper form* (a contract item for the flake, alongside inq-5). Never inside the target repo: that would pollute a read-only root and land in a dispatch worker's imported delta.

## Amendment to DEC-089

DEC-089 said the session dir "must sit inside the bound root" because `/tmp` is a per-run tmpfs. That was a false dichotomy — the wrapper can bind a narrow, separate writable directory — and it pulled in two problems the review named: a read-only root cannot host a session dir, and artefacts inside the repo contradict the delta-cleanliness goal. The corrected rule: the session dir is server-owned, outside the tree, and bound narrowly by the wrapper. DEC-089's root-per-call decision is unaffected.

## Consequence

The session directory becomes part of the wrapper contract: the flake form must accept one extra rw bind. That is a second delivery dependency (with inq-5), and it should be a single flake change rather than two.
