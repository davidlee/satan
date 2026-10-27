# Notes SL-034: malebolge wakeups: SATAN schedules its own turns in the room daemon

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## Design triage (2026-10-27, exploring)

Evidence: `research/research.md` (G = governance rows, C = cross-thread, S = spike).

**User rulings (2026-10-27):** no spend/rate limits in v0; wake turns share
`interactive`'s tool allowlist, kind `scheduled` is audit attribution only; a
wake off switch is in scope; ledger rows, owner token and a no-limits decision
record are written in this slice. Quiet hours: the ~23:20–07:00 suspend window
is off limits for large jobs. Two episode classes with opposite presence rules:
observation/intervention vs seclusion/self-work.

**Design theme (user, 2026-10-27): cheapest, simplest approach that works.**
Not hacks — but anything not carrying its weight, or that would add a lot of
code, is deferred. Apply it to every inquiry: prefer the answer that reuses
pi-durable / existing malebolge seams and leaves a follow-up over one that
builds machinery now. (E.g. presence source, pre-compaction, a separate
allowlist, rich task_list output are all candidates to defer or keep minimal.)

**Shaping decisions carried from research:**
- Wakes are pi-durable background tasks owned by the target conversation;
  no host table, no host timer (S3–S6, C2).
- Delivery: input with `entry:{kind:"satan.wake"}` and
  `requestId:"wake:<task>"` — idempotent fire (S1, S2, C3).
- Decider: pure function at schedule time (clamp) and fire time (gate/defer).

