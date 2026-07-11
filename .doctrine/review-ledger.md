<!-- Shipped reference (ADR-005 PULL tier). Edit the source in
     `install/review-ledger.md`; the installed copy at `.doctrine/review-ledger.md`
     is inert. Names verbs and states the invariant protocol — it never reproduces
     `doctrine review --help`; ask the CLI for exact flags. -->

# The review ledger

How to drive a review on the **RV kind** (`RV-NNN`, ADR-007) — the structured,
append-only audit substrate the hand-made `audit.md` lacked. This doc owns the
*invariant* protocol shared by every review skill (`/audit`, `/code-review`,
`/inquisition`): pick the subject, open + prime, raise, dispose + resolve,
synthesize + harvest, close. Each skill restates the trigger in its own voice and
keeps its own lens and harvest tail — but the mechanics live here, once.

For **exact command shapes and flags**, ask `doctrine review <command> --help` —
this doc names verbs, never their flag tables. For the work/knowledge/decision
boundary, see `using-doctrine.md`; for ids and the verification taxonomy, see
`glossary.md`.

## §1 — Pick the subject

A review needs a **subject**: the thing findings attach to and outlive the
conversation against. Steer toward a *proximate, typed* subject — the closer the
RV's `--target` sits to a real doctrine entity, the more the findings can be
queried, gated, and handed off later.

**Target ladder** (descend only when the rung above genuinely does not fit):

1. **A slice or phase** — the implementation, design, or plan artifact under
   review. The strongest subject; an audit lives here always.
2. **A backlog item** — `issue` / `improvement` / `chore` / `risk` / `idea`
   (`ISS-` / `IMP-` / `CHR-` / `RSK-` / `IDE-`). A durable diff or
   investigation with no slice yet still has a typed home here.
3. **Create one** — if no proximate subject exists but the work is durable,
   `doctrine backlog new <kind>` mints one, *then* target it. A review worth the
   ledger is worth a subject; do not skip to prose to dodge the mint.
4. **Prose, last resort** — only an explicitly throwaway one-shot with no durable
   subject, no lifecycle gate, no handoff, and no finding that should survive.

