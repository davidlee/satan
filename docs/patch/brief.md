---
name: satan-patch-brief
description: SATAN patch-agent extension — technical brief (scope, safety model, lifecycle, tool surface)
metadata:
  type: design
  topic: satan-patch
  status: canon
  updated_at: 03398479
  verified_at: 03398479
---

# Technical Brief: SATAN Patch-Agent Extension

## Purpose

Extend SATAN with a **patch-agent** lane for queued, edit-shaped work that should not be performed directly by normal SATAN modes.

The patch-agent is a sandboxed worker for notes and development projects. It operates in git worktrees, makes ordinary file edits using mature coding-agent tools, runs checks where available, commits its changes, and returns a branch/commit for human review.

It does **not** replace the existing SATAN broker, tick-agent, memory substrate, or proposal system.

Core distinction:

```text
tool-dispatch-shaped work → SATAN broker tools
patch-shaped work         → patch-agent worktree job
```

## Summary Decision

SATAN remains:

```text
broker
router
memory owner
tool-surface owner
audit owner
permission boundary
user-facing handoff layer
```

The patch-agent becomes:

```text
sandboxed patch worker
multi-file editor
test/check runner
git branch producer
```

Git becomes the proposal substrate for patch-shaped work.

The user accepts or rejects work by ordinary git review, cherry-pick, merge, or deletion of the branch.

---

# 1. Scope

## 1.1 In scope

The patch-agent should handle queued requests such as:

```text
rewrite this note section
tighten this design brief
implement this small elisp change
update these SATAN prompts
refactor this module
add tests for this memory canonicalizer
massage these notes into a coherent document
apply this proposal to a worktree
```

These requests share the same shape:

```text
read many files
understand local conventions
edit files
possibly run checks
produce a diff
commit result
return reviewable artifact
```

## 1.2 Out of scope

The patch-agent must not:

```text
mutate live files directly
mark @satan directives done by itself
write to SATAN inbox directly
write SATAN memory directly
call arbitrary SATAN tools
perform bough writes
send notifications
edit outside allowed paths
push to remotes by default
merge or cherry-pick into the user’s live branch
```

All user-facing effects are mediated by SATAN.

---

# 2. Architectural Principle

The patch-agent is a subordinate worker, not a peer agent.

```text
SATAN decides whether work is patch-shaped.
SATAN creates or queues a patch job.
Patch-agent operates only inside an isolated worktree.
Patch-agent returns structured result.
SATAN records, reports, and audits the outcome.
User accepts via git.
```

Do not let the coding harness become a second authority with its own memory, tool policy, or claim lifecycle.

---

# 3. Work Classification

SATAN should classify incoming requests into two lanes.

## 3.1 Tool-dispatch-shaped

Use the existing SATAN broker/tool path.

Examples:

```text
read agenda
append inbox item
mark behavioural memory
read bough active tasks
summarize context
mark @satan directive done
write today's owned SATAN block
```

Properties:

```text
bounded context
known domain tool
little or no file editing
single tool call or short tool chain
custom idempotency matters
SATAN transcript is the audit
```

Route:

```text
tick-agent / mode prompt
→ domain tool
→ satan_final
```

## 3.2 Patch-shaped

Use the patch-agent.

Examples:

```text
rewrite note prose
edit prompt files
implement elisp code
update tests
refactor module
apply design proposal
```

Properties:

```text
multi-file read/edit
needs local conventions
benefits from diff review
may need tests/checks
should not directly touch live files
git is the approval boundary
```

Route:

```text
SATAN broker
→ patch_job_create
→ patch-agent worktree
→ patch_job_result
→ inbox/proposal handoff
→ user cherry-pick/merge
```

---

# 4. Safety Model

## 4.1 Isolation boundary

Every patch job runs in a git worktree.

Required properties:

```text
dedicated branch
dedicated worktree path
allowed repository root
allowed path set
no live branch mutation
no direct upstream merge
no push by default
```

Suggested worktree root:

```text
~/.local/state/satan/patch-agent/worktrees/
```

