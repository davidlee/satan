# POL-001: SATAN module extraction policy

> **Imported 2026-07-22** from the `.emacs.d` doctrine corpus, frozen for SATAN.
> Ids cited below resolve in that corpus unless they also exist here; `DE-`/`DR-`
> have no doctrine equivalent, and `IMPR-NNN` / `ISSUE-NNN` are pre-doctrine
> prefixes for `IMP-NNN` / `ISS-NNN`.

This is the standing test for whether a SATAN module belongs inside the Emacs
broker process or should be extracted. It is **not** a list of imminent work —
the extraction candidates it evaluates live in the backlog (IMP-006..009),
gated by the triggers below. Carve early, carve when the next round of work
would otherwise grow the wrong half — not reactively.

## Statement

For each module ask: **does it use the editor as an editor?** Editor primitives
in scope: org-mode parsing/writing, denote naming, buffer manipulation, dired,
`find-file`, `recentf`, interactive `satan-*` commands, `compile-angel` save
hooks, ert as the natural test surface, and presenting to — or taking approval
from — the human at the keeper's editor.

- **Yes** → the module earns its seat in the Emacs client (`satan/`). Editor is
  the substrate.
- **No** → it is in elisp only because the broker spawned there: an incidental
  tenant, eligible for extraction when carving becomes cheaper than hosting it.

Holding an authority item is **not** an answer to this question. Authority is
defined by protocol and assigned by ledger (ADR-017 §2–§3); which process
enforces it is a placement decision this test does not make.

This is **not** a performance test. The motivating costs are maintainability:
test-harness coupling (`emacs --batch` to run anything), language fit for
JSON/SQL work (the `json-serialize` arrays gotcha paid at every boundary),
crash-domain coupling (editor freezes are user-hostile; daemon hangs are not),
onboarding/review surface (non-lisp work readable only by lispers), and
compile-angel coupling (bigger pure-logic mass = bigger startup blast radius).
None are felt acutely today; they compound silently.

## Rationale

SATAN grew to ~43k lines of elisp inside `.emacs.d`; two halves already spawned
out (`~/dev/panopticon`, `~/dev/satan-patcher`), and SL-012 has since extracted
the remainder to its own repository (~19k lines across 64 modules). The policy
exists so that when an extraction trigger arrives, the cut has already been
argued and the answer is known — rather than re-litigating per module under
pressure.

## Scope

### Earns the seat (do not extract)

`satan.el` (package entry, interactive commands); `satan-custom.el` (the
client's configuration leaf); `satan-output.el` (dispatch into editor
surfaces); `satan-tools-org.el` + `satan-block.el` (the owned-block writer on
the keeper's org substrate); `satan-tools-{hippocampus,inbox}.el` (denote
naming, `find-file`, interactive commands); `satan-tools-{atsatan,notes}.el`
(the notes corpus as substrate); `satan-intervention-mark.el` (manual mark, a
human-approval surface); `satan-tools-docs.el`; thin shells
`satan-tools-{notify,sway,activity,agenda}.el`.

The seat is narrower than it reads. Most of these modules now touch the *files*
of the org/denote substrate rather than its Emacs APIs — after SL-012 the tree
holds almost no live `org-`/`denote`/`dired` call sites. They earn the seat
because the human's editing surface is where their output lands and where the
keeper approves it, not because they need an Emacs image to compute. That makes
several of them cheap to move later; none of them urgent.

### Extraction candidates (deferred → backlog)

Ordered by ADR-018 D4. The destination is the single daemon repository of
ADR-018 D1 — `satan-attrd` is absorbed by it, not a peer authority.

- **Precondition, not an extraction** — collapse the `satan-run.el` /
  `satan-broker.el` run-context duplication to one owner (ADR-018 D4.1). Same
  language, low risk; it rehearses the single-owner discipline before any
  authority item migrates.
- **First authority item — policy + tool registry.** `satan-mode.el`'s
  mode/tool/capability/budget table and `satan-tools.el`'s registry, validation
  and schema emission, owned by the core and published read-only to every
  surface (ADR-018 D2). Pure data plus pure functions; the first entry in the
  ADR-017 §3 ledger.
- **IMP-006** patch runner → `satan-patcher` (pivot-pending, in flight).
- **IMP-007** memory substrate → `satan-memoryd` (biggest editor-mismatch).
- **IMP-008** audit verifier → `satan-audit` CLI (mechanical, CI-useful).
- **IMP-009** observer → daemon, folds into IMP-007 or stands alone.
- **Last — run execution.** `satan-broker.el`'s spawn / filter / sentinel /
  finalize / budget / failure-announce (ADR-018 D4.4). Largest, best-tested,
  least architecturally contested; moving it is a quality win, not a boundary
  fix. Gated on ADR-018 OQ-1.

