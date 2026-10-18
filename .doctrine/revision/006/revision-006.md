# REV REV-006 — ADR-018 scope: workload-fit placement and process-private state (SL-023)

Revision — a pending revise-intent against authored governance/spec
truth. The structured `[[change]]` payload lives in the sister `revision-NNN.toml`;
this prose companion carries the rationale and the free-text before/after excerpts
for prose-body section edits.

## Rationale

SL-023's design puts the patch runner in a TypeScript binary in
`~/dev/malebolge` (DEC-051) and keeps its job state in a runner-local SQLite
file (DEC-052). Read literally, ADR-018 D1 ("the headless core … lives in a
single repository, expected to become a Cargo workspace") and D3 ("Durable
state stays in Postgres") forbid both. An informal pre-lock review (finding 8)
held that a design must not lock against an accepted ADR with the drift only
noted. The keeper chose to amend ADR-018's scope now (2026-10-18, reply
"a)"), not to conform and not to defer to reconcile.

Why the scope, not the decisions, gives way:

- The runner's enforcement points (path allowlist, ceilings, abort) are hooks
  inside pi-durable, which exists only as a Node library. A Rust core would
  either call back into the harness per tool call or split one authority
  across two processes. POL-001 already admits workload-fit exceptions
  (panopticon).
- No process other than the runner reads job state once Emacs speaks RPC
  (DEC-050, DEC-058). Postgres's value in SATAN is state shared across
  processes; and one SQLite file is what lets job rows and pi-durable
  transcripts commit together (DEC-052).

Neither clause changes D3's control-plane rule, D2's policy ownership, or the
one-owner-per-item ledger rule.

### Change 1 — ADR-018, new `## Amendments` section before `## References` (modify)

Before: *(no Amendments section)*

After:

> ## Amendments
>
> **2026-10-18 — workload-fit placement and process-private state (REV-006,
> SL-023).** Two scope clauses; the decisions are otherwise unchanged.
>
> 1. **D1.** The single daemon repository holds the headless core. A
>    component whose authority-enforcement points are hooks inside a library
>    that exists only in another language may stand outside it by recorded
>    workload fit (POL-001, as for panopticon). It takes exactly one ledger
>    owner per item it enforces and gains no authority over any item the core
>    owns. First instance: the patch runner, a TypeScript binary in
>    `~/dev/malebolge` hosting pi-durable (DEC-051). Moving it into the core
>    repository later changes no owner.
> 2. **D3.** "Durable state stays in Postgres" means Postgres is SATAN's
>    *shared* state store: state that more than one process reads or writes
>    lives there. State private to one process, which other processes reach
>    only through that process's RPC, may live in its own store. First
>    instance: the patch runner's jobs and transcripts in one SQLite file
>    (DEC-052). The control-plane rule is unchanged.

And at the end of D1's and D3's paragraphs, the pointer *"(Scoped by the
2026-10-18 amendment.)"*

### Change 2 — POL-001 `### Extraction candidates` and `### Standing principles` (modify)

Before (candidates): *"**IMP-006** patch runner → `satan-patcher`
(pivot-pending, in flight)."*

After: *"**IMP-006** patch runner → a TypeScript runner binary in
`~/dev/malebolge` hosting pi-durable (SL-023, DEC-051), by workload fit under
ADR-018's 2026-10-18 amendment. Retires both the elisp runner and the Go
`satan-patcher`."*

Before (principles): *"`satan-patcher` being Go is incidental; panopticon
being Python is workload fit and stands."*

After: *"panopticon being Python and the patch runner being TypeScript
(pi-durable) are workload fit and stand."*

Plus a dated entry under `## Amendments`:

> **2026-10-18 — the patch runner's destination (REV-006, SL-023).** IMP-006's
> destination moves from the Go `satan-patcher` to a TypeScript runner in
> `~/dev/malebolge`, by workload fit under ADR-018's amendment of the same
> date. The test, triggers and principles are otherwise unchanged.