Suggested branch naming:

```text
satan/<mode>/<YYYYMMDDTHHMMSS>-<slug>
```

Example:

```text
satan/note-rewrite/20260520T184233-memory-brief
satan/self-edit-mech/20260520T190122-canon-tests
```

## 4.2 Permission boundary

Patch-agent receives:

```text
repo path
base ref
branch name
allowed paths
task directive
context bundle
checks to run
max runtime / max turns
```

Patch-agent does not receive:

```text
SATAN inbox write access
SATAN memory write access
SATAN notification access
bough write access
live @satan claim mutation
global filesystem write access
```

## 4.3 Human approval boundary

Patch-agent output is accepted only by user action:

```text
git diff
git show
git cherry-pick
git merge
manual copy
delete branch
```

SATAN may report:

```text
branch name
commit hashes
diffstat
checks run
warnings
review commands
```

SATAN must not merge on the user’s behalf unless a future explicit mode grants that capability.

---

# 5. Job Lifecycle

## 5.1 States

Recommended patch job states:

```text
queued
claimed
preparing_worktree
running
needs_review
failed
cancelled
accepted_external
stale
```

Minimal v1 states:

```text
queued
running
needs_review
failed
cancelled
```

## 5.2 Lifecycle

```text
1. SATAN receives or discovers patch-shaped request.
2. SATAN creates patch job record.
3. Job runner creates worktree + branch.
4. Patch-agent executes directive in worktree.
5. Patch-agent commits changes if successful.
6. Runner records result: commits, diffstat, checks, warnings.
7. SATAN writes inbox/proposal handoff.
8. User reviews with git.
9. Optional later reconciliation detects accepted/stale/deleted branches.
```

## 5.3 Queued `@satan` directive lifecycle

For notes containing `@satan` directives:

```text
@satan rewrite this section as a tight technical brief
```

Current tick-agent should not perform arbitrary rewrites. It should classify and queue:

```text
scan directive
→ classify patch-shaped
→ patch_job_create
→ mark directive queued or done-with-handoff
→ report job/branch to inbox
```

Possible markers (current scheme — see `satan-tools-atsatan.el`):

```org
@satan-was-here
#+BEGIN_QUOTE satan <run-id>,patch-job
queued: <patch-job-id>
#+END_QUOTE
```

Or for a completed claim, the body describes the completed action
(branch name, review link, etc.) under the same `@satan-was-here`
header plus quote block.

Recommendation:

Reserve a `queued:` prefix in the comment body when job execution is
asynchronous or long-running, so the model can later overwrite the
block (or write a follow-up) when it completes.

Only claim (`notes_at_satan_done`) when SATAN has completed its
responsibility for that directive. If the patch branch exists and the
user has been told how to review it, claiming is acceptable. Otherwise
leave the directive unclaimed and surface progress via `inbox_append`.

---

# 6. Tool Surface

Add a patch-agent tool group owned by the SATAN broker.

## 6.1 `patch_job_create`

Creates a patch job and optionally starts it.

```text
risk: low write
capability: patch-job-create
args:
  directive          string, required
  repo               string, required
  base_ref           string, optional default current HEAD
  allowed_paths[]    array, required
  mode               enum, required
  source             object, optional
  context            object, optional
  checks[]           array, optional
  start              boolean, optional default true
returns:
  ok {
    job_id
    state
    repo
    worktree_path
    branch
    allowed_paths[]
  }
  error string
```

`source` should describe where the request came from:

```json
{
  "kind": "at_satan_directive",
  "file": "~/notes/...",
  "line": 42,
  "directive_id": "..."
}
```

`context` may include:

```json
{
  "note_context": "...",
  "memory_matches": [...],
  "bough_nodes": [...],
  "proposal_id": "...",
  "mode_run_id": "..."
}
```

## 6.2 `patch_job_status`

Reads job state.

```text
risk: read
capability: none
args:
  job_id string, required
returns:
  ok {
    job_id
    state
    branch
    worktree_path
    started_at
    updated_at
    summary
    last_error
  }
```

