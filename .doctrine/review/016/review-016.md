# Review RV-016 — code-review of SL-016

Adversarial-review ledger (ADR-007). Structured findings live in the sister
ledger toml; this prose companion carries the reviewer's framing.

## Brief

Subject: the SL-016 implementation delta (`d036427`..`a6ebf37`; 11/12 phases
code-complete, PHASE-08 part B is the host rollout). Mechanised depth: full
process — a three-repo, ~1.7k-line elisp/DB/corpus change carrying the slice's
load-bearing classification signal.

Lines of attack, pinned to the design's own invariants:

1. **The keystone signal must not lie.** Design sec-5/RV-007 F-1: a delivery
   failure is never recorded as the keeper's silence. Read each verdict row
   (`undelivered`/`short_exposure`/`deferred`/`dismissed`/`untouched`) and its
   input against the goad day record — where does the observer get the record
   from, and can a wrong verdict arise from bookkeeping rather than fact?
2. **The record route must survive its own lifecycle.** sec-2: the observer
   "takes the emit date from the intervention"; the evidence source is
   queue-derived. Probe the seam between the disposable queue projection
   (`satan-goad-queue-rewrite` = *open* asks only) and maturity.
3. **Attribution.** sec-10/RV-007 F-28: an ask credits the emit-time motive,
   never a re-rank; a motive cued on `app:goad` cannot absorb it. Probe
   `--ask-motive`, `--winner`, and the goad-minted subject refusal.
4. **DEC-024/026/028.** form_json conditional INSERT (projects before 0008),
   one-shot validation at emit, JSON row reads that cannot split on `|`/newline,
   and the open-asks query's boundary as pending's complement.
5. **ADR-001 purity.** The `:goad` slice in the perceive leg writes nothing;
   `cue_only` skips it; no reader signals on absent/malformed input.
6. **Conceptual precision / DRY.** Two closed reason sets, duplicated instant
   parsing (`date-to-time` vs the design-mandated strict parser), size caps
   enforced late.

Verification basis: `SATAN_DB_HOST=127.0.0.1 just check` → 1286 ran, 0
unexpected, 6 skipped (integration tests counted, not skipped); fixtures are
`backend.py`'s own bytes; byte-compile of the eleven touched files yields no
new warnings. Claims below checked against code and execution, not recollection.

## Synthesis

**Overall: acceptable.** Eleven of twelve phases land a coherent, unusually
test-honest implementation of a hard design; one real robustness defect was
found and fixed in place.

### The closure story

SL-016 turns goad into SATAN's elicitation surface across three repos: a
tested `backend.py` record and queue (corpus), an elisp perceive leg
(`satan-goad.el`, `:goad` evidence, the `goad.outstanding` canon rule), the
`goad_ask` tool with a one-shot form validator, JSON intervention reads with
an open-asks query, and an ask-scoped observer route. The delta is faithful to
the design's load-bearing decisions: the correlation gate ranks only motives
cuing the perceived subject (`satan-tools-goad--winner`), never re-ranks by
percept overlap, and refuses goad-minted subjects; the emit-time motive is read
back at maturity (`satan-observer--ask-motive`); the ask is exempt from
`crosses_midnight`; option ids carry identity; the record is judged as it stood
at window end; `form_json` is named only for a payload carrying a form, so
every other kind projects before migration `0008`; and every reader goes
through `json_agg(row_to_json(…))`, so a `|` or a newline cannot split a row.

**The one defect worth raising (F-1).** The answer predicate and the negative
branch obtained the day record only from the queue-derived `:goad` slice. The
queue is a projection of *open* asks, so an ask whose window closed during a
spawn could be retired by the same spawn's ask-handler rewrite before the
observer scored it — and then mature `:unknown :high undelivered' whether or
not the keeper was presented and answered. That inverts the one signal the
slice exists to produce, and it is the exact class the design's F-1 lesson
forbids (never record a delivery failure where delivery happened). Fixed at
`satan-observer--ask-record`: the slice read stays first, with a fallback to the
day file of the ask's own emit date — the read `--persist-positive` already
used. A regression test drives the goldens with an empty `:goad` slice.

### What was done well (no raise — praise belongs here, not the ledger)

- **Tests pin to the producer, not to hand-built values.** The fixtures are
  `backend.py`'s own bytes (READ ME provenance table + the VT-43 re-derivation);
  the refusal tests spy on every side-effecting function to prove nothing ran;
  purity is proven with `ert-fail` spies over the mutating set (ADR-001).
- **The hard design mechanics are implemented literally and legibly** — the
  five-row verdict table, the ack-gate bypass, the emit-date/instant discipline
  (`satan-memory-canon-parse-instant`, not a substring), the DEC-024 conditional
  INSERT, and the open-asks boundary as `pending`'s exact complement.
- **DRY at the seams that matter:** the ranking rule was promoted to
  `satan-motive-rank-by-overlap` and both callers alias it; the atomic write was
  promoted to `satan-jsonl-write-file-atomic`; the undelivered writer moved to
  `satan-intervention` and notify now calls the shared one; the state home is
  one helper (DEC-027).

### Standing risks and observations (not raised)

- **`satan-goad.el` carries both the pure read side and the DB-writing queue
  projection.** The design names the module for both, but the file header's
  "read side stays dependency-light" is false transitively: `satan-memory-evidence`
  → `satan-goad` → `satan-intervention` → `satan-memory-migrate`/`satan-attribute`/
  `satan-memory-store`. The percept builder therefore loads the whole intervention/DB
  graph. Design-sanctioned, worth splitting if the read side is ever extracted
  (POL-001 No-branch tenant), not worth a raise against this delta.
- **Two instant parsers in the observer.** The ask path uses lenient
  `date-to-time`; the slice/design mandate the strict `satan-memory-canon-parse-instant`,
  precisely because `date-to-time` silently drops the time of day on a
  space-separated psql cell (R1). Correct today only because
  `--projection-to-classifier-plist` normalises `:ts` upstream; the ask helpers
  carry no comment or guard for that dependency. A nit, not raised.
- **The 8 KiB form cap is enforced after the form is rebuilt**
  (`satan-goad-form--serialised-bytes` runs on the constructed form). Bounded in
  practice by the MCP transport; a raw-size pre-check would harden it. A nit,
  not raised.
- **PHASE-08 part B is untouched** — attrd is undeployed, `0008` is test-DB only,
  and `satan-goad-enabled` is nil. The review covers the code that will run; the
  live loop (VH-1/VH-2) remains unproven.

### Haiku

The doorbell rings in
files the keeper never reads—
silence now has shape.

