---
name: satan-patch-plan
description: SATAN patch-agent implementation plan — phases, file plan, migrations, acceptance gates
metadata:
  type: plan
  topic: satan-patch
  status: living
  updated_at: 03398479
  verified_at: 03398479
---

# Patch-Agent Extension — Implementation Plan

Companion to [brief.md](brief.md). Brief = what + why; this = how + sequence.

## 0. Settled decisions

| Topic | Decision | Source |
|---|---|---|
| Coding harness | `jailed-pi` primary, `jailed-zerostack` alternate via shared adapter iface | user (2026-05-20) |
| Pi mode | `pi -p --mode json --no-session` headless; RPC mode reserved for v2 | pi README §CLI |
| Jail profile | `specDev` (network, persist-home `agent`, git-push blocked, clanker git identity) | `~/flakes/pub/jailed-agents.nix` |
| Storage | New tables in `satan_memory` PG db; migration `0005_patch_jobs.sql` | user (2026-05-20) |
| Execution | Background queued; runner = elisp timer + async `make-process` | user (2026-05-20) + brief §5 |
| Scope | Phases 1–3 (substrate + harness + SATAN mode integration); phase 4 deferred | user (2026-05-20) |
| Concurrency | Single global active job (no parallel runners in v1) | brief §19 |
| Cleanup | No auto-deletion of worktrees/branches; explicit tool only | brief §15 |
| Prompt | Patch-agent system prompt lives at `~/notes/satan/patch-agent/prompt.md` | mirrors `~/notes/satan/tools/<name>.md` split |
| Allowed-paths failure | v1 = fail before commit (brief §15.2) | brief |

## 1. File plan

New elisp modules under `~/.emacs.d/satan/`:

```
satan-patch-store.el        PG CRUD against patch_jobs / patch_job_events
satan-patch-worktree.el     branch naming + git worktree add + manifest + allowlist verify
satan-patch-adapter.el      adapter protocol + selector
satan-patch-adapter-pi.el   pi adapter (jailed-pi -p --mode json)
satan-patch-prompt.el       directive → harness prompt builder
satan-patch-runner.el       async runner: claim → run → verify → commit → record
satan-patch.el              top-level: require children, register tools, schedule runner
satan-tools-patch.el        broker-facing tools: patch_job_{create,status,result,cancel,cleanup}
memory/migrations/0005_patch_jobs.sql
```

Adjacent edits:

```
satan-tools-atsatan.el      classify patch-shaped @satan directives; queue + mark queued
satan-tick.el               wire patch tools into tick allowlist (status/result read-only)
satan.el                    require satan-patch
~/notes/satan/tools/patch_job_*.md   one description file per tool
~/notes/satan/patch-agent/prompt.md  harness system prompt
```

Tests:

```
test/satan-patch-store-test.el       schema, lifecycle transitions, json roundtrips
test/satan-patch-worktree-test.el    branch naming, worktree creation, allowlist verify
test/satan-patch-adapter-test.el     fake-pi adapter contract
test/satan-patch-runner-test.el      end-to-end with fake adapter
test/satan-tools-patch-test.el       tool schema + dispatch + capability gating
test/satan-tools-atsatan-patch-test.el   classify + queue + mark queued
```

## 2. Phase 1 — Job substrate

Deliver: DB, worktree mechanics, broker tools, **no harness invocation yet**.

### 2.1 Migration `0005_patch_jobs.sql`

Schema from brief §7.1 verbatim plus a slimmer event log (audit + state transitions):