## 6.3 `patch_job_result`

Reads final result.

```text
risk: read
capability: none
args:
  job_id string, required
returns:
  ok {
    job_id
    state
    repo
    branch
    base_ref
    worktree_path
    commits[]
    diffstat
    checks[]
    warnings[]
    summary
    review_commands[]
  }
```

## 6.4 `patch_job_cancel`

Cancels queued/running job where possible.

```text
risk: low write
capability: patch-job-cancel
args:
  job_id string, required
returns:
  ok { job_id, state }
```

## 6.5 `patch_job_cleanup`

Deletes abandoned worktree/branch if safe.

```text
risk: medium write
capability: patch-job-cleanup
args:
  job_id string, required
  delete_branch boolean, optional default false
returns:
  ok { job_id, removed_worktree, deleted_branch }
```

Cleanup should require explicit mode permission. It is not a tick-agent tool.

---

# 7. Job Record Schema

A simple SQLite/Postgres table is enough. If SATAN already uses Postgres, use a `satan_patch` schema or tables in the SATAN database.

## 7.1 Tables

```sql
CREATE TABLE patch_jobs (
  id                TEXT PRIMARY KEY,
  state             TEXT NOT NULL CHECK (state IN
                      ('queued','claimed','preparing_worktree','running',
                       'needs_review','failed','cancelled','accepted_external','stale')),
  mode              TEXT NOT NULL,
  directive         TEXT NOT NULL,

  repo              TEXT NOT NULL,
  base_ref          TEXT NOT NULL,
  branch            TEXT NOT NULL,
  worktree_path     TEXT NOT NULL,

  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  started_at        TIMESTAMPTZ,
  finished_at       TIMESTAMPTZ,

  source_json       JSONB NOT NULL DEFAULT '{}'::jsonb,
  context_json      JSONB NOT NULL DEFAULT '{}'::jsonb,
  allowed_paths_json JSONB NOT NULL,
  checks_json       JSONB NOT NULL DEFAULT '[]'::jsonb,

  result_json       JSONB,
  error_json        JSONB
);

CREATE INDEX patch_jobs_state_idx ON patch_jobs(state);
CREATE INDEX patch_jobs_created_idx ON patch_jobs(created_at DESC);
CREATE INDEX patch_jobs_repo_branch_idx ON patch_jobs(repo, branch);
```

## 7.2 Result JSON

```json
{
  "summary": "Tightened memory prompt language and added patch-agent routing note.",
  "commits": [
    {
      "sha": "abc1234",
      "subject": "Update SATAN memory prompt"
    }
  ],
  "diffstat": {
    "files_changed": 3,
    "insertions": 92,
    "deletions": 41
  },
  "checks": [
    {
      "name": "emacs batch byte-compile",
      "status": "passed",
      "output_path": "/..."
    }
  ],
  "warnings": [
    "No automated tests found for notes-only change."
  ],
  "review_commands": [
    "git -C ~/.emacs.d diff main...satan/self-edit-mech/20260520T190122-canon-tests",
    "git -C ~/.emacs.d cherry-pick abc1234"
  ]
}
```

---

# 8. Worktree Management

## 8.1 Create worktree

Procedure:

```text
resolve repo root
verify clean enough or allow dirty base explicitly
fetch current HEAD/base ref
create branch name
git worktree add <worktree_path> -b <branch> <base_ref>
write job manifest into worktree or SATAN state dir
```

Do not create worktrees inside the repo.

Suggested path:

```text
~/.local/state/satan/patch-agent/worktrees/<job_id>/
```

## 8.2 Allowed paths

Before running the patch-agent, provide allowed paths.

Examples:

```text
~/.emacs.d/satan/
~/notes/satan/
~/notes/20260519T003129--satan__agent_emacs_project.org
```

The runner should enforce allowed paths after execution:

```text
git diff --name-only <base_ref>...HEAD
```

If any changed file is outside allowed paths:

```text
state = failed
error = changed_path_outside_allowlist
```

