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
`find-file`, `recentf`, interactive `my/satan-*` commands, `compile-angel` save
hooks, ert as the natural test surface, broker authority over user-visible
surfaces.

- **Yes** → the module earns its seat in `.emacs.d/`. Editor is the substrate.
- **No** → it is in elisp only because the broker spawned there: an incidental
  tenant, eligible for extraction when carving becomes cheaper than hosting it.

This is **not** a performance test. The motivating costs are maintainability:
test-harness coupling (`emacs --batch` to run anything), language fit for
JSON/SQL work (the `json-serialize` arrays gotcha paid at every boundary),
crash-domain coupling (editor freezes are user-hostile; daemon hangs are not),
onboarding/review surface (non-lisp work readable only by lispers), and
compile-angel coupling (bigger pure-logic mass = bigger startup blast radius).
None are felt acutely today; they compound silently.

## Rationale

SATAN grew to ~43k lines of elisp; two halves already spawned out
(`~/dev/panopticon`, `~/dev/satan-patcher`). The policy exists so that when an
extraction trigger arrives, the cut has already been argued and the answer is
known — rather than re-litigating per module under pressure.

## Scope

### Earns the seat (do not extract)

`dl-satan-broker.el` / `dl-satan.el` / `dl-satan-mode.el` / `dl-satan-tools.el`
(the broker IS the trust boundary); `dl-satan-tools-org.el`, `dl-satan-block.el`
(owned-block writer, org parsing); `dl-satan-tools-{hippocampus,inbox}.el`
(denote, dired, `my/satan-*`); `dl-satan-tools-{atsatan,notes}.el` (headline
parsing); `dl-satan-context.el` (bundle assembly over org files);
`dl-satan-{tick,budget,output}.el` (schedule + ceiling + dispatch into editor
surfaces); `dl-satan-tools-docs.el`; thin shells
`dl-satan-tools-{notify,sway,activity,agenda,bough}.el`.

### Extraction candidates (deferred → backlog)

- **Active beachhead — `satan-attrd`** (attribute layer, first Rust daemon).
  In flight; capsule render = IMP-003.
- **IMP-006** patch runner → `satan-patcher` (pivot-pending, in flight).
- **IMP-007** memory substrate → `satan-memoryd` (biggest editor-mismatch).
- **IMP-008** audit verifier → `satan-audit` CLI (mechanical, CI-useful).
- **IMP-009** observer → daemon, folds into IMP-007 or stands alone.

### Anti-candidates (explicit do-not-touch)

`dl-satan-tools-bough.el` (real fix is `bough serve` upstream); sensor-alerts /
cooldown / quiet-hours state (tiny single-file JSON); mode/tool/capability
dispatch (trust boundary); memory canonicalizer alone without store+evidence
(half-extraction is worse than none); doc chunk indexer (until ~500 chunks);
hippocampus indexer (until a tool wants semantic recall).

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
- **Trust boundary stays in Emacs.** Daemons are dumb transports + pure
  transforms; authority over user-visible surfaces stays in the broker.
- **One binary per extraction; workspace consolidation is fine.** Shared types
  in a `satan-core` crate; processes and disable switches stay separate.
- **Preserve test corpora across the port** — ert becomes acceptance fixtures.
- **Disable switch on every extraction** (cf. `dl-satan-patch-runner-enabled`).

## References

- `docs/satan/refactor/extraction-policy.md` — original living doc (now a
  pointer to this policy).
- `docs/satan/refactor/plan.md` — active refactor themes.
- `docs/satan/governance.md` — broker trust boundary; Open Thread 12 (patcher).
- `docs/satan/attributes/design-contract.md` — attribute daemon contract.
- Backlog: IMP-003 (attrd capsule), IMP-006..009 (candidates).
