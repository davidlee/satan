# SL-036: Tick scheduling — read the decision, then shadow a policy oracle before any new clock

> **Id namespace note.** Ids in this checkout continue the imported corpus numbering, so
> `SL-036` here is not the frozen `.emacs.d` corpus's `SL-036`; references to `SL-002`,
> `SL-023`, `SL-034` in this repo's prose point at that frozen register. When in doubt,
> qualify by repo.

## Why

The tick loop is SATAN's least inspectable machinery and the place where "why did a run
happen" should be answerable and isn't. A proposal on the table was to stand up a new
scheduler in Python/TypeScript on a 10-minute systemd timer, calling `emacsclient -e` on
its own terms. The diagnosis behind it is right — the loop is the right target, "every
writer has a reader" is the right invariant, and self-proposable machinery is the prize —
but the wiring is wrong in a way that would cost us the ability to answer the question we
are asking:

- It is a **second clock inside the trusted path**, which answers O5a (scheduling authority)
  by implementation while `RFC-021` records that decision as the operator's and open.
- `emacsclient -e` is **server-eval**: arbitrary elisp in the privileged client — the very
  surface `ADR-017` replaces with validated, schema-checked actions.
- The arithmetic forbids it anyway: 100k tokens/run against a 2.5M/day ceiling is **≤25
  runs/day**, so a 144-events/day pulse cannot be runs. What is actually wanted is a
  **decision oracle**; the run-start is a separate act.

So this slice builds the decision, not the clock, and keeps the clock's current owner.

## What changes

Three increments, each useful without the next, each reversible.

1. **A reader over what runs already record.** A `tick_explain` surface (function + a
   read-only tool) answering, for a given tick or a time window: did a tick fire, if not
   why not, what did it see (percept handles, resonance, motive, sensor freshness), what
   did it cost, and what did it produce — assembled only from artefacts that already exist
   (`runs/<date>/<id>/{percept,bundle,actions,final}.json`, `transcript.jsonl`, the
   `kind:"tick"` trace rows, `satan-budget-today-total`). No new schema, no new write path.
   This is the operational-visibility goal, and it is the falsifier for the whole slice.
2. **`policy_oracle` — a prototype in Python, not a scheduler.** One file-shaped contract:
   `decide(percept, attributes, budget, freshness) -> (start|decline, reason, evidence)`.
   It takes `satan-resonance--admittable-p` (`satan-resonance.el:46`) as its baseline and
   the 5:3 tick pool as its only scheduling input. No spawn, no `emacsclient`, no clock, no
   database write. Testable offline against recorded bundles.
3. **Shadow mode.** The existing timer invokes the oracle *before* the tick; the oracle
   writes its decision (start/decline + reason + evidence) to a file; the tick reads it and
   records both answers — elisp's and the oracle's — including agreement, disagreement and
   the reason on each side. **No authority moves.** The output is a disagreement corpus,
   which is the only evidence that could justify a real scheduler later.

Disposable means: deleting the oracle directory and the shadow call site restores today's
behaviour exactly, with no migration and no data conversion.

## In scope

- `satan/satan-tick.el`, `satan/satan-budget.el` — a reader path, and the shadow call site.
- `satan/satan-trace.el` — one additive row kind for a decision record (or reuse of the
  existing tick row shape, if that is sufficient; the design decides).
- A new prototype directory for the oracle and its tests (proposed: `dev/tick-oracle/`,
  kept out of the shipped package and out of the load path).
- The systemd unit's pre-tick invocation — **declared in the host flake, which is an
  external repo**; this slice carries the interface and documents the unit change, it does
  not edit `~/flakes`.
- A reader for the disagreement corpus. **The slice's own writer must satisfy the invariant
  it is chasing** — an oracle whose decisions nobody reads would be the fourth instance of
  the bug.

## Out of scope

- **Any scheduler that starts runs.** No new clock, no spawn authority, no replacement of
  the systemd timer, no `emacsclient -e` from a prototype.
