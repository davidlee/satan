---
name: satan-patch-handover
description: SATAN patch-agent handover — current state (Phase-3 content + op-cache port + pi fixes)
metadata:
  type: handover
  topic: satan-patch
  status: living
  updated_at: 03398479
  verified_at: 03398479
---

# SATAN patch-agent — Handover (Phase-3-content + op-cache port)

Builds on [archive/handover-phase3-mechanism.md](archive/handover-phase3-mechanism.md) (Phase-3 mechanism).  Read that
first; this file is a delta.

This session shipped the Phase-3 *content* + four bug fixes that
surfaced when the mechanism met real pi for the first time.  The
last failure on record was a PATH-resolution miss from an
`emacsclient`-driven kick (latent; not introduced this session).
Acceptance §4.6 has been seen up to "pi spawned, ran code" but not
yet to a clean `needs_review` row with commits.

## What landed (commits on `main`)

```
bb6bbe55  satan(atsatan): treat legacy `@satan-done` token as claimed in scan
c94fd403  satan(budget): raise daily ceiling 800k → 1M tokens          (then 2M)
a1243482  satan(budget): bump daily ceiling 1M → 2M tokens
59ad1ea6  satan(modes): expose patch_job_create + patch_job_status to
          tick-agent + self-edit-{mech,mind}
fe5c1017  satan(patch-adapter, jailed-pi flake): port broker's op-cache
          path to pi adapter
1f5910c6  satan(patch-adapter): close stdin after spawning jailed-pi
4cca6b40  satan(patch-adapter): swap to pi's `--system-prompt' + persist
          pi stderr
```

`~/notes` repo:

```
9c3d975   satan(prompts): route patch-shaped work through patch_job_create
```

Prod DB now at migration 5 (operator applied 0004 + 0005 mid-session).

## Phase-3 content (per plan §4.3)

- `~/notes/satan/prompts/tick/agent.txt` — patch-shaped action: call
  `patch_job_create`, then `notes_at_satan_done :patch-job <id>`.
  Discipline added: no inline edits in tick; queue or skip.
- `~/notes/satan/prompts/self-edit-mech.txt` — patch lane is now the
  default; defaults aligned with brief §10.2 (allowed_paths,
  checks).  Proposal lane retained for design-shape work.
- `~/notes/satan/prompts/self-edit-mind.txt` — same shape with mind
  defaults.

## Mode manifests (the missing piece)

The prompt edits told the model to call `patch_job_create` but the
broker tool gate (`dl-satan-tool-allowed-p`) is the mode's `:tools`
allowlist.  Before this session, none of `tick-agent`,
`self-edit-mech`, `self-edit-mind` had `patch_job_*` in `:tools`,
so the broker refused the call and the model fell back to
`inbox_append`.  Now:

- `dl-satan-tools-atsatan.el` — `dl-satan-tick-register "agent"`
  adds `"patch_job_create" "patch_job_status"`.
- `dl-satan-mode.el` — same two added to `self-edit-mech` and
  `self-edit-mind`.

Historic note: tool specs used to carry a `:modes` documentary list.
T4 deleted it; the mode-spec `:tools' allowlist is now the only
source of truth and `dl-satan-mode-check-tool-references' enforces
consistency at load.

## Op-cache path port (the big one)

Symptom of the day: `jailed-pi` wedged for 21 min — wrapper sat in
`op run` waiting for biometric.  Root cause: prior to this session
`jailed-pi` was built with `useOpEnv = true` (default) so its
wrapper script does:

```
exec op run --no-masking --env-file=llm-api-keys.env -- inner-pi …
```

The Emacs broker already side-steps this for `jailed-satan-gptel-
harness` (see `~/.emacs.d/flake.nix:206-218`).  The same shape is
now mirrored for `jailed-pi`:

```
~/.emacs.d/flake.nix     useOpEnv = false; passApiKeysFromEnv = true;
```

Emacs-side, `dl-satan-patch-adapter-pi.el` now pre-resolves the API
keys in `dl-satan-patch-adapter-pi-api-key-vars` (defaults: 7 keys)
via `my/op-read-env` and binds the resolved env as
`process-environment` for the spawn.  Any leftover `op://` refs
are scrubbed via `my/scrub-op-refs-env`.

Helper move:

- `dl-satan-broker--scrub-op-refs` → `my/scrub-op-refs-env` in
  `lisp/dl-secret.el` so the broker and adapter share it.  Broker
  call site delegates; ert renamed.

`home-manager switch` is required to pick up the rebuilt
`jailed-pi`.  The user runs Emacs from inside a direnv-managed
shell at `~/.emacs.d`; `direnv reload` rebuilds the devshell so
`which jailed-pi` resolves to the new (no-op-run) wrapper.

