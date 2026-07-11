<!-- Shipped reference (ADR-005 PULL tier). Edit the source in
     `install/dispatch-mechanics.md`; the installed copy at
     `.doctrine/dispatch-mechanics.md` is inert. Explains the fork→land funnel and
     its sharp edges — it never reproduces `doctrine --help`; ask the CLI for exact
     flags. Distilled from project-local dispatch memories (CHR-036). -->

# Dispatch mechanics

How the `/dispatch` funnel actually moves code — the fork→verify→import→land
pipeline, the git-plumbing invariants it rests on, and the failure modes that
have cost real respawns. This is the *explain* tier: read it once to build the
mental model. For the sharp mid-operation traps you hit *while* driving a
dispatch, retrieve `mem.signpost.doctrine.dispatch`; for command shapes ask
`doctrine <command> --help`.

The orchestrator is the sole writer. Workers execute one phase inside an
isolated worktree and hand back a single source-delta; the orchestrator imports
that delta, verifies, and commits. Everything below protects that contract.

## The fork base is explicit, never the session HEAD

A worker's fork **must** be created from the explicit coordination base `B` —
the orchestrator's coordination-branch HEAD captured pre-spawn — never from the
implicit current/session HEAD.

The session repo may sit on a different branch (e.g. `main`) than the
coordination branch, so **session HEAD ≠ `B`**. A fork that inherits the
implicit HEAD lands on a divergent base: `S.parent != B`, and the net diff
`B..S` then smuggles the session↔coordination divergence into the import —
unrelated commits ride into the wrong slice's delta.

Two belts enforce it:
- **Worker baseline guard.** Immediately after `git worktree add <dir> <branch>
  <B>`, assert `git -C <dir> rev-parse HEAD == B` and abort otherwise.
- **Orchestrator import guard (trusted side).** Assert `git rev-parse S^ == B`
  before applying the delta — catches a misbased fork even if the worker skipped
  its own guard.

Harness trap: some spawn backends build the fork from the session HEAD and give
no reliable base control (the claude `Agent` tool at `isolation: worktree` is
one). Where the backend won't honour `B`, spawn a plain agent that self-forks
from `B` explicitly rather than trusting the backend's isolation.

## Verify scope: never run the project-wide gate in the funnel

Funnel and worker verification must be **scoped to the touched files**, not the
whole tree. A project-wide format gate (e.g. `cargo fmt` inside `just gate`)
reformats in place across the crate and pulls unrelated pre-existing drift into
the worker's delta — a base commit that isn't format-clean under the pinned
toolchain will smuggle format churn into every slice.

Scope it: lint + test + a `--check`-only formatter over the touched files. Prove
the phase, don't reformat the world.

## Two ways a worker returns its delta: gated self-commit vs working-tree diff

The worker cannot run raw `git commit` — the linked worktree's `.git` is
read-only (jail wall). Two arms clear that wall differently:

- **claude arm — gated server-side self-commit.** The worker calls the
  `worker_commit` MCP tool, passing only its own opaque `agent` id (its worktree
  name — **never a path**). The *unconfined* server resolves that id to the
  worker's worktree and lands the commit on its behalf, so the jailed worker never
  touches `.git` directly. This is a deliberate, single-purpose bypass of the jail
  wall — therefore the tool's **belts are the security boundary**, not the wall:
  non-empty pre-fmt delta → two-tier scope (a HARD forbidden-zone that hard-refuses
  any write under `.doctrine/`, `.claude/`, or the configured
  `[dispatch].worker-forbidden-writes`, plus a SOFT undeclared-path report) →
  `HEAD == B` → the `check commit` gate → exactly one non-merge commit `C`
  (`C^ == B`) on the worker's own `dispatch/<agent>` branch. A spoofed sibling id
  commits to the *sibling's* branch and leaves its own at `B`.
- **subprocess (pi) arm — working-tree diff.** The worker cannot self-commit at
  all; it hands the tree back and the orchestrator captures the working-tree diff
  (`import --from-worktree`). This is also the fallback when the MCP server is down.

The orchestrator then imports. On the claude arm it imports the **commit**
(`import --fork <C> --branch dispatch/<agent>`); the `--branch` coherence belt
binds the import to the branch the orchestrator *armed*, so it promotes nothing of
a poisoner who committed to a sibling's branch. `verify-worker` accepts the
post-commit `HEAD` because it tests `merge-base --is-ancestor B HEAD` (a
descendant), not `HEAD == B`. Either arm's import is **non-committing** (next
section) — the delta is diff-applied, and the orchestrator commits separately.

Ask `doctrine worktree --help` / `doctrine mcp` for exact flags and the tool's
refusal tokens.

