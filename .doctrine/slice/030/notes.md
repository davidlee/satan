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

## Plan review RV-052 (2026-10-21)

Seven rounds (pi-research ×5, pi-scout ×2; raw in a session scratchpad, not kept): 24 → 10 → 8 → 4 → 5 → 5 → 1 findings, F-1..F-57, all fix-now and verified; concluded. Design-level findings amended sec-4/6/7 (run regressed to reviewing, adopted, re-locked rev 52 on user acceptance; RV-054 disposed conducted on RV-052's basis).

Durable lessons (also in plan.toml criteria):
- malebolge lint forbids every type assertion — the wire id narrows through `isConversationKey` (user's choice over a suppression or a scan).
- `exactOptionalPropertyTypes` shapes optionals: `ConversationDefaults` requires `cwd`; options objects carry only defined members.
- One macrotask does not guarantee a unix-socket server has read the hang-up (reviewer measured ~7/400 misses). Departure tests observe the server-side socket's `close` via a `serveUnix` recorder mocked in `test/daemon.test.ts` instead.
- Negative assertions (no stream / nothing created / nothing submitted) need a control connection and a receipt guarantee, or they pass vacuously.
- `attach-main.ts` runs at import, outside coverage — testable logic belongs in `attach.ts`.

## Harvest
<!-- single-copy: updated in place each harvest; ids only, never restated content -->
fresh-as-of: 2026-10-21 · ready (design re-locked rev 52; plan reviewed; phases materialised; none started) · 5e55f00

### Produced
- scope authored (173f682), re-aligned to the decisions at inquiry and review; research round + architecture supplement (`research/`, gitignored)
- malebolge RFC-002 — topics/conversations policy deliberation (malebolge c082433)
- minted: ISS-053 — SPEC-002 transport row missing for the interactive daemon socket
- design.md locked (7 sections); amended by plan review, re-locked rev 52
- decisions: DEC-104..DEC-109 (DEC-108, DEC-109 amended 2026-10-21); ASM-007
- RV-051 — design review, 28 findings verified, concluded
- plan.toml / plan.md — 8 phases (order 01,02,03,04,08,05,06,07); runtime sheets materialised
- RV-052 — plan review, 57 findings verified, concluded; RV-054 — design-amendment pass, concluded (basis RV-052)

### Learned
- mem.fact.pi-durable.agent-defaults-and-ids — no default model; root({agent}) ignored on an existing root; ConversationId has no parser; configure merges per key; resume() is scheduler-wide
- user direction: keep cwd an opaque string, no path semantics (DEC-107)
- user direction: wire id narrowed by type predicate, never assertion (design sec-4, 2026-10-21)
- notes § Plan review RV-052 — lint/tsconfig constraints, unix-socket close timing, negative-assertion controls

### Open
- inq-7 follow-through (reconcile): malebolge RFC-002 table + wire sketch; ISS-053 note; REQ-004/REQ-010 deferral cited; ADR-017 §3 ledger untouched
- PHASE-04 VA-1: implementation-time read of sec-3 against the daemon.ts rewrite (the RV-051 probe, now a criterion)