## Pi behavioural fixes

1. **stdin EOF.**  `pi --mode json --no-session -p DIRECTIVE` is
   non-interactive but still reads stdin and blocks on EOF.  CLI
   users get this via `< /dev/null`; `make-process' leaves stdin
   as an open pipe.  Adapter now does `(process-send-eof proc)`
   after spawn.  Symptom before fix: pi did 1s of CPU then sat in
   `epoll_wait' forever with zero syscalls.

2. **`--system-prompt-file` → `--system-prompt`.**  Pi 0.75.x
   dropped the file flag.  Adapter reads the prompt file inline
   and passes the contents via `--system-prompt`.  Prior semantics
   preserved (fully replaces pi's default coding-assistant prompt;
   `--append-system-prompt' would only append).

3. **Stderr persisted.**  Sentinel now writes pi's stderr to
   `<log-root>/<job_id>.stderr.log' before killing the buffer.
   Stdout was already at `<log-root>/<job_id>.jsonl'.

## Other small things

- `dl-satan-tools-atsatan--claimed-re' now matches
  `@satan-\(?:was-here\|done\)\b` — legacy claim token from before
  the rename in `bfea6c2f' is filtered upstream again.  Test added.
- Budget ceiling raised to 2M (was 800k) — long debugging session
  burned a lot of model tokens.

## Where things stand

Last observed acceptance run (`patch_20260520T195442_llvu`):

```
queued → claimed → preparing_worktree → running → failed
adapter error: pi exit 1 ("Unknown option: --system-prompt-file")
```

That `Unknown option` was the bug fix in 4cca6b40.  Subsequent runs
hit the next problem:

```
queued → claimed → preparing_worktree → running → failed
adapter error: "jailed-pi executable not found"
```

= the latent PATH-resolution miss.  See **Open issues** below.

A clean §4.6 acceptance has not been observed in this session.  The
prompts + mechanism + op-cache port should now be sufficient; the
PATH issue is the one remaining blocker for fully automated
end-to-end (manual-invocation works from a buffer that has
direnv-elisp's env loaded).

## Open issues

1. **PATH resolution for `jailed-pi`.**  The adapter currently
   relies on `executable-find` against the caller's `exec-path`.
   When invoked from a context without `~/.emacs.d` direnv loaded
   (emacsclient eval, a timer fire from a non-direnv buffer, the
   runner tick path under some conditions), `executable-find`
   returns nil and the adapter reports
   `jailed-pi executable not found` before spawning.

   Two unblock options:

   - Pin the absolute path:
     ```
     (setq dl-satan-patch-adapter-pi-program
           (string-trim
            (shell-command-to-string
             "direnv exec ~/.emacs.d which jailed-pi")))
     ```
     Brittle across rebuilds.

   - Land a resolver in
     `dl-satan-patch-adapter-pi.el' that, on first use, runs
     `direnv exec ~/.emacs.d which jailed-pi' and caches the
     absolute path; falls back to a defcustom override.  Started
     drafting this in the session — not committed.

2. **`patch_job_cancel' does not kill the process.**  Only
   updates the DB row to `cancelled`.  The runner's `_active`
   slot and the live bwrap process keep running until the timer
   timeout (1800s) or external `kill`.  Symptom: a queued job
   sits behind a cancelled-but-still-spawned ancestor and only
   runs after the timeout.

3. **Op popup count after Emacs restart.**  `my/op--cache` is
   per-Emacs-session, so the first tick post-restart prompts
   biometric for each `op://` ref in
   `dl-satan-patch-adapter-pi-api-key-vars`.  User saw 4 prompts.
   Tick #2+ is silent (cache hit).  Reduction options noted in
   chat: trim the var list, pre-warm on startup, or use `op
   signin` for a CLI session token (~10 min unlock).

4. **Empty stdout log on success.**  In a clean CLI run pi prints
   9 JSON lines (`session`, `agent_start`, `turn_start`,
   `message_start`, `message_end`, …).  In the adapter spawn,
   stdout reached pi's first message OK but the runner's
   `--system-prompt-file' bug aborted before more arrived.
   Re-test after the fixes — expectation is that stdout `.jsonl'
   now fills as pi turns.

5. **§4.6 acceptance still owed.**  Drive one real `@satan
   rewrite …' through tick → classify → patch_job_create →
   runner → pi → commit → inbox patch-ready.  Plan §4.6.

## Possible architectural pivot (the user raised it)

Mid-session the user mused: a separate supervisor process might
make more sense than Emacs-as-runner.

Current shape:

- Emacs broker is the only thing that ever spawns `jailed-pi'.
- The runner is a globally-singletonised callback chain
  (`dl-satan-patch-runner--active') driven by `make-process'
  sentinels.  Its PATH / `process-environment' inherits from
  whatever buffer triggered the kick.
- Cancel / timeout / cleanup are all in-process.

Alternative shape (sketch, not designed):

- A standalone supervisor process (Python / Go / Rust) tails
  `patch_jobs' (`FOR UPDATE SKIP LOCKED' is already in the
  schema), claims rows, prepares worktrees, runs `jailed-pi',
  streams JSONL to disk, updates state on terminal events.
- Emacs only writes rows (`patch_job_create' inserts; everything
  else becomes a thin SQL wrapper).
