# Notes SL-030: malebolge daemon: many conversations — thread the conversation through the interactive daemon

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## Inquiry review (GPT, 2026-10-21) — dispositions

Source: `/tmp/sl-030-inquiry-review.md` (informal, no RV). All points integrated, none contested.

- F-1 (overlap verification): scope done-criteria now require overlapping conversations; faux factory steps see the transcript (pi-ai 1.3.0 `faux.js:349-351` ✓).
- F-2 (attach combinations): DEC-108 amended — operation table, unknown-key refusal, second attach errors without rebind, create/ack gap accepted, client holds lines until `attached`.
- Drafting obligations for design.md: one line splitter across prelude and commands; buffer lines while selection pending; stop after a failed attach; stop a watcher acquired after disconnect; headers/README say "non-root" where DEC-104 excepts root.
- Compatibility criterion narrowed to legacy clients whose first line is a command.

## Design review RV-051 — adversarial lane (2026-10-21)

Four rounds (pi-research ×3, pi-scout ×1; raw: `research/raw/rv051-round{1,2,3}.md`). 28 findings (F-1..F-28), all fix-now and verified. The blockers were F-1 (Conversations could not produce an event stream → `Conversations.watch`) and F-15 (departure rule vs attach turn → the check is a turn's first step; a started attach completes).

**A further pass would probe:** an implementation-time read of sec-3 against the actual `daemon.ts` rewrite (turn queue, departure check, bind), since the lifecycle took three rounds to state consistently; and V-4/V-15's barrier mechanics against the `vi.mock` spy once written. No further design-time pass is needed: round 4 found only wording nits, folded in.

## Harvest
<!-- single-copy: updated in place each harvest; ids only, never restated content -->
fresh-as-of: 2026-10-21 · plan (design locked, run dr-01a15954 rev 42; no plan yet) · HEAD at commit below

### Produced
- scope authored (173f682), re-aligned to the decisions at inquiry and review; research round + architecture supplement (`research/`, gitignored)
- malebolge RFC-002 — topics/conversations policy deliberation (malebolge c082433)
- minted: ISS-053 — SPEC-002 transport row missing for the interactive daemon socket
- design.md locked (7 sections; adversarial-then-human review)
- decisions: DEC-104 (model creation default), DEC-105 (id lookup), DEC-106 (room faults per daemon), DEC-107 (cwd opaque string), DEC-108 (attach first frame; amended 2026-10-21), DEC-109 (conversations.ts; amended 2026-10-21, watch); ASM-007 (socket is attach authority)
- RV-051 — design review ledger, 28 findings verified, pass conducted

### Learned
- mem.fact.pi-durable.agent-defaults-and-ids — no default model; root({agent}) ignored on an existing root; ConversationId has no parser; configure merges per key; resume() is scheduler-wide
- user direction: keep cwd an opaque string, no path semantics (DEC-107)

### Open
- inq-7 follow-through (reconcile): malebolge RFC-002 table + wire sketch; ISS-053 note; REQ-004/REQ-010 deferral cited; ADR-017 §3 ledger untouched
- further review probe at implementation: sec-3 lifecycle vs the daemon.ts rewrite; V-4/V-15 barrier mechanics (notes § Design review RV-051)
