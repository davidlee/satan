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

## Execution log (pi capsule run, 2026-10-21)

Shape: Claude orchestrator (host) → per phase jailed pi planner → pi worker →
host gate → commit → pi reviewer → RV-056. Prompts/helper in the untracked
`.capsule-runs/` (excluded via `.git/info/exclude`). All pi on
`llm-gateway/deepseek-flash`.

Gate deviations (environmental, not slice work):
- biome's glibc binary cannot run in the jail (no `/lib64` loader); workers skip
  it, the orchestrator runs `npx biome format --write` on the host.
- malebolge's untracked `_pi/` breaks `eslint .` (project-service parse
  errors); gate runs with `--ignore-pattern '_pi/**' --ignore-pattern
  '.agents/**'`. Base `889551d` otherwise green (lint, tsc, vitest, 98.5 %).
- `test/runner/*` has known jail-only failures; the host gate is authoritative.

| phase | malebolge | review | notes |
|---|---|---|---|
| PHASE-01 | 71f1bed | clean | planner/worker/reviewer ≈ $0.15 total |
| PHASE-02 | 48af103 | clean | ≈ $0.22 |
| PHASE-03 | 2aac756, b2c37cf | RV-056 F-1 nit, fixed | ≈ $0.22; facts: an absent pi section writes no `pi.system` entry (`[]`, not `[{}]`); `configure` emits `agent_changed`, never a `pi.system` patch |
| PHASE-04 | 2f84bce, cf5e304 | RV-056 F-2 minor, F-3/F-5 nits fixed; F-4 tolerated | ≈ $0.45; first worker run killed by the 10-min tool cap, resumed from its session. VA-1: sec-3 read recorded in the worker hand-back; the failed-attach `ended` marker is sec-3 :105's "marks the connection closed", while :106's "no closing flag" is about the departure check |
| PHASE-08 | 7f0086c, 4232538 | RV-056 F-6/F-7 nits fixed; F-8 recorded here | ≈ $0.25; no src change. V-15 tests green on arrival; red proven by deleting the `bind` destroyed branch (`src/daemon.ts:129-134`): both V-15 tests time out on a never-closed stream. EX-4: V-11 covers pre-ready departure, V-15 mid-bind, so the removed `:185-197` property is covered in both states |
| PHASE-05 | 7d2f856, 51bfff3 | RV-056 F-9/F-10 minors fixed, F-11 nit tolerated | ≈ $0.25; review first died on gateway 402, resumed after top-up. A is now a created conversation (root B runs while A is held); abort receipt via a recording `Conversations` seam passed to `serve`. Red: aborting root instead of the bound conversation hangs the receipt. A's abort is witnessed by `tx.submissionByRequest` → `unanswered`/`aborted`; `scanSubmissions` is not public in pi-durable 1.3.0 |
| PHASE-06 | fe935ed, 67831a0 | RV-056 F-12 major, F-13 minor, F-14..16 nits fixed | ≈ $0.25. Deviation from EX-7's literal text (orchestrator): the daemon-close test waits for `[attached to conversation N]`, since a close before `attached` now rejects NOT_ATTACHED (EX-4). Chosen texts: bare close `[the daemon closed before attach completed]`; skew prints the raw error, then the hint |
| PHASE-07 | 7cc688a, 11af256 | RV-056 F-17..F-20 minors, F-21..F-23 nits fixed | ≈ $0.25. Docs review swept stale singulars and a pre-SL-030 false claim (README said SL-026's layer was unimplemented). V-12: `git diff 889551d -- test/structure.test.ts src/room src/runner` empty |

Run total ≈ $2.2 of pi; RV-056 concluded (23 findings: 21 fixed, F-4/F-11 tolerated).
Host gate at 11af256: 1756 tests, 98.29 % lines.

**Open — for audit.** malebolge's untracked `_pi/` (present at session start,
2026-10-21 ~09:30) is gone and not found under `~/dev`. No pi transcript has a
command that touches it (only `--ignore-pattern '_pi/**'`); cause unknown — not
attributed. `.agents/` and the modified `AGENTS.md`/`flake.*` are intact.

## Audit RV-057 (2026-10-21)

Conformance audit, self-run. Two pi-research lanes (design conformance; Done/EX/VT test mapping), ≈ deepseek-flash, medium thinking; one jailed pi repair worker via `.capsule-runs/run-pi.sh` (label `audit-repair`, $0.07). 12 findings, all verified: 4 fix-now (malebolge `8fa162c`: passive-client test, created-conversation tool cwd test, V-1 refused shapes through the daemon, vacuous render test dropped, internals/README wording), 6 design-wrong → brief, 2 tolerated (F-10 cross-repo conformance blind; F-11 `_pi/` loss). Host gate at `8fa162c`: 1765 tests, 98.29 % lines.

- The `_pi/` open item above is closed as RV-057 F-11: unrecoverable, unattributed, surfaced to the user.
- Lesson: a design "replaced, not deleted" claim for a removed test needs the replacement to assert the same property — V-13 kept only half of `:174-183` (F-1).
- Lesson: the pi lanes earn their keep on negative findings ("no test for X") when the prompt demands a positive control for each.

## Harvest
<!-- single-copy: updated in place each harvest; ids only, never restated content -->
fresh-as-of: 2026-10-21 · close · 009d697

### Produced
- PHASE-01..08 — conversation threaded through malebolge's daemon, protocol, attach and cwd seams (malebolge 71f1bed..11af256); audit repairs 8fa162c; docs 54b0393
- no backlog minted: follow-up work is already captured below

### Learned
- mem.pattern.doctrine.pi-tiered-capsule-execution — run shape, outcome and RV-057 audit lessons (body repaired: the include line had not expanded)

### Open
- ISS-053 — SPEC-002 Transports lacks the malebolge client-socket row
- ISS-055 — older daemon rejects a newer client with an opaque protocol error
- malebolge RFC-002 — conversation organisation policy (topics, index, titles), deliberately undecided here