Optionally auto-revert out-of-scope changes in v2. In v1, fail loudly.

## 8.3 Commit policy

Patch-agent should commit only if:

```text
there are changes
changed paths are allowed
checks passed or failures are recorded as acceptable warnings
commit message is generated
```

Commit message format:

```text
<satan-mode>: <short imperative summary>

Patch-agent job: <job_id>
Source: <source kind/path if any>
```

Example:

```text
self-edit-mech: add memory canonicalizer tests

Patch-agent job: patch_20260520T190122_a13f
Source: at_satan_directive ~/notes/...:42
```

---

# 9. Coding Harness Contract

The coding harness should receive a self-contained job prompt.

## 9.1 Harness input

```json
{
  "job_id": "patch_20260520T190122_a13f",
  "repo": "~/.emacs.d",
  "worktree_path": "~/.local/state/satan/patch-agent/worktrees/patch_...",
  "base_ref": "main",
  "branch": "satan/self-edit-mech/20260520T190122-canon-tests",
  "directive": "Add tests for memory canonicalizer fixtures.",
  "allowed_paths": [
    "satan/",
    "test/"
  ],
  "context": {
    "mode": "self-edit-mech",
    "source": "...",
    "memory_matches": []
  },
  "checks": [
    "emacs --batch -l test/satan-memory-test.el -f ert-run-tests-batch-and-exit"
  ],
  "output_contract": {
    "must_commit": true,
    "must_report_summary": true,
    "must_report_checks": true,
    "must_not_edit_outside_allowed_paths": true
  }
}
```

## 9.2 Harness responsibilities

The harness may:

```text
read files in worktree
edit files in worktree
create files in allowed paths
run local commands
run tests/checks
commit changes
produce summary
```

The harness must not:

```text
write outside worktree
access SATAN private DBs directly
call SATAN memory/inbox/bough tools
push to remotes
change branch outside assigned worktree
mark directives done
```

## 9.3 Harness output

```json
{
  "status": "success",
  "summary": "...",
  "commits": ["abc1234"],
  "checks": [
    {"name": "ert", "status": "passed", "output": "..."}
  ],
  "warnings": [],
  "changed_files": [
    "satan/satan-memory-canon.el",
    "test/satan-memory-test.el"
  ]
}
```

SATAN runner verifies this output against git reality.

---

# 10. SATAN Mode Integration

## 10.1 `tick-agent`

Do **not** give `tick-agent` direct edit tools.

Allowed behavior:

```text
classify @satan directive
if tool-dispatch-shaped: handle directly
if patch-shaped: create patch job or append inbox/proposal to create one
mark directive queued/done according to lifecycle
```

Tick-agent should not run long patch jobs inline unless explicitly permitted.

## 10.2 `self-edit-mech`

Primary first adopter.

Use patch-agent for:

```text
elisp implementation changes
tool schema edits
migration changes
test additions
prompt file mechanical edits
```

Default allowed paths:

```text
~/.emacs.d/satan/
~/.emacs.d/test/
~/notes/satan/tools/
```

Checks:

```text
ert tests where available
emacs batch load/byte-compile
grep lint for forbidden bough DB access
```

## 10.3 `self-edit-mind`

Use patch-agent for:

```text
prompt rewrites
mode prompt edits
design note edits
organism framing changes
```

Default allowed paths:

```text
~/notes/satan/
~/.emacs.d/satan/prompts/
```

Checks:

```text
prompt lint
tool-name consistency check
no direct final JSON blob instruction
no free-text handle invention
```

## 10.4 Note rewrite mode

Optional later mode.

Use patch-agent for:

```text
rewrite section
distill brief
turn chat into design note
split note into files
normalize org headings
```

Restrictions:

```text
must preserve original in git
must commit separately
must not rewrite unrelated sections unless directive permits
```

---

# 11. Memory Integration

Patch jobs should be visible to SATAN memory, but the patch-agent must not write memory directly.

SATAN broker may call `memory_mark` at lifecycle points.

## 11.1 On job creation

