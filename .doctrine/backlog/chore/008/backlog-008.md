# CHR-008: Stale governance claim rides every boot: SPEC-001 and the authority ledger both exist

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

`.doctrine/governance.md:15` asserts:

> Before the first authority item migrates: the protocol tech spec and the
> authority ledger must exist (ADR-017 verification). **Neither is written yet.**

Both now exist:

- **SPEC-001** — SATAN trust-boundary protocol (tech spec, `draft`, REQ-001..012).
  This is the vehicle ADR-017's first open question resolved on 2026-07-22.
- **The authority ledger** — `.doctrine/adr/017/authority-ledger.md`, stood up
  **2026-07-24 by SL-014** (RFC-017 gate G2), seven rows, day-one owner
  `emacs-client` for every item. ADR-017 §3 was amended in place to link it.

## Why it matters more than a stale line

`.doctrine/governance.md` is inlined into `.doctrine/state/boot.md` and thence
into every session's prefix via `CLAUDE.md`. So **every agent boots believing the
ADR-017 migration gate is still shut.** An agent reasoning about whether an
authority item may move will either block on a gate that has already cleared, or
spend a research round rediscovering that it has.

Observed 2026-09-23: a `/canon` pass on the ISS-012 credential question routed
its first step specifically to test whether this gate barred a service-account
token. It does not — the claim was stale by two months.

## Fix

Correct the line to record both artefacts as landed, citing SPEC-001 and the
ledger path, and keep whatever obligation genuinely remains (the spec is
`draft`, and its requirements are all `pending` — that is a real caveat, and
distinct from "not written").

Then `doctrine boot` + `/clear` — regenerate *then* clear, since `doctrine boot`
alone cannot refresh an already-inlined prefix.

## Adjacent, do not conflate

`.doctrine/governance.md` may hold other assertions that have aged out of true
the same way. Worth one sweep of the file against the live corpus while it is
open, rather than fixing this line alone.