```sql
CREATE TABLE patch_jobs (
  id                 TEXT PRIMARY KEY,
  state              TEXT NOT NULL CHECK (state IN
                       ('queued','claimed','preparing_worktree','running',
                        'needs_review','failed','cancelled','accepted_external','stale')),
  mode               TEXT NOT NULL,
  directive          TEXT NOT NULL,

  repo               TEXT NOT NULL,
  base_ref           TEXT NOT NULL,
  branch             TEXT NOT NULL,
  worktree_path      TEXT NOT NULL,

  adapter            TEXT NOT NULL DEFAULT 'pi',

  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  started_at         TIMESTAMPTZ,
  finished_at        TIMESTAMPTZ,

  source_json        JSONB NOT NULL DEFAULT '{}'::jsonb,
  context_json      JSONB NOT NULL DEFAULT '{}'::jsonb,
  allowed_paths_json JSONB NOT NULL,
  checks_json        JSONB NOT NULL DEFAULT '[]'::jsonb,

  result_json        JSONB,
  error_json         JSONB
);

CREATE INDEX patch_jobs_state_idx ON patch_jobs(state);
CREATE INDEX patch_jobs_created_idx ON patch_jobs(created_at DESC);
CREATE INDEX patch_jobs_repo_branch_idx ON patch_jobs(repo, branch);

CREATE TABLE patch_job_events (
  id          BIGSERIAL PRIMARY KEY,
  job_id      TEXT NOT NULL REFERENCES patch_jobs(id) ON DELETE CASCADE,
  at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  kind        TEXT NOT NULL,     -- transition|log|warning|check
  payload     JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX patch_job_events_job_idx ON patch_job_events(job_id, at);
```

Apply to **both** `satan_memory` (prod) and `satan_memory_test` (ert). Updates `satan-memory-migrate.el` migration list.

### 2.2 `satan-patch-store.el`

Mirror `satan-memory-store.el` style. API:

```
(satan-patch-store-insert SPEC)         -> job-id
(satan-patch-store-update-state ID NEW &optional FIELDS)
(satan-patch-store-claim-next)          -> SPEC | nil   ; FOR UPDATE SKIP LOCKED on state='queued'
(satan-patch-store-get ID)              -> SPEC
(satan-patch-store-list &key STATE LIMIT) -> list
(satan-patch-store-event ID KIND PAYLOAD)
```

`claim-next` is the runner's atomic pick. Single global runner means contention is theoretical, but PG `FOR UPDATE SKIP LOCKED` future-proofs concurrent runners.

`ert`: insert+get roundtrip; state transition; claim-next atomicity; jsonb roundtrip preserves nesting.

### 2.3 `satan-patch-worktree.el`

API:

```
(satan-patch-worktree/branch-name MODE SLUG)
   -> "satan/<mode>/<YYYYMMDDTHHMMSS>-<slug>"

(satan-patch-worktree/create JOB-SPEC)
   -> (:worktree-path PATH :branch BRANCH)
   ; git -C <repo> worktree add <path> -b <branch> <base-ref>
   ; writes <path>/.satan-patch-manifest.json  (job_id + allowlist + checks)

(satan-patch-worktree/changed-files JOB-SPEC)
   -> list of paths relative to repo root
   ; git diff --name-only <base-ref>..HEAD inside worktree

(satan-patch-worktree/verify-allowlist JOB-SPEC CHANGED)
   -> ok | (error LIST-OF-OFFENDING-PATHS)

(satan-patch-worktree/cleanup JOB-SPEC &key delete-branch)
   ; git worktree remove --force; optional git branch -D
```

Root: `~/.local/state/satan/patch-agent/worktrees/<job_id>/`.

Allowlist matching: prefix match against repo-root-relative paths. Trailing `/` on entry means "this dir and below"; no trailing `/` means exact file. No globs in v1 — easy to add later.

`ert`: branch name deterministic given clock; worktree created on clean repo; allowlist accepts inside, rejects outside; cleanup is idempotent.

### 2.4 `satan-tools-patch.el`

Tools registered against broker via existing `satan-tool-register` mechanism (cf. `satan-tools.el:satan-tool-register`). Capabilities:

| Tool | Risk | Capability |
|---|---|---|
| `patch_job_create` | low | `patch-job-create` |
| `patch_job_status` | read | — |
| `patch_job_result` | read | — |
| `patch_job_cancel` | low | `patch-job-cancel` |
| `patch_job_cleanup` | medium | `patch-job-cleanup` |

`patch_job_create` validates: repo exists, allowed_paths non-empty, mode in known-modes set. Inserts row with `state='queued'`, returns `{job_id, state, branch, worktree_path}`. Worktree itself is created lazily by the runner during `preparing_worktree`.

`ert`: tool schema validates inputs; reject on bad repo path; cancel from queued → cancelled; cleanup refuses non-terminal states.

### 2.5 Phase 1 acceptance