- Pros: PATH / env stability (the supervisor's environment is
  fixed at start, not at-each-kick); survives Emacs
  restart / crash; cancel is `kill <pid>' against an OS process
  the supervisor owns; testable in isolation; same broker → pi
  path can run from CI / cron / a tick that fires outside an
  Emacs session.
- Cons: another moving part, another systemd unit, another set
  of secrets to thread, another place a bug can hide.  Streaming
  logs back to the Emacs UI is a small protocol design.

If this pivot happens, the dl-satan-patch-runner.el and most of
dl-satan-patch-adapter-pi.el become a thin client.  The
worktree / store / prompt / classify modules are unaffected.
The inbox-handoff / atsatan integration code (in
`dl-satan-patch-inbox.el' and `dl-satan-tools-atsatan.el') is
unaffected as long as the runner-hook contract is preserved.

Worth a tiny ADR before committing either way; the in-Emacs
runner *does* work today with the bugs identified above patched.

## What the next agent should do, in order

1. **Read this file + the original
   `archive/handover-phase3-mechanism.md' + the plan §4.3-4.6.**

2. **Confirm `home-manager switch' has been run** so `jailed-pi'
   is the rebuilt no-op-run wrapper.  Quick check inside
   `~/.emacs.d`:
   ```
   readlink -f $(which jailed-pi)
   head -10 $(readlink -f $(which jailed-pi))
   ```
   The wrapper script should NOT contain `op run`.

3. **Drive one acceptance run from a buffer that has direnv
   loaded** — i.e. M-: in `dl-satan-patch-adapter-pi.el`:
   ```
   (dl-satan-tool/patch-job-create
    (list :directive "In satan/hello-world.txt write the single line 'hi'. Then commit."
          :mode "manual"
          :repo (expand-file-name "~/.emacs.d")
          :allowed_paths '("satan/")
          :start t)
    nil)
   ```
   Watch `~/.local/state/satan/patch-agent/logs/<job_id>.jsonl'
   fill; row should transition `running' → `needs_review' with
   commits + diffstat in `result_json'.  Inbox file should get a
   `patch-ready' headline.

4. **If step 3 succeeds**, ship the PATH resolver from §Open
   issues #1 so subsequent kicks from any context just work.

5. **If step 3 fails**, the `.stderr.log' sidecar (from
   4cca6b40) is your friend.  CLI flag drift in pi releases is
   now visible without bisecting.

6. **Surface the supervisor question** if step 4 is more than a
   one-commit fix.  This is the user's call, not yours.

## Don't

(In addition to the originals in
`archive/handover-phase3-mechanism.md::Don't`.)

- Don't `setq dl-satan-patch-adapter-pi-program` to a `/nix/store`
  path and commit it — paths change with every rebuild.  A
  defcustom override is fine; a hardcoded default is not.
- Don't strip `process-send-eof' from the adapter "to simplify."
  It is load-bearing — see fix 1 above.
- Don't move `my/scrub-op-refs-env' back into `dl-satan-broker'.
  Two callers now (broker, pi adapter); the helper is generic.

## File map (delta from previous handover)

```
~/.emacs.d/
  flake.nix                              jailed-pi: useOpEnv=false, passApiKeysFromEnv=true
  lisp/dl-secret.el                      + my/scrub-op-refs-env
  satan/
    dl-satan-broker.el                   delegate scrub to dl-secret
    dl-satan-budget.el                   ceiling 2M
    dl-satan-mode.el                     self-edit-{mech,mind} :tools + patch_job_*
    dl-satan-patch-adapter-pi.el         resolved-env, stdin EOF,
                                         --system-prompt, stderr sidecar
    dl-satan-tools-atsatan.el            tick-agent :tools + patch_job_*;
                                         claimed-re tolerates @satan-done
    test/dl-satan-test.el                require dl-secret;
                                         renamed scrub-op-refs test
    test/dl-satan-tools-atsatan-test.el  + legacy @satan-done filter test
~/notes/satan/prompts/
  tick/agent.txt                         + patch_job_create routing
  self-edit-mech.txt                     + patch lane defaults
  self-edit-mind.txt                     + patch lane defaults
```
