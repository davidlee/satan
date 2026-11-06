# IMP-067: Close SPEC-002's empty Spec column where it pays — attribute layer and broker, anchors first

## The claim

SPEC-002 already publishes the gap, so this item does not argue that governance is missing
in the abstract. Its container table carries a `Spec` column: Harness → SPEC-003, Patch
runner → SPEC-004, Trust-boundary protocol → SPEC-001, and **`—` against eight containers** —
Broker, Attribute daemon, Interactive daemon, Perception, goad, Confinement, Shared database,
Text roots.

A census of the broker-side surface (2026-11-06, `8f67940`) says what that `—` costs:
**19,897 loc of elisp in 64 files**, of which the two largest mutually-reinforcing areas —
the memory substrate (2,722 loc) and perceptual assembly (2,598 loc) — have zero doctrine
anchors and zero specs. `docs/memory/design.md` and `docs/perceptual-design.md` are their
only design records, and both are drifting unguarded (docs-ledger §6).

The full census is `.doctrine/state/spec-coverage-map.md` (gitignored, as the harness census
is). Everything durable is below.

## What the census found

Sizes: broker core 8 files/2,565 loc · memory substrate 8/2,722 · perceptual assembly
8/2,598 · observer+intervention 4/2,489 · tools 16/4,192 · tick+budget+block+tank 4/960 ·
attribute elisp half 3/749 · patch client 4/803 · harness 1,459 Python · `satan-attrd`
~4,500 Rust in a second repo · tests 29,454.

Coverage: harness **covered** (SPEC-003), patch runner **covered** (SPEC-004),
trust-boundary protocol **partial** (invariants yes, but the broker files it names as sources
are not owned by it), tool modules **thin** (only the registry is anchored), attribute elisp
half **thin** (only the listener), and **dark**: attribute daemon, memory substrate,
perceptual assembly, observer/intervention, tick/scheduling, the shared database *as a
store*.

Two anchor defects found while checking liveness:

1. **SPEC-002's only anchor is `doctrine/cli`** — the shipped spec-skeleton leftover. The
   system context spec anchors nothing in SATAN, which is defensible (it is context-level)
   but should be explicit rather than accidental.
2. **Identifier forms disagree**: SPEC-001 and SPEC-003 write bare basenames
   (`satan-mode.el`), resolvable only by knowing the `satan/` convention; SPEC-004 writes
   repo-relative (`satan/satan-patch-rpc.el`). Both currently resolve; a reader or a future
   liveness check cannot tell which convention applies.

## Wanted — a plan, not a sweep

Three steps, in this order, and nothing else until they are done.

**1. Anchor repair (no new entity, minutes).**
Drop `doctrine/cli` from SPEC-002; settle one identifier convention (repo-relative, as
SPEC-004) across SPEC-001 and SPEC-003. This is the cheapest possible change that makes
"covered" mean something, and it should happen before any new spec is written so the new
specs are written in the settled form.

**2. SPEC-005 — Attribute layer** (container; parent SPEC-002).
One spec covering both halves — `satan-attrd` and its elisp consumer — because they share
one contract and one store; components are members, not separate specs. Drafting sources:
RFC-021 (state of play + the F findings), `docs/attributes/design-contract.md` (normative,
`authority: blocking`), `docs/attributes/wiring-status.md`, `satan-attrd/src` and
`migrations/0007-0012`, `docs/attributes/outcome-semantics.md`.
Why second: it is the only gap with an unblocked backlog behind it — RFC-021 **Q3** (where
does the contract live), ISS-011, IMP-063/064 — *and* a normative source to draft from, so it
can be authored without new decisions. It also carries the clearest risk: a second repo, a
second migration lineage, one shared database (**RSK-015**).

**3. SPEC-006 — Broker** (container; parent SPEC-002).
One container spec naming its components — context assembly, memory substrate,
tick/scheduling, observer/intervention, tool registry, output staging — and holding only the
invariants. Child component specs only when one earns it, the **memory substrate** first
(own schema, own grammar, own migrations, own design doc — it is separably a component).
Drafting sources: `docs/architecture.md` (live), `docs/perceptual-design.md`,
`docs/memory/design.md`, `docs/data-collection.md`, the `satan-broker.el` spawn sequence and
the `satan-context.el` render order.

Sequencing rationale: 005 before 006 because 006 will want to *cite* 005's store ownership
rather than restate it, and because 005 is decision-free while 006 will surface decisions
about what the broker owns versus what the daemon owns.

## Deliberately not in the plan

- **No spec for the shared database as its own container.** SPEC-002's invariant is
  "single schema owner per store", so ownership belongs to whichever spec owns each store:
  attribute tables to SPEC-005, traces and queues to SPEC-006. Whether that suffices is an
  Open Question for `/spec-tech`, not a proposal here.
- **Malebolge, goad, confinement, text roots stay `—`.** Cross-repo, described elsewhere
  (RFC-019, ADR-018, `~/flakes/SATAN.md`), and none of them is blocking SATAN work in this
  repo now. Filling the column for symmetry would produce documents nobody reads — the
  failure mode `docs/review/` already demonstrates.
- **Panopticon internals** are not a SATAN spec. The SATAN-side need is a *contract* (what
  may be read, how long anything is kept), which **ISS-065** holds.

## Acceptance

- `doctrine spec show SPEC-002` shows `SPEC-005` against the Attribute daemon row, and the
  Broker row no longer reads `—` (SPEC-006, or a recorded decision to defer it).
- No spec carries an anchor whose path does not resolve under one stated convention — and
  `doctrine/cli` appears in no SATAN spec.
- No new entity for the shared database, or an explicit decision recorded that one is needed.

## Open

- Does the attribute contract belong inside SPEC-005, or stay a `docs/` document the spec
  cites? (RFC-021 Q3; the contract is `authority: blocking` and predates doctrine.)
- Is SPEC-006 one container spec plus a memory-substrate component spec, or two container
  specs? The census proposes one-plus-one; the seam is real either way.
- Should the identifier convention be enforced by a check (a spec lint), or is a convention
  in a reference doc enough? Today nothing verifies an anchor at all.

## Relations

- RFC-021 — its Q3 is the attribute half of this item.
- RSK-015 — two migration lineages on one database; the symptom of the missing owner.
- ISS-065 — retention, backup and the store's ownership boundaries.
- CHR-014 — the mode/tool table drift that a broker spec would subsume.
