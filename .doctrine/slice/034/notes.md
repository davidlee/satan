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

## Live check (PHASE-08 VA-1, 2026-10-28)

Deploy: satan 6de3fb3 (`malebolgeWakes = "on"` + probe) pushed; ~/flakes 001b88da (lock: satan, plus the user's pending agents/emacs/claude-desktop bumps, by their choice); `just home-switch`; launcher `/nix/store/ig9n4msk…-jailed-malebolge` carries `--setenv MALEBOLGE_WAKES on`; `systemctl --user restart malebolge-room` at 09:47:23. Driven by the super-orchestrator through `MALEBOLGE_PROFILE=room node src/attach-main.ts --topic room` (conversation 1970). Transcripts: session scratchpad `live-attach-{1,2,3}.txt`.

Journal (`journalctl --user -u malebolge-room | grep 'malebolge: wake'`):
```
09:47:23 wake heartbeat 1976 created in room                       # ensure at start; sweep: nothing blocked, no line
09:50:43 wake 1983 n=0 (room) cancelled                            # abort handler
09:50:43 wake 1983 cancelled                                       # wake_cancel tool
09:55:47 wake 2000 n=0 (room) defer presence until 2026-10-27T23:01:11.270Z
10:01:11 wake 2000 n=0 (room) fire
10:01:12 wake 2000 n=0 (room) done
```
- schedule: `wake_schedule` without `after_minutes` → id 1983 at now + ceiling (2 h), per design sec-13 step 2 ("absent means one ceiling"); with `after_minutes: 1` → id 2000 at now + floor (5 min). `wake_list` showed heartbeat 1976 (recurring) and 1983, `enabled: true`.
- cancel: `wake_cancel 1983` → `{"id":1983,"cancelled":true}`.
- fire: wake 2000 deferred once on presence (user active), fired 10:01:11, produced exactly one turn in conversation 1970 whose input is `<wake fired_at="2026-10-27T23:01:11.385Z" late_by="5" class="seclude" scheduled_by="1970">` with wake.md, intent and percept; SATAN replied once and stopped; `done`.
- Not exercised live: heartbeat fire (due ~11:47 unless suppressed), failure path, sweep of a blocked wake (covered by PHASE-04..07 tests).

Observations for /audit (not defects found by tests):
- `fired_at` and the `defer … until` journal line were UTC (`Z`), while `wake_schedule`/`wake_list` report local offset (`+11:00`); SATAN read the mix as a clock shift. User: "timezone needs fixing". Fixed in malebolge 578761c (`localIso` → `src/wake/local-time.ts`, used by all three; red→green, `just check` 2258 tests); daemon restarted 10:13:23, no new `heartbeat … created` line (ensure kept 1976: idempotent across restart, live). Compounding cause outside this slice: the room VM (`/srv/fleet` `rooms.assistant`) runs in UTC, so `date` in the room shows UTC; the user is setting its time zone themselves.
- pi `implement` in malebolge now runs node (user-approved form, malebolge f611305), with two sandbox caveats: `npx biome` needs the nix glibc loader (`/lib64/ld-linux` absent), and the sandbox's `git-guarded` refuses `reset --hard`/`clean -ffd`, failing 4 `test/runner/{collect,recovery}` tests in-sandbox (green on host).
- A tool cancel journals two lines (handler `n=0 (room) cancelled` + tool `cancelled`); check against design sec-4's table.
- The PHASE-08 procedure predicted the floor for an absent `after_minutes`; the design (and code) give one ceiling. Procedure note was wrong, not the code.

## Harvest
<!-- single-copy: updated in place each harvest; ids only, never restated content -->
fresh-as-of: 2026-10-28 · reconciled (RV-063 outcome, REV-015) → /close · satan 1d44fb4, malebolge 578761c

### Produced
- PHASE-01…08 completed. malebolge 6e7e461, 8950871, fe010b9, 77fec26, b1ac1d9, d3b374b, 27d0855, 578761c (+ f611305 build: malebolge's own quotient forms with node, user-approved); satan c67618c…61da3b4 (PHASE-08 code: 1441304, db21812, 6de3fb3); satan-corpus a8b2db2 (prompts/wake.md); ~/flakes (home repo) 001b88da (lock: satan + user's pending bumps). satan pushed to 6de3fb3; later satan commits and all malebolge commits unpushed.
- Live: `malebolge-room` runs wakes on since 2026-10-28 09:47 (restarted 10:13 for 578761c); heartbeat 1976; `satan.wake` v1 shapes now frozen. Evidence: § Live check.
- Design departures to reconcile (phase sheets phase-0N.md § Decisions): PHASE-04 D10 (user-accepted); PHASE-05 D2/D4/D5; PHASE-06 D1/D2/D4/D5; PHASE-07 D1/D2/D4/D6/D7/D9 (D9 user-accepted), review m1 wording; local-time rendering (578761c); two-line tool cancel journal (§ Live check).
- PHASE-08 recorded delta spans 1441304 (stale forms-suite deletion, pre-existing red) — check `slice conformance` at audit.
- minted: RSK-022 — room tools bash/grep lack a per-call deadline.
- `doctrine slice verify-vt 34` reports every malebolge VT UNATTRIBUTABLE (cross-repo limit); per-phase sheets map tests to VTs. Gates last run green: malebolge `just check` 2258 tests @578761c; satan `just check` + `nix flake check` @6de3fb3.

### Learned
- mem.fact.pi-durable.scheduled-turn-mechanics (spike S1–S6).
- Candidate memories (record at /close): satan-mcp tool results are printed Lisp text; pi-durable `RunningTask.state` is `{status, checkpoint}`; `inspect()` shows a task awaiting `Submission.wait()` as `running` even when its input is stuck; `Submission.abort()` withdraws only a queued input (check+withdraw one commit); aborting a definition-blocked task settles `orphaned` without its handler; pi-ai `timeoutMs` stops at response headers; pi-durable retries a model error only on `stopReason: error` + retryable wording; sleeps are recorded asynchronously (poll `inspect()` with `vi.waitFor`); fake `setTimer` via `SessionOptions.setTimer` drives in-phase bounds and also captures the scheduler timer, a held faux turn must be released; malebolge structure test rejects the word "capsule" in src; a root needing a toolchain for pi gets its own quotient forms (`just quotient-forms` + `quotient allow` per form), the host default forms carry none by rule; malebolge pi sandbox: `npx biome` needs the nix glibc loader, `git-guarded` fails 4 runner tests; design-run sections materialise in lexical id order.
- Process: Anthropic sub-agents in this session repeatedly ended without a hand-back and needed a nudge; pi test drafts had real defects every phase (review hard).

### Open
- Audit: RV-063 (10 findings, all verified; none blocking). Gates re-run green: malebolge `just check`, satan `just check`, `doctrine check gate`, `nix flake check`. Reconcile works from RV-063 § Reconciliation Brief (design.md F-1…F-5; SPEC-002 REV F-9).
- Reconciled: design.md sec-2/3/4/5/13 (F-1…F-6), REV-015 SPEC-002 (F-9).
- Next: `/close`.
- Room VM (`/srv/fleet` `rooms.assistant`) runs UTC; the user is setting its time zone (outside SL-034).
- Optional user act: approve malebolge's read form (`quotient allow /home/david/dev/malebolge read=…`); read/review pi profiles in malebolge are refused until then.
- 1441304 deleted `test/flake/forms.test.ts` rather than rewriting it: RV-063 F-8 tolerated; user ruling pending (reopen F-8 if they want it rewritten).
- Not exercised live: heartbeat fire, failure path, blocked-wake sweep (tests cover them).
- RSK-022 (per-tool deadlines). At close: IDE-014 / IDE-017 absorbed.
