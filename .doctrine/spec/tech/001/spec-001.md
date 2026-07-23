# SPEC-001: SATAN trust-boundary protocol

## Overview

The trust boundary is a **protocol, not a process** (ADR-017 §2). Safety does not
hold because untrusted model output happens to pass through Emacs broker code; it
holds because every surface that can enact an action satisfies a fixed set of
invariants — schema-validated actions, mode/tool allowlists, append-only audit,
token ceilings, kill switches — regardless of which process runs the enforcement.
This spec writes that protocol down.

It exists because ADR-017 records it as an **obligation due before the first
authority item migrates**, and resolved (its OQ) that the vehicle is a *tech
spec* rather than an extension of `architecture.md` — precisely so it carries
addressable requirement ids. The ADR-017 §3 authority ledger cites those ids per
row, and each extraction's audit verifies the migrated invariant against
something addressable rather than against prose. RFC-017 places this spec as gate
**G1** on the critical path `G1 → G2 (ledger) → D4.2 (policy/registry)`.

**C4 frame.** Container-level, cross-cutting: the protocol spans the daemon core
(future owner of policy + registry, ADR-018 D2), the Emacs client (permanent
owner of human-approval surfaces), the Python harness, and any future surface.
Posture is **forward-intent** — the invariants exist today implicitly in broker
code (`satan-mode.el`, `satan-tools.el`, `satan-audit.el`, the JSONL protocol);
this spec states them as a contract before they are re-homed. Its requirements
are `pending`; observed coverage is reconciled at each migration's audit, never
inferred here. The spec is **anchor-free** for now — the corpus has no PRD to
descend from and no container spec to parent to; it is reparented when the
whole-system context spec is authored (ADR-018 D1).

## Responsibilities

1. **The invariant set.** Define the trust-boundary invariants every surface must
   satisfy to enact an action: schema validation, allowlist gating, append-only
   audit, ceiling enforcement, kill-switch honouring. Each is an addressable
   requirement (below).
2. **The policy artifact.** Specify the read-only mode/tool/capability/budget
   artifact (ADR-018 D2) — its schema, its single owner (the daemon core), its
   versioning, and the contract that every surface *reads* it and none *restates*
   it.
3. **The control plane.** Specify the control-plane RPC surface (ADR-018 D3):
   which operations are request/response (capability decisions, run lifecycle,
   ledger handoff, kill), and the data-plane / control-plane split that keeps
   durable append-only logs for perception/evidence/audit while retiring the
   `*_inbox` + `pg_notify` + `notify-stream` bridge.
4. **The authority inventory.** Define the single-owner ledger contract
   (ADR-017 §3): every authority item names exactly one owner at any time, with
   the transition recorded as it migrates. This spec owns the *contract*; the
   ledger instance is stood up by RFC-017 G2.

It does **not** own: the daemon topology or transport choice (ADR-018), the
per-module extraction gate (POL-001), or any single extraction's design (that
slice's `/design`).

## Concerns

- **Security — the RPC surface is a new boundary.** ADR-018 OQ-2: today privilege
  separation is partly implicit in "it is all one trusted Emacs." An explicit RPC
  control plane must not weaken it. This spec states the invariants the surface
  must preserve; it does not design the surface (that interacts with OQ-2 and must
  not be front-run — see Hypotheses).
- **Failure modes — fail closed.** With the Emacs client absent, daemons enforce
  their own ceilings and never fall open (ADR-017 §4). A tripped kill switch, an
  exhausted budget, or an unreachable policy artifact must deny enactment, not
  default-permit.
- **Half-migration is the dominant hazard.** An invariant enforced in two places
  or in neither is worse than either end-state (ADR-017 negative consequence 3).
  The single-owner ledger and the no-dual-enforcement requirement exist to make
  the hazard checkable (grep both sides at each audit).
- **Readability outside an editor.** The policy artifact must be answerable by a
  non-Emacs process (ADR-018 VT-1); an invariant that can only be evaluated by
  booting an editor is unverifiable.

## Hypotheses

- **The invariant set is complete as five plus authority.** Schema validation,
  allowlist gating, append-only audit, ceilings, kill switches (ADR-017 §2) plus
  the single-owner authority inventory (§3) cover the trust boundary. If a sixth
  invariant surfaces during migration, it is added here as a requirement, not
  smuggled into a slice.
- **Control/data split is stable.** Perception, segments, evidence and audit are
  genuinely append-only-log-shaped (the panopticon pattern, RFC-001 D5); only
  capability/lifecycle/ledger/kill are genuinely request/response. If a datum
  turns out to need both, this hypothesis is revisited before D3 lands.
- **The spec can precede the RPC design.** The invariants are statable
  independently of the wire format and transport of the control plane (ADR-018
  OQ-2). This spec asserts *what must hold*; it leaves *how the surface is shaped*
  to the OQ-2 design, requiring only that the design preserve every invariant.

## Decisions

Local technical decisions (project-global ones are ADRs — ADR-017 for the
boundary-as-protocol thesis, ADR-018 for topology/transport):

- **Invariants are stated surface-agnostically.** No requirement names Emacs, the
  daemon, or the harness as its enforcer; each names the *property* and leaves the
  owner to the ledger. This is what lets an authority item migrate without
  rewriting the invariant.
- **Requirements are the ledger's citation targets.** Each functional invariant is
  a `REQ` a ledger row can cite; the quality requirements (single-enforcement,
  fail-closed, surface-agnostic, addressable) are the cross-cutting checks each
  migration audit re-runs.
- **Retrospective where already true.** Where an invariant is already enforced in
  broker code, the requirement is written to match the shipped behaviour so the
  first ledger owner (Emacs) is accurate on day one; migration moves the owner,
  not the requirement.