```text
kind: observation
payload: "Queued patch-shaped request for worktree agent."
hints:
  phase: execution
  topic: [patch-agent, <project>]
valence: neutral
```

Useful handles may include:

```text
project:emacs.d
artifact:none
intervention:surface
```

## 11.2 On job result

If successful:

```text
payload: "Patch-agent produced branch <branch> with <n> commits for <directive>."
hints:
  outcome: produced_artifact
  topic: [patch-agent, <project>]
valence: positive
```

If failed:

```text
payload: "Patch-agent failed while attempting <directive>; failure reason <x>."
hints:
  outcome: unknown
valence: negative
```

## 11.3 On user acceptance

Optional future reconciliation:

```text
detect branch merged/cherry-picked
mark outcome: produced_artifact / accepted_external
```

This is not v1 required.

---

# 12. Inbox / User Handoff

SATAN should report patch results through inbox unless interruption is useful.

Example inbox item:

```org
* Patch ready: memory canonicalizer tests
:PROPERTIES:
:SATAN_PATCH_JOB: patch_20260520T190122_a13f
:BRANCH: satan/self-edit-mech/20260520T190122-canon-tests
:REPO: ~/.emacs.d
:END:

The patch-agent produced 1 commit.

- abc1234 self-edit-mech: add memory canonicalizer tests
- Checks: ert passed
- Changed: 2 files, +143/-12

Review:
#+begin_src sh
git -C ~/.emacs.d diff main...satan/self-edit-mech/20260520T190122-canon-tests
git -C ~/.emacs.d show abc1234
#+end_src

Accept:
#+begin_src sh
git -C ~/.emacs.d cherry-pick abc1234
#+end_src
```

Notifications should be rare:

```text
patch failed after explicit user request
patch ready for time-sensitive active work
patch changed high-risk files and needs review before continuing
```

---

# 13. Proposal System Relationship

Keep both systems.

## 13.1 Use `proposal_stage` for

```text
policy proposals
tool capability changes
non-git design suggestions
small suggested edits not worth a branch
dangerous actions requiring explicit approval
```

## 13.2 Use patch-agent for

```text
multi-file edits
code changes
note rewrites
prompt rewrites
test changes
refactors
anything naturally represented as git diff
```

## 13.3 Rule

```text
If acceptance is best represented by cherry-pick or merge, use patch-agent.
If acceptance is best represented by “approve this idea,” use proposal_stage.
```

---

# 14. Audit

There are three audit layers.

## 14.1 SATAN transcript

Records:

```text
classification
patch_job_create call
patch job ID
inbox handoff
satan_final
```

## 14.2 Patch job DB

Records:

```text
directive
source
context
repo/base/branch/worktree
state transitions
result
errors
checks
```

## 14.3 Git

Records:

```text
exact diff
commits
author
timestamps
review boundary
```

Patch-agent output should be reproducible enough to answer:

```text
why did this job exist?
what was it allowed to edit?
what did it actually edit?
what checks ran?
how can I accept/reject it?
```

---

# 15. Failure Modes

## 15.1 Worktree creation fails

Causes:

```text
repo missing
base ref missing
dirty state policy rejects
branch already exists
worktree path exists
```

Response:

```text
state = failed
record error
inbox if user needs action
```

## 15.2 Harness edits outside allowlist

Response:

```text
state = failed
do not commit, or commit only after reverting out-of-scope changes
record changed paths
surface warning
```

v1 recommendation: fail before commit.

## 15.3 Checks fail

Response options:

```text
state = failed
```

or:

```text
state = needs_review with warnings
```

Recommendation:

```text
code changes → failed unless checks are known unavailable
note/prose changes → needs_review with warnings
```

## 15.4 No changes produced

Response:

```text
state = failed or needs_review/noop
record harness summary
no commit
```

If the agent concluded no change was appropriate, report that as a completed no-op.

## 15.5 Job becomes stale

Branch falls behind, source directive changed, or allowed paths changed.

Response:

```text
state = stale
recommend recreate
```

## 15.6 User manually edits branch