- **Scheduling authority (O5a / Q2a) and prompt exposure (O5b)** — `RFC-021` decisions. This
  slice deliberately does not answer them; it produces evidence.
- Changes to `satan-attrd`, the attribute contract, or attribute semantics.
- New schema, new migrations, or any write to `satan_memory`.
- The attribute *daemon's* own ledger (`ISS-011`/`F1`): the oracle must be able to run with
  the daemon's reasons still being dropped, and must say so in its evidence rather than
  infer around it.

## Affected surface

Coarse, to be tightened in `/design`:

- `satan/satan-tick.el` — decision path, shadow read, explanation assembly
- `satan/satan-budget.el` — read-only reuse of the daily total
- `satan/satan-trace.el` — the decision row
- `satan/satan-tools*.el` — a read-only `tick_explain` tool (if the design admits a tool)
- `dev/tick-oracle/**` — prototype oracle, its contract, its tests, its fixtures
- A test that asserts **no spawn path was added** — the negative is the point

## Risks and assumptions

- **Two clocks by accident.** The shadow call site must not acquire decision powers through
  a later "just make it act on it" edit. Mitigation: the negative test above, plus the
  decision record naming which component decided.
- **Subprocess noise.** `ISS-018` showed a per-tick subprocess can add 152,983 trace rows
  and zero useful ones. The oracle runs *before* the tick, on the timer's schedule, and must
  not be invoked from inside the spawn sequence.
- **The reader can outrun the data.** If tick decisions turn out to be *unreconstructible*
  even in principle — no artefact records the reason a tick fired or didn't — the loop is
  unfixable in place and the slice pivots to the argument for a replacement scheduler. That
  judgement is a deliverable of increment 1, not a risk to defer.
- **Attribution confound.** While `satan-attrd` drops unknown reasons (`F1`, `ISS-011`), an
  oracle that reads attributes is reading a state whose derivation is partly missing. The
  design must keep the oracle's inputs observable enough that a disagreement is explainable.
- Assumption: the tick decision is a *pure function of observables* for practical purposes.
  If it isn't, increment 2 collapses and increment 1 still ships.

## Verification / closure

- **Increment 1:** for 20 sampled ticks, `tick_explain` answers "did it fire, why not, what
  did it see, what did it cost" with no manual SQL, and at least one of those answers is
  today unavailable by any route.
- **Increment 2:** the oracle reproduces elisp's decision on recorded inputs, or states a
  reason for every disagreement, on a fixture set drawn from real bundles.
- **Increment 3:** ≥1 week of shadow records; every record names a decision, a reason and
  its evidence; disagreement rate is measured, not estimated.
- **Negative:** a test proves no run-start path was added; deleting the prototype directory
  restores prior behaviour.
- **Reader parity:** the disagreement corpus is readable by an agent (a function or tool),
  not only by `jq`; no new writable artefact without a reader in the same slice.

## Open questions for `/design`

- Does the decision record belong in the trace JSONL (cheap, already written per tick) or in
  a dedicated file (easier to read, one more writer)? Prefer the former if it satisfies the
  reader requirement.
- Is `tick_explain` a tool (model-visible, useful to SATAN for self-inspection) or an
  interactive command only? A tool makes the loop self-proposable; it also widens the tool
  surface by one.
- Does the oracle need attributes at all in increment 2, or is budget + sensor freshness +
  pool weight enough for a first comparison? Fewer inputs, more honest baseline.
- Where does the oracle's contract live so that a future spec can adopt it — the prototype
  directory, or a short contract note beside it that `IMP-067`'s SPEC-006 can absorb?

## Relations

- `IMP-063` — the tick-ledger review this slice's increment 1 implements (it proposed
  exactly this reader, read-only, no new schema).
- `IMP-064` — the tick gate, gated `after IMP-063`; this slice's evidence feeds it.
- `RFC-021` — O5a (scheduling authority) is left to it; this slice produces the data.
- `ADR-017` — the reason `emacsclient -e` is refused as the interface.
- `IMP-067` — the spec-coverage plan; a successful oracle is a candidate member of SPEC-006.
