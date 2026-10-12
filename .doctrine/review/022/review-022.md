# Review RV-022 — reconciliation of SL-021

Adversarial-review ledger. Structured findings live in the sister
ledger toml; this prose companion carries the reviewer's framing.

## Brief

Mode: **conformance** (post-implementation, self-audit). Surface reviewed:
the primary checkout on `main` (capsule-driven, no dispatch candidate) —
commits 87a9757, 45297dd, 0a35c36, b0471ff; out-of-repo touches
`~/satan-corpus` c07ead9 (PHASE-05) and `~/.config/emacs`
`lisp/dl-sleipnir-doctor.el` (PHASE-03 EX-6).

Lines of attack:

- **ADR-001 class-A invariant** — `:current_window` and activity `current`
  are a function of the durable desktop series at a given instant; nothing
  reads `current/desktop.json` or judges freshness by mtime/wall clock.
- **Design DEC-034..DEC-040** — reader contract (`satan-desktop-at` →
  `(STATUS . WINDOW)`, two-day backward walk), status vocabulary
  (ok / disconnected / missing / malformed), alert-cause vocabulary,
  `since` semantics, landing order.
- **Plan criteria** — every EX/VT of PHASE-01..05 has evidence; VA/VH
  criteria have an agent/human act behind them.
- **Residue** — removed symbols (stale defcustom, mtime probe,
  `panopticon_current_stale`, `current/desktop.json`) absent from code,
  tests, docs, corpus.
- **Test hygiene** — fixtures zone-pinned, synthetic, independent of prod
  data and the corpus (public repo).
- **Design truth** — design prose still describes what shipped.

Evidence baseline: `doctrine slice conformance SL-021` — 17 conformant,
0 undeclared, 0 undelivered. `doctrine check gate` / `just check` with test
Postgres up — 1356/1362, 6 standing skips (real-pi / integration gated).

## Synthesis

SL-021 delivered what its design locked. `:current_window` (evidence),
the sensor-alert causes and `activity_read`'s `current` scope are now a
function of the durable desktop series at an instant (ADR-001 class A):
`satan-desktop-at ROOT TIME` replays `raw/desktop-<date>.jsonl` backwards
over at most two local days and returns `(STATUS . WINDOW)` with
`ok | disconnected | missing | malformed`. No consumer reads
`current/desktop.json` or judges freshness by mtime; the closure grep is
empty across `satan/` and `~/.config/emacs`. Path conformance is exact
(17/17, nothing undeclared or undelivered), the full suite passes with the
test database up (1356/1362, six standing environment-gated skips), and
the deployed package behaves as specified in the live Emacs: the reader
returns `ok` with `:since`, `activity_read current` returns
`:scope/:status/:window` without `:path`, and the sleipnir doctor reports
`current=ok`.

No finding blocks. The material ones are truth-maintenance:

- **Prose lags code** (F-1, F-2, F-6, F-7). Repo docs, three design
  passages and DEC-037's rationale still describe the superseded model or
  overstate an invariant. Reconcile rewrites them (brief below).
- **Plan criteria that aged** (F-3). `~/.emacs.d` vanished mid-slice and
  the corpus `just commit` recipe is unsafe on a dirty corpus. Both were
  followed in intent; plan ids are immutable, so the deviations are
  tolerated and recorded, not rewritten.
- **Model-facing wording** (F-4) implied `since` was focus duration; fixed
  in the corpus (25bc25f) during audit.

Standing risks and accepted tradeoffs:

- The VT-7 pin lines are sanitised (umbriel) and derived (niri), not
  captured: the pin test guards the reader against the documented shape,
  not against a live producer drift. Capture real niri lines when the logs
  allow.
- `malformed` can become `missing` when later lines are appended (F-6):
  accepted — both are non-`ok` with no window, and the decision itself is
  append-stable.
- The suite is host-zone dependent outside SL-021's own tests (F-9,
  ISS-036); SL-021 did not make it worse, and its new tests pin the zone.
- Host literals remain in the focus/browser alert hints (F-8, IMP-031).

## Reconciliation Brief

### Per-slice (direct edit)

- **design.md §3** (F-2a, F-10): replace "no remaining caller" with the
  sleipnir doctor as the one external caller of the removed evidence
  symbols, corrected under PHASE-03 EX-6 (user ruling 2026-09-26) in
  `~/.config/emacs/lisp/dl-sleipnir-doctor.el`, including the defensive
  `(fboundp 'satan-desktop-at)` guard in `--sensors-available-p`.
- **design.md §5** (F-2b): the VT-7 pin test uses sanitised umbriel lines
  and niri lines derived from the documented `window_focus` shape (live
  niri logs had rotated out) — not lines copied verbatim.
- **design.md §5** (F-2e): the fixture module's surface is `-write`,
  `-focus`, `-append`, `-with-root`, `-zone` (plus the originally listed
  helpers).
- **design.md §2** (F-6): qualify the append invariant — the decision
  (`ok`/`disconnected` and the window) never changes when events after T
  are appended; `malformed` may become `missing`.
- **notes.md** (F-3, F-5): record the tolerated plan deviations (EX-6/VA-1
  ran against `~/.config/emacs`; EX-2 committed one file, not
  `just commit`) and the VA-2 / VH-1 evidence (live doctor `current=ok`;
  daemon restarted before PHASE-05; corpus c07ead9 + 25bc25f).
- **Repo docs** (F-1) — edits in this repo, extending notes.md's
  "Documents reconcile will touch":
  - `docs/governance.md:528` tool-table row and `:814` open thread 10;
  - `docs/data-collection.md:150, 458, 530, 660`;
  - `docs/memory/design.md:277, 425` (with the evidence-input rows already
    listed);
  - `docs/perceptual-design.md:454, 492-494, 573` (with §S6 already
    listed).

### Governance/spec (REV)

- **ADR-001 Amendment §2** — dated amendment recording that
  `:current_window` is now class A (already listed in notes.md; unchanged
  by this audit).
- **DEC-037** (F-7) — rationale: the orphaned `panopticon_current_stale`
  cooldown entry is pruned on next read (design §3, RV-021 F-13), not
  "harmless". Knowledge edit
  (`doctrine knowledge edit decision DEC-037 …`).
- **IMP-013** body — move 2 delivered by SL-021 (already listed).

### Housekeeping

- `doctrine slice research 21 --restamp` — drift is only plan.md/plan.toml
  added after the stamp.