**Constraining governance:** ADR-017 §3/§4 (one owner per duty; fail closed),
ADR-018 D2/D3 (read policy, never copy; in-process control plane), DEC-121/125
(`scheduled` kind; pool per conversation × kind), DEC-083/085 (service stop is
not a kill switch; satan-mcp off leaves room tools live), REQ-013 (one schema
owner — satisfied by using pi-durable's tables), CON-005 (room stays offline),
POL-001 (disable switch per extraction).

**Open questions:** inq-1 … inq-11 in the design run (`doctrine design show 34`).

**Risks:**
- Unattended spend with no owned ceiling (accepted v0; gateway key cap is the backstop, outside the ledger — DEC-043).
- A wake that calls no satan-mcp tool mints no satan-mcp run/audit (DEC-122/125) — the percept fetch normally mints one.
- Heartbeat races producing two pending wakes, or none.
- Startup ordering: tasks resuming before tool refresh / index backfill.

**Assumptions:**
- The room daemon is long-running (SL-028 user unit); with it down, no wakes fire.
- pi-durable 1.4.0 semantics as spiked hold for the pinned version.

## Inquiry outcomes (2026-10-27, inquiring → all 11 resolved)

| inq | Record | Gist |
|---|---|---|
| 1 | DEC-127 | `satan.wake` background task owned by target; one `fire` phase; no topic/parent snapshot (index via `contextOf`) |
| 3 | DEC-128 | async `WakePolicy` seam + injected `env` (user: wants randomness, budget, history later); weighted presence (~60/40) |
| 4 | DEC-129 | presence = satan-mcp `activity_read{scope:current}` over `scheduled` |
| 2 | DEC-130 | `wake_*` tools; target = caller or known topic's latest at schedule |
| 5 | DEC-131 | one perpetual recurring heartbeat, topic `room` |
| 7 | DEC-132 | `MALEBOLGE_WAKES=on` at start; off defers |
| 6 | DEC-133 | fire composition; `requestId wake:<task>:<at>` (heartbeat would dedupe otherwise) |
| 8 | DEC-134 | failure → journal + `notify_send` (lands in satan-tank) |
| 9 | DEC-135 | no pre-compaction (IMP-056) |
| 10 | DEC-136 | ledger token `room-daemon`, rows 7b/6d/4d; plus DEC-137 (no limits v0), DEC-138 (shared allowlist) |
| 11 | DEC-139 | daemon wiring; 5 env keys, rest code constants (narrows DEC-128) |

Runbook steps `inquire.knowledge` and `inquire.scope` discharged (rev 23–24);
scope rewritten. Outstanding before drafting: GPT sense check of the map (user
direction), then the user's `sufficiency-accepted`.

## GPT sense check (2026-10-27)

Codex `gpt-6.1-sol`, thread `01a17c9f-bea9-7882-bd5c-1f09ef8779b0`. Verdict:
approach sound; F1–F3 would-block, F4–F8 should-fix. All dispositions accepted
by the user as recommended; applied as DEC amendments (each DEC body records it).

| # | Fix | DEC |
|---|---|---|
| F1 | stable occurrence id `wake:<taskId>:<n>`; defer keeps `n` | 127, 133 |
| F2 | switch stops new admissions only; `satan-mcp-enabled` is the hard stop | 132, 136 |
| F3 | wake env set in room jail `set-env` + launcher probes (row 3b); no `~/flakes` change | 139, 132, 136 |
| F4 | pending = sleeping only; blocked/parked heartbeat recreated; `afterFailedRun` stays `keep` | 131 |
| F5 | `wake_cancel` only while sleeping, else "already fired" | 130 |
| F6 | admission-time quiet gating, documented | 128, 133 |
| F7 | tool decides `at`, stored in task input | 127 |
| F8 | journal line per gate decision + terminal outcome; journal suffices for REQ-003 | 136 |
| ASM-c | settled by source (`generation.ts:376`) | 134 |

Verified in source: F1, F3, F4, F7, ASM-c. F2, F5 plausible from the API
(`resume()` re-drives admitted work; `abortTask` does not withdraw inputs).

## Further review pass (2026-10-28, after RV-062 concluded)

None needed before lock. RV-062 ran four rounds; the last (Opus standing in
for codex) raised only two minors, both repaired and verified, against
design rev 59. What another pass would probe is implementation-bound and
is not settled by design prose: the F-13 demonstration (stream deadline
through the real adapter in a real pi-durable run, criterion as amended by
F-16), the sweep's crash windows as tests, and per-tool deadlines for
in-turn tool calls (Risks). Those land as `/plan` criteria and `/audit`.
The later route-only reopen of F-1…F-5/F-7/F-9 (routed `review`, verdicts
unchanged, re-concluded) examined nothing new and changes none of this.

## Execution log (review passes)

| phase | who / profile | cost | outcome | what went wrong |
|---|---|---|---|---|
| 01 | pi implement (tests) | $0.064, 33 req | 3 suites, red as specified | header cited wrong design refs (`§4.5; RFC-002`); fixed by hand |
| 01 | pi implement (code) | $0.048, 18 req | green after 3 hand lint fixes | could not run node: pi write form lacks node/npx, so lint/tsc issues reached me |
| 01 | pi review | $0.018, 7 req | 7 minors | F3/F7 false (host refusal ordering); DST notes accepted as doc caveat |
| 02 | Sonnet sub-agent (implement) | ~108k tokens | green first gate run | ended without handback; needed a nudge |
| 03 | pi implement (tests) | $0.041, 27 req | 4 tests drafted; red as specified (stall demo timed out — F-13 reproduced) | none material; guessed signatures listed accurately |
| 03 | Opus sub-orchestrator (code) | — | ~60-line wrapper; green after one lint fix (type assertion → non-generic helper) | — |
| 03 | pi review | $0.042, 21 req | 2 major, 4 minor, 3 nit; 6 accepted | majors 1/2 false (EventStream iteration never rejects; an inner without a result is settled by the deadline); could not find ~/.local/src/pi from its jail, read dist instead |
| 04 | pi implement (tests) | $0.139+0.005, 31+2 req | 9 tests drafted, red against a throwing skeleton | first call hit the ceiling before writing (re-prompted via session); crash-after-admission test raced the faux model (fixed: hold the first turn, wait `placed`); `checkpointOf` param type too narrow |
| 04 | Opus sub-orchestrator (code) | — | task.ts ~370 lines; green after 3 lint fixes + one doctrine-word trip (`capsule` in a comment fails the door-knowledge test) | — |
| 04 | pi review | $0.058, 30 req | 4 accepted (late_by on heartbeat n≥1, notify-catch, exact journal lines, heartbeat occurrence 1), 6 rejected | first call spent its ceiling in pi-durable dist; could not reach the satan design path from its jail |
| 05 | pi implement (tests) | $0.079, 19 req | 11 tests drafted; red for the right reasons once fixed | never released the failing foreground turn (every stuck case hung); topic added to the heartbeat-unanswered line against the sec-4 table; a ceiling loop that would pass a 3-ceiling bound (replaced with an exact armed-bound helper) |
| 05 | Opus sub-orchestrator (code + fixture refactor) | — | bounded wait + withdraw ~170 lines; green after one lint fix (switch exhaustiveness) | — |
| 05 | pi review | $0.061, 22 req | 9 findings: 6 accepted (settled-branch test, restart re-race, discriminating asserts, timer disarm), 3 rejected (crash window as PHASE-04 F5; W9-permitted overstatement; journal-in-catch as PHASE-04 F2) | — |
| 06 | pi implement (tests) | ceiling, 30 req | 12 tests drafted (611 lines); never answered (ceiling) — read the file instead | conversations without a model (`no_model`); "abort first" by moving the clock is not deterministic (any scheduling pass runs a due task); faux queue replaced inside a tool call |
| 06 | pi read (deadline recon) | $0.010, 13 req | per-tool deadline table → RSK-022 | missed pi-mcp's 30 s default request timeout (claimed satan-mcp calls unbounded) |
| 06 | Opus sub-orchestrator (code) | — | tools.ts ~210 lines; green after lint fixes (no type assertions: `isWakeInput`, `Type.Unsafe<JsonObject>`, `isConversationKey`) | — |
| 06 | pi review | $0.037, 27+1 req | 10 findings: 4 accepted (default topic, ms, no-hang pin, stub typing), 6 rejected | first call spent its ceiling in malebolge's own .doctrine; answered on a 1-request continuation |
| 07 | quotient implement + read | — | refused `form-unapproved` (new store paths for both forms; operator `quotient allow` needed — reported to main) | — |
| 07 | 2× Sonnet sub-agent (tests) | ~194k + ~131k tokens | 12 heartbeat/sweep tests + 6 daemon-start/sections tests; fixture gained `crash` and the failed-run helpers (moved from wake-wait); red against stubs | both ended without a handback and needed a nudge; created-line format wrong (`wake <id> heartbeat created`); first formatting pass by prettier instead of biome (mine — reverted format-only hunks) |
| 07 | me (code) | — | sweep.ts, heartbeat.ts, suppression, daemon wiring; green first run after the test fix | startDaemon over lint limits → 6 small extractions |
| 07 | Opus sub-agent (review) | ~135k tokens | 1 major (session leaked when the post-resume step fails), 6 minor, 2 nits; 5 accepted and fixed, m1/m6 accepted as recorded | ended without a handback; needed a nudge |
| 07 | pi implement (test fixes) | $0.082, 61 req (ceiling) | VT-1b held handler, VT-1d past due, VT-2c one-shot, VT-2g fake inspection, VT-3f; all correct on review | never answered (ceiling, spent requests on a /tmp copy for mutation checks); VT-3f did not observe the leak — I added an open-fd check |
| 08 | me (Opus sub-orchestrator), no pi | — | flake.nix `malebolgeWakes = "off"` + set-env + probes (WAKES, /etc/localtime); wake.md (corpus a8b2db2); ledger 4d/6d/7b + token + 3b evidence; docs sentences | `just check` was already red at HEAD (stale `test/flake/forms.test.ts` since 4dfd3b2): suite dropped (12ae025). Work too small to earn pi delegation |

Form constraint: the quotient `write`/`implement` form has no node, so pi cannot run malebolge's gate. Build loops are the orchestrator's or a Bash-capable sub-agent's.

## Harvest
<!-- single-copy: updated in place each harvest; ids only, never restated content -->
fresh-as-of: 2026-10-28 · plan authored, 8 phases materialised · slice status ready

### Produced
- SL-034 scope (rewritten, reconciled with RV-062), notes; research (`research/`, gitignored); design run dr-01a17c58 (locked 2026-10-28; 13 sections attested, RV-062 conducted); plan.toml/plan.md (PHASE-01…08).
- DEC-127 … DEC-139 (accepted, shape SL-034; 127/128/130–134/136/139 amended by the GPT sense check and RV-062; 127/131/134 again by RV-062 F-11/F-12/F-14); IMP-056, IMP-057, IMP-058.
- RV-062 (design review, raiser codex; Opus stood in for F-13…F-16): done, F-1…F-16 verified, concluded. F-13 routed demonstrate (its criterion clause amended by F-16's response).

### Learned
- mem.fact.pi-durable.scheduled-turn-mechanics (spike S1–S6).
- Candidate memories (not yet recorded): satan-mcp tool results are printed Lisp text (`satan-mcp.el:381`), not JSON; pi-durable `RunningTask.state` is `{status, checkpoint}`; `inspect()` reports a task awaiting `Submission.wait()` as `running` even when its input is stuck behind a failed run; design-run sections materialise in lexical id order (`sec-1`, `sec-10`, …); `Submission.abort()` withdraws only a still-queued input, check and withdraw in one commit (`harness/submissions.ts:130-143`); aborting a definition-blocked task never runs its abort handler, it settles `orphaned` (pi-durable `docs/spec.md` § blocked tasks); pi-ai `timeoutMs` on the openai-completions path stops at response headers (OpenAI SDK `fetchWithTimeout`); pi-durable retries a model error only when `stopReason` is `error` and pi-ai's wording classifier accepts it (`generation.ts:561-566`), so an aborted request is never retried. PHASE-05: `runtime.setTimer` is a foreground host timer routed through `HarnessOptions.setTimer` (malebolge `SessionOptions.setTimer`), so a fake `setTimer` on the fake clock (`fakeTimers`) drives an in-phase bound deterministically — it also captures the scheduler's earliest-sleep timer; a test that holds a faux turn on a gate must release it, or `Submission.wait()` and the harness close hang.

### Open
- Next: PHASE-08 live check (VA-1) and VH-1 — user's go-ahead needed (deploy + `malebolge-room` restart freezes `satan.wake` v1 shapes); then `/audit`. PHASE-08 EX-1…EX-5, VT-1, VA-2 done.
- PHASE-08 D1: jail sets `MALEBOLGE_WAKES` from one binding `malebolgeWakes = "off"` (flake.nix); turning wakes on (VH-1) edits that binding and the probe literal `--setenv MALEBOLGE_WAKES off ` together. D2 (EX-5): no TZ needed — jail.nix binds the host's `/etc/localtime` symlink (→ `/etc/zoneinfo/Australia/Melbourne`); Node in a replica bwrap resolves `Australia/Melbourne`, UTC without the bind; the bind is now probed. D3: other `MALEBOLGE_WAKE_*` keys unset (daemon defaults).
- PHASE-07 departures/decisions to reconcile: phase sheet D1 (`sweepBlockedWakes(deps, read, ctx)`), D2 (`tasksExtension(deps, task?)`), D9 (`MALEBOLGE_WAKE_TOPIC` must be a topic name, not `default` — narrows PHASE-01), D6 (`withdrew <k>` counts withdrawn; no failure report for an abort-marked blocked wake). Review m1: a `restart_limit` wake's handler journals "cancelled: already fired" after the sweep withdrew its input (W9-permitted; wording). m6: a failed satan.wake migration would leave no heartbeat until the next start (moot at v1).
- PHASE-07 D9 (`MALEBOLGE_WAKE_TOPIC` must be a valid topic name, not `default`; narrows PHASE-01): accepted by the user 2026-10-28 ("yes"). Reconcile with the design text at /audit.
- Live check (PHASE-08 VA-1/VH-1) authorised by the user 2026-10-28 ("yes"): `malebolgeWakes = "on"` + probe, deploy via ~/flakes, `malebolge-room` restart.
- PHASE-04 D10 (`late_by` only on occurrence 0; heartbeat occurrences n≥1 omit it; no due-time field in the fire checkpoint): accepted by the user 2026-10-28 ("1. yes"). Departs from design sec-2 text (`late_by = firedAt − input.at`) — reconcile the design text at /audit → /reconcile. Departures to reconcile likewise: PHASE-05 D2/D4/D5, PHASE-06 D1/D2 (phase sheets).
- RV-062 F-13 (demonstrate) transcribed to PHASE-03 EX-2/VT-1/VA-1 with F-16's amendment. Raiser-side transcription check done 2026-10-28 (Opus standing in for codex, super-orchestrator): EX-2 carries F-13's criterion with F-16's "exactly one model request, no retry"; malebolge fe010b9 `test/models.test.ts` asserts it through the real adapter in a real pi-durable run (`requests` toBe 1, unanswered/model_error, positive control "hello"); lands before PHASE-05 as F-13's host constraint requires. F-13 itself was already verified/terminal; no ledger act needed.
- Implementation checks carried by the design: room jail time zone (done, PHASE-08 D2); per-tool deadlines for in-turn tool calls (Risks; RSK-022).
- Candidate backlog at close: close IDE-014 / IDE-017 as absorbed.