Do not assume patch-agent owns branch forever. Detect divergence and mark:

```text
accepted_external
modified_external
stale
```

v1 can ignore this unless cleanup/reconciliation is implemented.

---

# 16. Security and Containment

Minimum containment rules:

```text
run in worktree
enforce allowed paths
no network unless mode explicitly allows
no push
no writes outside worktree
no access to SATAN write tools
no secrets in prompts where avoidable
redact tokens from result logs
cap output sizes
timeout commands
```

If using a general coding harness, wrap it with:

```text
environment variables scrubbed
working directory fixed to worktree
explicit allowlist of commands if possible
resource limits
log capture
```

---

# 17. Implementation Plan

## Phase 1 — Job DB and worktree runner

Deliver:

```text
patch_jobs table
patch_job_create
patch_job_status
patch_job_result
manual runner stub
worktree creation
branch naming
allowed path verification
result recording
```

No coding harness yet. The runner may create worktree and stop.

Acceptance:

```text
can create worktree branch from repo/base
can record job
can mark failed/cancelled/needs_review manually
```

## Phase 2 — Harness integration

Deliver:

```text
invoke coding harness with job manifest
capture output
verify changed paths
run checks
commit result
record result_json
```

Acceptance:

```text
can execute simple note edit in worktree
can produce commit
can return review commands
can fail on out-of-allowlist edit
```

## Phase 3 — SATAN mode integration

Deliver:

```text
self-edit-mech can create patch job
self-edit-mind can create patch job
tick-agent can classify patch-shaped @satan directive and queue job
inbox handoff for completed jobs
```

Acceptance:

```text
patch-shaped directive does not cause live edit
job branch is produced
user receives review/cherry-pick instructions
```

## Phase 4 — Memory and reconciliation

Deliver:

```text
memory_mark on job creation/result
optional branch acceptance detection
stale job detection
cleanup command
```

Acceptance:

```text
SATAN can later resonate against prior patch-agent successes/failures
old worktrees can be safely listed/cleaned
```

---

# 18. Acceptance Criteria

A v1 patch-agent extension is acceptable when:

```text
1. SATAN can create a patch job from a directive.
2. The job runs in a dedicated git worktree and branch.
3. The patch-agent can edit only allowed paths.
4. Changed paths are verified before success.
5. Results are committed to the patch branch.
6. Checks are run or explicitly recorded as unavailable.
7. SATAN reports branch, commits, diffstat, checks, and review commands.
8. The user can accept via git cherry-pick or merge.
9. Tick-agent remains unable to perform arbitrary live edits.
10. Patch-agent cannot call SATAN memory/inbox/bough/write tools directly.
11. SATAN transcript, patch job DB, and git history together explain what happened.
```

---

# 19. Non-Goals for v1

Do not implement initially:

```text
automatic merging
remote pushing
background daemon scheduling
parallel patch jobs
complex dependency graph between jobs
semantic branch acceptance detection
full issue tracker
patch-agent memory writes
patch-agent bough writes
free-form live note editing from tick-agent
```

---

# 20. Design Tests

Use these questions to reject bad integrations.

```text
Is this task naturally represented as a git diff?
If yes, patch-agent may fit.

Does the task only need a SATAN domain tool?
If yes, patch-agent is overkill.

Can the user reject the result by ignoring/deleting a branch?
If no, containment is weak.

Can SATAN explain why the job was created?
If no, audit is weak.

Can the patch-agent mutate SATAN state directly?
If yes, boundary is wrong.

Can the patch-agent edit outside allowed paths?
If yes, containment is wrong.

Does acceptance require bespoke proposal parsing instead of git?
If yes, maybe use proposal_stage instead.
```

---

# 21. Compact Principle

```text
SATAN routes. Patch-agent edits. Git proposes. User cherry-picks.
```

Or more explicitly:

```text
Keep SATAN's broker loop narrow and idempotent.
Move edit-shaped work into isolated git worktrees.
Treat commits as proposals.
Let human git operations be the approval gate.
```
