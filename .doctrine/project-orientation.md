# Project Orientation

## Project Purpose

SATAN (Scheduled Agent for Textual Attention and Notes) is a local,
Emacs-mediated, org-backed, harness-agnostic agent runtime for one user's
personal orchestration. On a schedule it reads personal context (org notes,
browser / git / window-manager activity via panopticon, its own memory),
reasons over it through a model harness, and produces bounded, inspectable
effects through a trusted broker. Not a chatbot, not a general automation
daemon: the priority is safe, inspectable, evolvable agency, not maximum agency.

## Guiding Principles

- **Identity is the durable "DNA", not the model or harness:** prompt corpus,
  self-authored memory, permission model, jail constraints, tool protocol,
  schedule, audit trail. Models and harnesses are interchangeable.
- **Proposal-first.** Effects on the user's material are staged for review;
  nothing auto-applies.
- **The trust boundary is a protocol, not a process** (ADR-017). Each
  authority item (allowlists, ceilings, audit append, kill switches) has one
  owner, recorded in the ADR-017 §3 ledger. Emacs owns human approval surfaces.
- **Emacs is a client** (ADR-017). Code that doesn't use the editor as an
  editor is an extraction candidate (POL-001 earns-the-seat test), targeting
  Rust daemons per ADR-018. Every extraction gets a disable switch.
- **Three roots, never mixed:** notes (`~/notes`, the user's, read-only),
  corpus (`~/satan`, SATAN-authored), state (`~/.local/state/satan`,
  discardable). All paths are `satan-{notes,corpus,state}-path` joins.
- **No fallbacks for framing text:** a wrong-but-readable path is worse than
  an error.

## Architecture

A broker in Emacs assembles a context bundle (prompt + framing + percept +
resonance + motive + sensors + attributes), spawns a harness over a JSONL wire
protocol, mediates tool calls against a per-mode allowlist, writes outputs
(org blocks, notifications, proposals) and an audit bundle per run. Postgres
(always via `psql` `call-process`, never an elisp PG library) holds the memory
trace store, patch jobs, and interventions.

Major components (all in `satan/`, prefix `satan-`):

- **Core** — `satan.el` (entry), `-broker`, `-mode`, `-protocol`, `-output`, `-audit`, `-run`
- **Custom** — `satan-custom.el`: zero-dep leaf; roots, path joins, `satan--root`
- **Context/perception** — `-context`, `-percept`, `-resonance`, `-motive`, `-sensor-*`
- **Memory** — `-memory*` (grammar, canonicaliser, evidence, store, migrations)
- **Tools** — `-tools.el` registry + `-tools-*` modules, registered at load time
- **Patch agent** — `-patch*`: jailed code-change proposals in worktrees
- **Attributes / observer / intervention** — behavioural state and outcome classification
- **Scheduling** — `-tick`, `-budget`, `-block`, `-tank`
- **Harness** — `satan/harness/` (Python): model-side runloop and providers

Trip hazards: `satan-broker--spawn` is a flat, order-sensitive `let*`; the bare
roots are literal `~` strings, so `expand-file-name` before `call-process`.

## Structure

- `satan/` — package source (Elisp); `satan/test/` — ert suites + fixtures
- `satan/harness/` — Python harness; `satan/protocol/fixtures.json` — wire fixtures
- `satan/memory/migrations/` — SQL migrations; `satan/bin/` — run/tick entry scripts
- `dev/satan-test.el` — batch test runner
- `docs/` — design docs; start at `docs/INDEX.md`, then `governance.md`, `architecture.md`
- `.doctrine/` — governance: slices, ADRs, policies, specs, backlog, memory
- `~/satan` (separate repo) — model-facing corpus; corpus-dependent tests `skip-unless` it exists
- `~/flakes` (separate repo) — Nix system config: systemd timers (`modules/home/linux/satan.nix`),
  and this repo as a flake input pinned to GitHub, not the local checkout

## Conventions

- Every symbol is `satan-*`; private helpers `satan-foo--bar`.
- Conventional commits, scoped by slice where one governs: `feat(SL-017): …`,
  `docs(SL-018): …`; otherwise by area: `fix(mcp): …`.
- Change is governed by doctrine slices (`doctrine slice new` → design → plan → execute → audit → close).
- Rust for extracted daemons (POL-001); a shared `satan-core` crate is planned, layout still open (RFC-017).

## Tooling & Development Workflow

- Enter the Nix devshell (`nix develop` / direnv): provides Emacs, Python,
  psql, supabase, doctrine.
- Test DB: the local Supabase Postgres (127.0.0.1:54322). The justfile exports
  `PG*` + `SATAN_DB_HOST` for it (override with `SATAN_TEST_PG*`); nothing
  falls back to the system socket. One-time: `just db-start` (outside the
  jail), then `just db-setup`.
- `just check` — lint + test. `just lint` — paren balance only
  (`bin/elisp-locate-paren-error`). `just test` — ert in `emacs --batch`
  (interpreted, never byte-compiled) + Python harness unittests. Fails if a
  test fails or a test DB is unreachable (`SATAN_TEST_ALLOW_NO_DB=1` opts out).
- Run the suite serially: concurrent runs corrupt the shared test DBs (ISS-013).

## Further Reading

1. `docs/INDEX.md` — index of all design docs
2. `docs/governance.md`, `docs/architecture.md`, `docs/protocol.md`
3. ADR-017, ADR-018, POL-001 — `doctrine adr show ADR-017` etc.
4. `docs/memory/design.md`, `docs/perceptual-design.md`, `docs/patch/brief.md`
5. `README.md` — sibling projects (panopticon, satan-attrd, sloptower, goad)