```
- migration 0005 applied to satan_memory + satan_memory_test
- patch_job_create from elisp inserts row
- patch_job_status returns row contents
- runner stub (manual trigger) can create worktree + branch + manifest
- allowed-paths verify catches off-allowlist diffs in a hand-staged worktree
- patch_job_cleanup removes worktree (branch retained unless delete_branch=t)
- ert all green; phase-3 ert still passes
```

No real edits happen yet. Stop here, commit, smoke-test.

## 3. Phase 2 — Harness adapter + runner

Deliver: actual edits in worktree by jailed-pi, with commit + result recording.

### 3.1 Adapter protocol — `satan-patch-adapter.el`

Generic interface:

```
(satan-patch-adapter/invoke ADAPTER JOB-SPEC &key on-finish on-log)
   -> process handle
   ; runs adapter in worktree, async, with timeout & token caps
   ; on-finish: (lambda (RESULT-PLIST))
   ;   RESULT-PLIST :: (:status success|failure
   ;                    :summary STR
   ;                    :changed-files LIST   ; adapter's self-report
   ;                    :checks LIST
   ;                    :warnings LIST
   ;                    :raw-output PATH)
   ; on-log: per-line streaming hook (optional)
```

Registry: `satan-patch-adapters` alist keyed by adapter name (`pi`, `zerostack`, `fake`).

### 3.2 `satan-patch-adapter-pi.el`

Invocation shape:

```
jailed-pi \
  --provider <from config> \
  --model <from job-spec or default> \
  --mode json \
  --no-session \
  --no-context-files \
  --tools read,write,edit,bash,grep,find,ls \
  --system-prompt-file <prompt> \
  -p <directive-with-context>
```