## Mode B — the confined-orchestrator arm drives the funnel through MCP

Everything above assumes the **main thread** orchestrates: an unconfined driver
running raw git by hand. **Mode B** is the other arm — a *confined subagent
orchestrator* whose cwd is jailed to the coordination tree and whose raw `.git`
is read-only. It cannot run the funnel by hand; it drives the same fork→land
pipeline entirely through the dispatch MCP tools. Mode B is the capstone of the
confined-drive posture; the main-thread arm (this doc's default) stays the
fallback for when the MCP server is down.

**The fork override.** A confined nested `isolation:worktree` spawn would (per
"The fork base is explicit", above) fork off the session HEAD — no base control.
Mode B arms the create-fork one-shot with `arm-spawn` *first*, so the worktree
hook Forks the worker's `dispatch/<name>` branch at the explicit base `B` with
its jail record provisioned. That provisioning is what makes the worker's
`worker_commit` resolvable server-side — without the armed base there is no
branch for the gated self-commit to land on.

**The funnel folds the by-hand steps.** Where the main-thread arm imports, then
commits, then flips the phase, then records the boundary as separate manual acts,
Mode B's MCP tools fold each pair into one server-side act:

- `dispatch_import` **applies AND commits** the delta server-side — the import
  folds the commit (no separate orchestrator commit step).
- `dispatch_conclude_phase` is a **two-tier, self-healing conclude**. The
  `completed` flip is a **disposable runtime write** to the gitignored phase sheet
  (`.doctrine/state/…`) — it never enters committed history, so it can never be a
  "completed-without-boundary" hazard. The real completion signal is the
  **committed `(B, coord_tip)` boundary row**, landed by ONE working-tree-free
  `commit_on_behalf`. The only fault outcome is a flipped (disposable) sheet with
  **no committed boundary**; because that sheet is disposable, a retry simply
  re-composes the boundary — `completed`-WITH-committed-boundary is the only
  durable success state.
- an **undeclared-scope delta is hard-refused before anything lands** — the scope
  belt is server-side, not an orchestrator judgement call.

**reads-raw / writes-MCP split.** The confined orchestrator reads git directly
(`status`, `diff`, `log`, `rev-parse` — to know the coord tip and inspect a
worker's commit) but every *write* goes through an MCP tool. It never mutates
`.git` by hand.

**The boundary — report-and-halt, never auto-merge.** Trunk-facing ops
(`integrate`, `refresh-base`, candidate) write OUTSIDE the coord jail, which is
read-only to Mode B — so it **report-and-halt**s them to the main thread rather
than attempting them. The same boundary catches a red worker verify and a hard
scope refusal: Mode B returns a structured summary and stops. It never
auto-merges and never self-unblocks a refusal.

## The import severs ancestry — so "did it land?" needs a patch-id oracle

The funnel imports a worker's delta with a non-committing 3-way apply onto `B`,
then the orchestrator commits separately. This **severs git ancestry**: the fork
branch `S` is never an ancestor of the coordination commit. Every naive
landed-oracle is therefore unsound:

- `git branch --merged` — the apply-funnel branch is never merged, always
  reported unmerged (and `git branch -d` always refuses it; deletion needs `-D`).
- **Delta-emptiness** (`git diff B..fork` empty ⇒ landed) — `B..fork` is the
  whole worker delta, never empty for real work, so it refuses every fork. And
  the moment a sibling moves the coordination HEAD, `HEAD..fork` legitimately
  diverges ⇒ non-empty ⇒ also refuses a spent fork. Either way the operator
  learns a `--force` reflex and the safety gate collapses.
- **A runtime-tier "import receipt"** stamped on apply-success — unsound too. It
  certifies the *apply*, not the *commit*: it is born before the separate commit,
  lives in disposable state, and survives a crash-before-commit — reading
  "landed" when no commit ever reached the branch, so a recovery-time cleanup
  reaps the only surviving copy of unmerged work. A flag in disposable state must
  never gate an irreversible `branch -D`.

**Sound oracle: a durable patch-id check.** Run `git cherry <coordination-HEAD>
<fork-branch>` and treat the fork as landed **only when every commit in its
`B..fork` range is marked `-`** (its patch is already present in coordination's
history by patch-id). Any `+` ⇒ not fully landed ⇒ refuse. This is keyed on
durable git state *after* the commit, so it is crash-proof (a crash before the
commit leaves no landed patch ⇒ `+` ⇒ refuse), robust to a sibling moving HEAD
(patch-id matches the commit's patch, not a whole-tree diff), and robust to the
apply severing ancestry (patch-id ≠ ancestry). Ranging over *all* commits (not a
single tip) lets one oracle serve both the single-commit dispatch fork and the
multi-commit solo fork.

### The squash blind spot

The patch-id oracle **cannot** distinguish a *multi-commit* squash-merge from a
fork that never landed. A multi-commit `git merge --squash` produces one squash
commit whose patch-id matches none of the fork's individual commits, so `git
cherry` lists every commit `+` and the tip is not an ancestor — byte-for-byte the
signal of a fork that never landed. (A *single*-commit squash is fine: its
patch-id equals the squash commit's, so `git cherry` marks it `-` and certifies
it landed — the blind spot is strictly the multi-commit case.) Do not build a
squash detector; it cannot exist.
Collapse squash + never-landed into one `not-landed` refusal whose message names
both remedies. This is the load-bearing reason a solo fork must land via a
non-squash (`--no-ff`) verb: squash destroys the oracle.

## Landing on a shared trunk races — report and halt, never auto-merge

Integrating onto a live shared trunk is fast-forward-only plus an expected-tip
compare-and-swap. On a trunk where other agents commit concurrently, two
failures bite — both report-and-halt by design:

1. **Trunk moved mid-command.** The admitted target's base went stale between
   "create candidate" and "integrate". Fix: re-create the candidate superseding
   the prior on the new base, re-admit, re-integrate. To shrink the race window,
   chain create→admit→integrate in one shell invocation (the candidate ref name
   is deterministic, so nothing needs threading). Expect retries under churn.
2. **Dirty-worktree refusal.** Integrate resyncs the live checkout and refuses a
   blanket-dirty tree — even when the dirty file is another slice's authored WIP
   that cannot conflict with the projected code. You may not stash or discard
   another agent's uncommitted work. Resolution is the work's owner committing
   it, then re-superseding (their commit advanced trunk) and integrating. The
   driver cannot self-unblock — surface it and wait.

The trunk ladder defaults to the remote's `origin/HEAD`, which lags a local
trunk; point dispatch verbs at the intended local trunk ref explicitly.

## Worker-spawn identity is accident-fenced, not fail-closed

A `SubagentStart`-style spawn hook that stamps a worker-identity marker runs
synchronously (the marker is present before the worker's first command *when the
hook succeeds*) but is **read-only** — it cannot abort the subagent on failure.
On a stamp failure the worker proceeds unstamped and un-gateable by the hook. So
worker identity must be fenced by the **import belt + a worker-mode env guard +
the pre-distilled prompt**, never by the hook's exit status. The only
fail-closed-capable creation seam is a worktree-creation hook (non-zero exit
aborts creation), preferable *where the harness exposes it with enough payload to
act on* — often it does not: a creation hook whose payload lacks the worker's
type/path can neither scope its check nor identify what to abort, so it stays
deferred and the belt-plus-guard fence remains the default.

## Workers can silently discard their own work

A worker may build a phase correctly (tests green) and then `git reset` /
`checkout -- ` / `stash` / `clean` the entire delta away — hallucinating a
"pre-existing WIP", reverting its own edits, and never committing. The fork comes
back clean (HEAD == B, empty diff). Fence it at the prompt:
- State the fork is a **clean** checkout with **no** WIP and that the target
  files do not yet exist.
- Forbid every work-discarding git verb; the only git the worker runs is the
  final `git add <paths>` + `commit`.
- For a red-proof reversion (TDD), instruct it to *edit* the scratch out, never
  to git-discard it.

And never trust the worker's self-reported success — the fork's committed git
state is the ground truth. Re-read the commit, re-run the suite; distrust the
handover's own green/failure labels.

## Subprocess-arm RPC hygiene (codex/pi)

When the worker is a subprocess speaking a line-oriented RPC:
- **One compact JSON object per line.** A pretty-printed prompt message emits
  multi-line JSON and every line fails to parse — the prompt never lands and the
  worker sits idle. Build RPC lines compact (single-line).
- **The process may park on success, not self-exit.** It emits a completion
  event but blocks on stdin, so a timeout-bound spawn burns the full timeout even
  though work finished in minutes. Run a watcher that polls the log for the
  completion event and kills the process on match, so the spawn returns at
  completion rather than at timeout.

## See also

- `mem.signpost.doctrine.dispatch` — the retrieval index for the sharp
  mid-operation traps (retrieve *during* a dispatch, not up front).
- ADR-006 (worktree posture), ADR-008 (jail isolation), ADR-011 (harness-agnostic
  spawn), ADR-012 (integration topology) — the decisions behind this machinery.
- `doctrine dispatch --help`, `doctrine worktree --help` — exact command shapes.