### Anti-candidates (explicit do-not-touch)

Sensor-alerts / cooldown / quiet-hours state (tiny single-file JSON); memory
canonicalizer alone without store+evidence (half-extraction is worse than
none); doc chunk indexer (until ~500 chunks); hippocampus indexer (until a tool
wants semantic recall).

Half-extraction is the recurring hazard here: a migrated item enforced in two
places, or in neither, is worse than either end-state (ADR-017 negative
consequence 3). Every candidate above lands as a cutover, never as an addition.

## Verification

Trigger a candidate's extraction when **one** applies, not before:

1. The candidate's surface area is about to grow materially in the next refactor
   theme (carving before growth is cheaper than after).
2. A recurring bug traces to language/runtime fit (JSON walking, subprocess
   hang, ert-only test reach).
3. A contributor/reviewer is asked to read elisp to evaluate non-elisp work.
4. The candidate's tests begin to dominate `emacs --batch` CI cost.

Absent any trigger, leave it.

### Standing principles

- Carve early, not reactively.
- **Rust is the target language for SATAN-orbit daemons** (PG + LISTEN/NOTIFY +
  RPC + invariant-heavy dispatchers + replay determinism; `sqlx` compile-time
  query checking). bough is the in-orbit precedent; its scaffolding is the
  cheapest start. `satan-patcher` being Go is incidental; panopticon being
  Python is workload fit and stands.
- **The trust boundary is a protocol, not a process** (ADR-017 §2). Safety is
  defined by invariants every surface must satisfy — schema-validated actions,
  mode/tool allowlists, append-only audit, token ceilings, kill switches — and
  each authority item has exactly one owner at a time, recorded in the ADR-017
  §3 ledger. A daemon must hold its own ceilings with the Emacs client absent;
  it never falls open. Emacs keeps the human approval surfaces permanently.
- **One binary per extraction; workspace consolidation is fine.** Shared types
  in a `satan-core` crate; processes and disable switches stay separate.
- **Preserve test corpora across the port** — ert becomes acceptance fixtures.
- **Disable switch on every extraction** (cf. `satan-patch-runner-enabled`).

## Amendments

**2026-07-22 — the seat lists, on acceptance of ADR-017 + ADR-018.** The test
is unchanged; its pre-computed answers were not survivable.

1. **"The broker IS the trust boundary" is withdrawn as a seat rationale.**
   ADR-017 §2 makes the trust boundary a protocol property. Holding authority
   no longer answers "does it use the editor as an editor?" — so
   `satan-broker.el`, `satan-mode.el` and `satan-tools.el` lose their seats,
   and `mode/tool/capability dispatch` stops being an anti-candidate. It is now
   the *first* named candidate (ADR-018 D2/D4.2).
2. **Seats retargeted to post-extraction module names and to what SL-012
   actually left behind.** The `dl-satan-*` prefix is gone; so are nearly all
   org/denote/dired call sites. `satan-{tick,budget}.el` lose their seats:
   ADR-002 moves the arrival clock daemon-side and ADR-018 D2 makes budgets
   core-owned policy. `satan-context.el` loses its seat — bundle assembly is
   file reads, not org parsing.
3. **`satan-tools-bough.el` dropped from anti-candidates.** SL-002 removes the
   integration; the question is moot, not deferred.
4. **Candidate list gains ADR-018 D4's ordering** and the D1 statement that
   `satan-attrd` is absorbed by the daemon repository rather than standing
   beside it.

The motivating costs (§Statement), the triggers (§Verification) and the
carve-early principle are untouched.

## References

- ADR-017 — Emacs is a client; the trust boundary is a protocol. Supplies the
  destination this policy's test lacked, and overturns the seat rationale
  amended above.
- ADR-018 — daemon topology and control-plane transport. Supplies the order
  (D4) and the single-repository shape (D1); re-homes this policy (D6).
- ADR-002 — metabolic arrival gating (moves the clock daemon-side).
- `docs/refactor/extraction-policy.md` — original living doc (now a pointer to
  this policy).
- `docs/refactor/plan.md` — active refactor themes.
- `docs/governance.md` — DNA thesis; Open Thread 12 (patcher).
- `docs/attributes/design-contract.md` — attribute daemon contract.
- Backlog: IMP-003 (attrd capsule), IMP-006..009 (candidates).