Run with `default-directory = <worktree-path>`. `jailed-pi` already bwraps cwd to `/workspace/<basename>` via `baseJailOptions` and forwards API keys via `apiKeyPassThrough` (no `op run` needed since `passApiKeysFromEnv` reads from Emacs's env — same path SATAN broker uses today, see memory `satan-secret` pattern).

Parse the JSON event stream as it lands. Track:

- `assistant_message` deltas → log file
- `tool_call` (write/edit/bash) → tally changed-files set
- `error` → mark failure, abort
- terminal status event → resolve `on-finish`

Caps:

- max wall clock: 1800s default, overridable per job
- max tokens (cumulative): 200k default
- max turns: pi's own `max_agent_turns` (default 100) is fine
- output log capped at 8 MiB, then truncated

Stdout file: `~/.local/state/satan/patch-agent/logs/<job_id>.jsonl`.

### 3.3 Prompt builder — `satan-patch-prompt.el`

Combines:

- canonical system prompt (`~/notes/satan/patch-agent/prompt.md`) — describes role, allowlist enforcement, commit-on-success contract, must-not-push, must-emit-summary
- per-job directive
- per-job context bundle (note excerpt / memory matches / proposal id / mode_run_id)
- explicit allowlist string ("you may only edit files matching ...")
- explicit check list to run before declaring success

System prompt lives outside the repo (mirrors the `satan-tools-descriptions-dir` split — mind out, mechanism in).

### 3.4 Runner — `satan-patch-runner.el`

Single global runner. Implemented as:

```
(satan-patch-runner-tick)   ; idempotent; safe to invoke from timer or hook
   ; if a job is already running this Emacs session: no-op
   ; else: (claim-next) → preparing_worktree → running
   ;   → invoke adapter → on-finish:
   ;       verify changed-files vs allowlist
   ;       if ok: git commit (msg template)  → state=needs_review
   ;       if bad-allowlist: state=failed (no commit)
   ;       if adapter failure: state=failed
   ;       if no changes: state=needs_review/noop
   ;   → emit patch_job_events row
   ;   → call inbox handoff (Phase 3 hook)
```

Trigger:

- `(run-with-idle-timer 30 30 #'satan-patch-runner-tick)` — defensive sweep
- After successful `patch_job_create` (post-commit hook on tool): `(satan-patch-runner-tick)` immediate kick
- Manual: `M-x satan-patch-run-now`

Concurrency guard: `satan-patch-runner--active` buffer-local flag + a session-level mutex via row state (`claimed` → `running` transition is the lock).

Commit message (brief §8.3):

```
<mode>: <short imperative summary>

Patch-agent job: <job_id>
Source: <source kind/path if any>
```

Author/committer: defer to `jailed-pi`'s `clanker` identity (set by `sandboxGitIdentity`). Result is `git log` clearly distinguishes clanker commits from user commits — useful for reconciliation later.

### 3.5 Checks

Brief §10.2 listed `ert`, `emacs --batch -l ... -f ert-run-tests-batch-and-exit`, byte-compile, lint. Run these via the adapter (it's already in the jail, network on for any deps).

Result `checks_json` records per-check `{name, status, output_path}`. v1: if any check fails on a code change → state `failed`. Notes/prose changes → `needs_review` with warnings (brief §15.3).

### 3.6 Phase 2 acceptance

```
- fake adapter (test-only) drives a fixture worktree through success + allowlist-violation + no-op paths
- real jailed-pi adapter (gated by SATAN_PATCH_LIVE=1 env) makes a 1-file edit in a throwaway repo and commits
- runner timer fires; idle Emacs picks up a queued job; status moves queued → running → needs_review
- patch_job_result returns commits + diffstat + checks + review_commands
- changed-files outside allowlist → state=failed, no commit, error_json populated
- timeout: runner kills process, marks failed, records elapsed
- ert all green
```

## 4. Phase 3 — SATAN mode integration

Deliver: @satan directives + self-edit modes generate patch jobs end-to-end.

### 4.1 `notes_at_satan_done` extension

Today `notes_at_satan_done` claims a directive in-place by writing `@satan-was-here` + a `BEGIN_QUOTE satan <run-id>` block (cf. `satan-tools-atsatan.el`).

Add: a `:patch-job` arg. When set:

- write the quote block with `queued: <patch-job-id>` body (brief §5.3)
- the line is **not** considered claimed yet (`@satan` token still present? — no, replaced with `@satan-was-here`); but `notes_at_satan_scan` should skip lines tagged `queued:` so the directive doesn't reappear

Decision: skip claimed-or-queued in scan. Later, the runner's on-finish hook can rewrite the queued block in place with the final result (branch/commits), or append a follow-up block.

For Phase 3 simplicity: do **not** auto-rewrite. The original block stays as `queued:<job-id>`. The final result lands in inbox (§4.4). User can grep for the job-id in either place.

### 4.2 Tick-agent classifier

`satan-tick.el` already routes per mode. New helper:

```
(satan-patch/classify DIRECTIVE)
   -> 'patch | 'dispatch
```

Heuristic: keywords (`rewrite`, `implement`, `add`, `refactor`, `tighten`, `update`, `edit`, `fix`) → `patch`. Anything else → `dispatch`. Crude, intentionally. The tick prompt sees the helper output as a *hint*; the model still decides.

The tick prompt gets an explicit instruction: "if the directive is patch-shaped (multi-file edit, prose rewrite, code change), call `patch_job_create` instead of editing inline." Inline edits aren't possible today anyway (tick has no edit tools) — this just stops it from claiming the directive done when it should queue.

### 4.3 self-edit-mech / self-edit-mind

Update their prompt files (`~/notes/satan/prompts/self-edit-{mech,mind}.md` or wherever they currently live — confirmed at impl time) to route through `patch_job_create` for edit-shaped work.

Defaults (brief §10.2/10.3):

```
self-edit-mech:
  allowed_paths:  ["~/.emacs.d/satan/", "~/.emacs.d/test/", "~/notes/satan/tools/"]
  checks:        ert + emacs --batch byte-compile + bough-isolation lint

self-edit-mind:
  allowed_paths:  ["~/notes/satan/", "~/.emacs.d/satan/prompts/"]
  checks:        prompt lint + tool-name consistency
```

### 4.4 Inbox handoff

On state `needs_review` (success) or `failed` (when source was a user-facing directive):

```
(satan-tool/inbox-append
  :kind "patch-ready" or "patch-failed"
  :title "<mode>: <summary>"
  :properties (:SATAN_PATCH_JOB <id> :BRANCH <branch> :REPO <repo>)
  :body <render of brief §12 template>)
```

Body includes review_commands (diff + show + cherry-pick).

### 4.5 Memory hooks (light)

Optional in Phase 3 — already trivial. Wire later if it pulls weight:

```
on create:        memory_mark observation, topic=[patch-agent,<project>]
on needs_review:  memory_mark outcome=produced_artifact, valence=positive
on failed:        memory_mark outcome=unknown, valence=negative
```

Add iff doing so doesn't blow scope.

### 4.6 Phase 3 acceptance

```
- @satan directive "rewrite this section…" in a test note:
  1. tick scan picks it up
  2. tick classifies patch-shaped, calls patch_job_create
  3. line is marked @satan-was-here with queued:<job-id>
  4. runner picks up the job, jailed-pi edits the worktree, commits
  5. inbox gets a 'patch-ready' item with review commands
  6. nothing in the live note has been edited
- self-edit-mech can run end-to-end against a contrived directive
- ert all green, phase-3 broker ert still passes
```

## 5. Risks & open questions

1. **jailed-pi cwd vs worktree.** `baseJailOptions` binds `$PWD` to `/workspace/<basename>`. If worktree path is `~/.local/state/satan/patch-agent/worktrees/<job_id>`, basename `<job_id>` is fine, but pi inside the jail sees `/workspace/<job_id>`. Pi's own `--worktree`-related commands should be disabled (`--tools` allowlist excludes them — we pass `read,write,edit,bash,grep,find,ls` only). Confirm at impl time that pi doesn't refuse to start without a sensible-looking project name.
2. **API key path inside jail.** `passApiKeysFromEnv = useOpEnv = true` means the bwrap wrapper does `op run` then `--setenv`. Emacs invoking `jailed-pi` from a desktop-launched session: `op` must be on PATH and unlocked. Already a precondition for SATAN broker today; should "just work". Document as a known precondition.
3. **`accept_all` permission inside pi.** Default pi permission mode is "standard" — interactive prompts. For headless we need `--accept-all` or config `accept_all: true`. Decision: pass `--accept-all` from the adapter, on the basis that the jail itself is the safety boundary. Document explicitly.
4. **Repo as worktree target with `~/.emacs.d` open in user's Emacs.** Creating a worktree off `~/.emacs.d` is fine (git supports many worktrees of one repo). But `home-manager switch` from the user's session vs concurrent commits from the worktree could race during nix evaluation. Not a correctness problem (separate working trees), but worth a note.
5. **Pi vs zerostack feature parity.** Pi has clear headless mode. Zerostack adapter is TUI-first; if/when we need it, plan to use its ACP server (`--features acp`) and speak ACP. Out of scope for v1.
6. **Slug derivation for branch names.** Mode and a 6-char nanoid suffice; the human-readable slug is optional. Keep simple: `satan/<mode>/<timestamp>-<job-suffix>`.
7. **Migration order in test DB.** `satan_memory_test` migration 0004 status is "pending operator-applied" per [../memory/handover.md](../memory/handover.md). 0005 must not assume 0004 ran. Make 0005 independent of 0004's content.
8. **No-op detection.** Pi may emit a "no changes were needed" final message without writes. Detect via `git status --porcelain` in worktree post-run, not just adapter self-report.

## 6. Suggested commit cadence

```
1. migration 0005 + satan-memory-migrate.el update           (one commit)
2. satan-patch-store.el + tests                              (one commit)
3. satan-patch-worktree.el + tests                           (one commit)
4. satan-tools-patch.el + tool description files + tests    (one commit)
5. adapter protocol + fake adapter + runner skeleton + tests   (one commit)
6. pi adapter + prompt builder + prompt file + live-gated test (one commit)
7. inbox handoff + memory hooks                                 (one commit)
8. tick-agent classifier + self-edit-{mech,mind} prompt edits   (one commit)
9. CHANGELOG.md + brief follow-up notes                          (one commit)
```

Each commit green ert + green lint, mergeable independently for review.

## 7. Out of scope for this plan

- automatic merging / cherry-pick
- remote pushes
- parallel runners
- branch acceptance detection (`accepted_external` / `stale`)
- patch-agent → SATAN write tools (forbidden by design)
- zerostack adapter
- richer slugging / human-readable branch names beyond mode+timestamp
- web UI / TUI for browsing patch jobs (the inbox is enough for v1)
