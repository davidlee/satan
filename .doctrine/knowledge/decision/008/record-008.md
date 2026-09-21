## The test, applied

POL-001: **does it use the editor as an editor?** The in-scope primitives it names are org-mode parsing and writing, denote naming, buffer manipulation, dired, `find-file`, `recentf`, interactive `satan-*` commands, `compile-angel` save hooks, ert as the natural test surface, and presenting to — or taking approval from — the human at the keeper's editor.

The three SL-016 modules:

| module | editor primitives used | verdict |
|---|---|---|
| goad day-file reader (evidence + canon rule) | none — file reads and a pure rule | No |
| ask tool (queue projection write, intervention emit) | none — file write and a DB row | No |
| doorbell (`goad-emit` shell-out) | none — `satan-trace-call` | No |

## Why the thin-shell precedent does not reach

A1 assumed `satan-tools-{notify,sway,activity,agenda}.el` were the precedent. The 2026-07-22 amendment is explicit about why those keep their seats:

> The seat is narrower than it reads. Most of these modules now touch the *files* of the org/denote substrate rather than its Emacs APIs — after SL-012 the tree holds almost no live `org-`/`denote`/`dired` call sites. **They earn the seat because the human's editing surface is where their output lands and where the keeper approves it**, not because they need an Emacs image to compute.

The rationale is the *destination of the output*, not the thinness of the shell. `notify_send` raises a notification the keeper sees beside their editor; `sway_border_set` paints the frame around it. goad renders in its own window, under its own host, with its own interaction model. The precedent's load-bearing clause does not extend there.

This is also why the fix is not to argue harder. The seat clause genuinely does not contemplate a second human surface that is not the editor. That gap is real and predates this slice.

## No is not the same as now

POL-001's No branch: *"it is in elisp only because the broker spawned there: an incidental tenant, **eligible for extraction when carving becomes cheaper than hosting it**."* Eligible, not due. The Verification section then gates it:

> Trigger a candidate's extraction when **one** applies, not before: (1) surface about to grow materially in the next refactor theme; (2) a recurring bug traces to language/runtime fit; (3) a contributor is asked to read elisp to evaluate non-elisp work; (4) tests begin to dominate `emacs --batch` CI cost. **Absent any trigger, leave it.**

None fires. (2) deserves a note, since JSON walking is one of the named language-fit costs and DEC-008 puts SATAN on a JSON day file — but a *recurring bug* is the trigger, and there is no bug in code not yet written. If one recurs, the trigger fires then, and this ruling is the record that makes that a one-line argument rather than a re-litigation.

## What is deliberately not done here

The seat clause is **not** widened. Doing so in a slice design would be governance by implementation. It is logged as a revision candidate for `/reconcile` at close, alongside the two stale-boot-snapshot items research already found.