`--target` is a **validated canonical ref**: `doctrine review new` refuses a
target that does not resolve, so a backlog kind is only a legal target once it
exists (rung 3 before rung 2's degenerate case). The full ladder is presented
here, but **each consuming skill pins which rungs apply** — an audit always
targets its slice (rung 1) and never degrades to prose.

### The ledger-vs-prose trigger

Drive the ledger when the review is **closure-grade** — it:

- gates a lifecycle move (a slice's `audit→reconcile→done`), **or**
- runs adversarially across more than one round, **or**
- hands off between agents, **or**
- raises findings that must outlive the conversation.

An existing doctrine subject — a slice, a phase, a backlog item, a slice-tied
implementation diff, a design or plan artifact — makes that presumption **strong**:
open an RV. Durable diff-only work with no subject yet → create/use a backlog
target (rung 3). Reserve **prose** for the genuinely throwaway one-shot above.

The **cost asymmetry is the test**: an RV that turns out trivial cost a few verbs;
a prose review whose findings mattered is lost the moment the context clears. When
the two are close, open the ledger.

## §2 — Open + prime

### Facet

Pick the **facet** by *what aspect you interrogate* — the subject's lifecycle
aspect (e.g. `reconciliation` for a post-implementation audit). The facet always
names a **lifecycle aspect, never a posture** (INV-2). An adversarial *posture*
(inquisitor, devil's advocate, …) rides `--raiser <label>` — **never** a bespoke
facet. Same subject, same facet, different raiser label: that is how a posture is
expressed.

### Open

```
doctrine review new --facet <F> --target <REF> [--phase <P>] [--raiser <L>]
```

`<REF>` is the canonical ref from §1's ladder; `--phase` narrows to one phase;
`--raiser` stamps the posture label.

### Prime

Warm the reviewer context so the staleness signal has a path-set to hash:

1. `doctrine review prime RV-NNN` — populates the warm-cache from the **target
   slice's selectors** (`scope-relevant` + `design-target`; the path-set the
   staleness signal hashes). One call, no curation step. (The hand-authored
   `domain_map` of areas/invariants/risks was a dead authoring tax — retired in
   SL-147; selectors, seeded at `/slice` and `/design`, are the path-set now.)
2. Seed the ledger's `## Brief` (in `review-NNN.md`) with the **lines of attack**:
   what this review is probing and the invariants it pins the subject to — this is
   where the reviewer's intent lives, not in a persisted map.

`doctrine review status RV-NNN` reports `cache: current` / `stale` as an
**optimization signal, never a gate** — a stale cache costs a re-prime, not a
refusal.

## §3 — Raise findings

```
doctrine review raise RV-NNN --severity <S> --title <expected vs observed> \
  --detail <evidence>
```

The **raiser owns `severity` / `title` / `detail`**, fixed at raise — the ledger is
append-only, so frame each finding as *expected vs observed* with its evidence the
first time.

**Severity vocab** — `blocker | major | minor | nit`:

- **`blocker`** is the only severity that gates the *target's* close. An unresolved
  blocker on an active RV refuses the `audit→reconcile` and `reconcile→done`
  transitions (the close-gate teeth, enforced in the binary; D-C9b). Reserve it for
  findings that must not ship unreconciled.
- **`major` / `minor` / `nit`** record the finding but never block close.

## §4 — Dispose + resolve

Every finding gets an explicit disposition, then a terminal close:

```
doctrine review dispose RV-NNN --finding F-n --disposition <vocab> \
  --response <rationale> --as responder
```

**Disposition vocab** (use consistently):

- **aligned** — observed behaviour is already correct; no follow-up.
- **fix-now** — reconcile inside the current unit of work before closing.
- **design-wrong** — the design, not the code, is the defect; reconcile the design
  artifact (and scope) so canon tells the truth.
- **follow-up** — owned future work is the right route; capture it (`backlog new`).
- **tolerated** — explicit unresolved drift, with rationale, only when the tradeoff
  is consciously accepted.

Then close each finding **terminal**:

- `doctrine review verify RV-NNN --finding F-n --as raiser` — accept (terminal).
- `doctrine review contest RV-NNN --finding F-n --as raiser` — disagree; hand back
  (answered → contested) for re-disposition.
- `doctrine review withdraw RV-NNN --finding F-n --as raiser` — a finding **raised
  in error** is retracted (terminal), *not* disposed.

**Caveats:**

- `--note` on `verify` / `contest` is **ephemeral baton chatter** for the log, NOT
  durable rationale — durable justification belongs in the finding's `response` or a
  new finding (D10).
- **Self-review** drives both roles via `--as` (raiser raises / verifies /
  withdraws; responder disposes). The per-review lock and the per-finding `can()`
  gate keep a one- or two-party review correct; `--as` is **cooperative role
  assertion, not a security boundary** (ADR-007).
- Loose conversation notes are **insufficient** for closure-grade work — findings
  live in the ledger, not the conversation.

### Anti-escape guardrails

- Do **not** pick **follow-up** because the fix feels large.
- Do **not** normalise **tolerated** without a real rationale.
- Do **not** downgrade a true **blocker** to dodge the close-gate.
- Unresolved ambiguity after reading the design and governance → stop and
  `/consult`. Do not improvise a disposition.

## §5 — Synthesis + harvest

When the findings are resolved, append a `## Synthesis` section to
`review-NNN.md` — the narrative the old `audit.md` carried: the **closure story**,
the **standing risks**, the **tradeoffs consciously accepted**. The ledger holds
the structured findings; the synthesis holds the prose that ties them together.

Then **harvest — judgment-gated, not mandatory**. *When durable findings exist*,
promote them per the work/knowledge/decision boundary (`using-doctrine.md`):
durable facts/patterns/gotchas → `/record-memory`; durable follow-up **work** →
`backlog new`; notes that belong with the subject → its `notes.md`. A clean review
harvests nothing — that is a valid outcome, not a skipped step.

Generic review-harvest is thin by design; **skill-specific harvest tails stay in
the owning skill** (e.g. an audit's phase-sheet harvest).

## §6 — Done + close-gate

A review is **done** when **every finding is terminal** — verified or withdrawn
(D-C9a). `doctrine review status RV-NNN` then reports `done · await=none`. Done is
about the *ledger*; closing the *subject* is the next, separate move.

The **close-gate** (D-C9b): an unresolved `blocker` on an active RV refuses the
target's closure transitions — resolve it (`verify` or `withdraw`) before the
subject can advance. `major` / `minor` / `nit` never gate.

**Parent-tree caveat.** Drive reviews from the **parent tree** — the `doctrine
review` verbs refuse a worktree/fork-resolved root. Run a review from the main tree
(or merge the fork first), never from inside an isolated worktree.
