---
name: at-satan-design
description: AT-SATAN — `@satan` agent-trigger tooling design
metadata:
  type: design
  topic: satan-at
  status: draft
  updated_at: 03398479
  verified_at: 03398479
---

# AT-SATAN: `@satan` agent-trigger tooling

## Overview

SATAN needs a way to discover `@satan` directives placed in the user's
notes, act on them, and mark them as done so they do not reappear in
subsequent scans. `@satan` is a lightweight convention — a line in any
`.org` or `.md` file under `~/notes/` (outside `~/notes/satan/`) that
instructs SATAN to perform some action on the surrounding context.

This document is **design + implementation spec**. The design half
(below) is complete: every formerly open question is resolved, every
elisp form is eval-able, and the model-facing artifacts are quoted
verbatim. The Implementation guide section at the bottom is the build
order and file-by-file recipe.

---

## The `@satan` convention

A line in any user note that matches the substring `@satan`
(case-sensitive). Examples:

```org
- @satan summarise the three points above this line
- @satan check if the bough tree for this project has any overdue items
When you see this note, @satan follow the maintenance steps in the code block below
```

The line is not a function call — it is a prose directive that the LLM
interprets in the context of the document excerpt. The surrounding
content (which lines are returned) is the document's natural context:
the paragraph containing `@satan`, the headline/subtree, and a fixed
window of adjacent lines.

A line claimed by a previous run carries `@satan-was-here` in place of
the bare `@satan`, followed by a quoted block holding the run-id and a
summary comment. Org files use `#+BEGIN_QUOTE`/`#+END_QUOTE`; markdown
files use `> `-prefixed lines. The scan filters claimed lines out.

Render example (org):

```org
- @satan-was-here summarise the three points above this line
  #+BEGIN_QUOTE satan 20260520T125209-tick-agent-259270,inbox_append
  your 12:15 blood test already passed; today is packed; go tomorrow
  #+END_QUOTE
```

---

## Tool: `notes_at_satan_scan`

### File header and dependencies

```elisp
;;; satan-tools-atsatan.el --- @satan scan + done tool handlers -*- lexical-binding: t; -*-

;; Scans ~/notes/ for @satan references and returns excerpts with
;; context (`notes_at_satan_scan'); marks a directive done by replacing
;; the @satan token with @satan-was-here and appending a quoted block
;; carrying the run-id + summary comment (`notes_at_satan_done').
;;
;; Risk model:
;;   - notes_at_satan_scan : risk read; no capability required.
;;   - notes_at_satan_done : risk low;  requires 'write-notes capability.

(require 'cl-lib)
(require 'subr-x)
(require 'json)
(require 'dl-notes-paths)
(require 'satan-tools)
(require 'satan-tick)  ; for satan-tick-register at load time

(defcustom satan-tools-atsatan-root
  dl-notes-root
  "Root directory the @satan scan searches under."
  :type 'directory :group 'satan)

(defcustom satan-tools-atsatan-default-context-lines 3
  "Default lines of context above and below each @satan match."
  :type 'integer :group 'satan)

(defconst satan-tools-atsatan--context-max 20
  "Hard upper bound on context lines; clamped without error.")

(defconst satan-tools-atsatan--results-max 200
  "Hard upper bound on results returned in a single scan.")

(defconst satan-tools-atsatan--exclude-globs
  '("!satan/**")
  "Glob exclusions passed to rg as repeated --glob flags.")

(defconst satan-tools-atsatan--default-path-glob "*.{org,md}"
  "Default rg glob for files to scan.")

(defconst satan-tools-atsatan--mark "@satan"
  "Substring matching an active @satan directive.")

(defconst satan-tools-atsatan--done-re "@satan-done\\b"
  "Regex marking a claimed @satan line; excluded from results.")

(defconst satan-tools-atsatan--headline-re
  "^\\(\\*+\\|#+\\) "
  "Org-or-markdown heading line; walked backward from each match.")

(defvar satan-tools-atsatan--rg-program "rg"
  "Name (or absolute path) of the ripgrep binary. Overridable for tests.")
```

### Schema

```elisp
(satan-tool-register
 (list :name "notes_at_satan_scan"
       :risk 'read
       :args-schema '(context-lines (:type integer :required nil)
                      max-results   (:type integer :required nil)
                      path-glob     (:type string  :required nil))
       :handler 'satan-tool/notes-at-satan-scan))
```

| Arg | Type | Required | Default | Notes |
|-----|------|----------|---------|-------|
| `context-lines` | integer | no | 3 | Lines above/below each match. Clamped 0..20. |
| `max-results`   | integer | no | 30 | Max matches returned. Clamped 1..200. |
| `path-glob`     | string  | no | `*.{org,md}` | rg `--glob` pattern. |

### Backend: ripgrep JSON

`rg --json` emits one NDJSON record per line. Each record's `.type`
classifies it; only `match` records are interesting.

Locked field map:

| Field | JSON path |
|---|---|
| File path | `.data.path.text` |
| Line number (1-based) | `.data.line_number` |
| Matched line text | `.data.lines.text` |

Invocation:

```
rg --json -n --fixed-strings @satan
   --glob '!satan/**'
   --glob '*.{org,md}'
   --max-count <max-results>
   <root>
```

Stderr captured via temp file; stdout collected in a buffer — same
plumbing as `satan-tools-notes--run-fd`. The NUL handling pattern
from `--run-fd` does **not** transfer to rg.

### Context window: in-elisp slice

`rg -A/-B` emits `type=context` records that must be re-associated to
their preceding match — fragile across record orderings. Instead, after
parsing the match list, open each match's file once (cache the buffer
by path), take lines `(line - N) .. (line + N)`, join with `\n`. The
buffer walk also serves the headline lookup; one open per file.

### Headline walk-up

Walk backward from the match line for the first occurrence of
`^\(\*+\|#+\) `. Return the matched heading text (sigil included) so the
LLM sees `** Maintenance` vs `## Maintenance` and can infer document
structure. Return `nil` if neither found.

### Handler

```elisp
(defun satan-tools-atsatan--clamp (raw default min max)
  (cond ((null raw) default)
        ((< raw min) min)
        ((> raw max) max)
        (t raw)))

(defun satan-tools-atsatan--hash (file line)
  "Stable id for a (FILE . LINE) pair within a single scan cycle.
Hash shifts if lines above the match are inserted/deleted, so callers
must round-trip the id within one scan-then-done cycle."
  (concat "M-" (substring (secure-hash 'md5 (format "%s:%d" file line)) 0 12)))

(defun satan-tools-atsatan--rg-argv (max-results path-glob)
  (let ((argv (list "--json" "-n" "--fixed-strings"
                    "--max-count" (number-to-string max-results)
                    "--glob" path-glob)))
    (dolist (g satan-tools-atsatan--exclude-globs)
      (setq argv (append argv (list "--glob" g))))
    (append argv
            (list satan-tools-atsatan--mark
                  satan-tools-atsatan-root))))

(defun satan-tools-atsatan--run-rg (argv)
  "Invoke rg with ARGV. Returns (:exit N :stdout STR :stderr STR)."
  (let ((stdout-buf (generate-new-buffer " *satan-atsatan-rg-out*"))
        (stderr-file (make-temp-file "satan-atsatan-rg-err-")))
    (unwind-protect
        (let ((exit (apply #'call-process
                           satan-tools-atsatan--rg-program nil
                           (list stdout-buf stderr-file) nil argv)))
          (list :exit exit
                :stdout (with-current-buffer stdout-buf (buffer-string))
                :stderr (with-temp-buffer
                          (when (file-readable-p stderr-file)
                            (insert-file-contents stderr-file))
                          (buffer-string))))
      (when (buffer-live-p stdout-buf) (kill-buffer stdout-buf))
      (when (file-exists-p stderr-file) (delete-file stderr-file)))))

(defun satan-tools-atsatan--parse-matches (stdout)
  "Parse rg --json STDOUT into a list of (:file :line :content) plists.
Skips non-match records and lines containing @satan-done."
  (let (out)
    (dolist (raw (split-string stdout "\n" t))
      (let* ((rec (ignore-errors
                    (json-parse-string raw :object-type 'plist
                                       :array-type 'list
                                       :null-object nil)))
             (type (and rec (plist-get rec :type)))
             (data (and rec (plist-get rec :data))))
        (when (and (equal type "match") data)
          (let* ((path (plist-get (plist-get data :path) :text))
                 (line (plist-get data :line_number))
                 (text (plist-get (plist-get data :lines) :text))
                 (content (and text (string-trim-right text))))
            (when (and path line content
                       (not (string-match-p satan-tools-atsatan--done-re
                                            content)))
              (push (list :file path :line line :content content)
                    out))))))
    (nreverse out)))

(defun satan-tools-atsatan--enrich (matches context-lines)
  "Add :context, :headline, :mtime, :id to each match plist.
Opens each unique file once; reads lines into a vector for slicing."
  (let ((cache (make-hash-table :test 'equal)))
    (mapcar
     (lambda (m)
       (let* ((file  (plist-get m :file))
              (line  (plist-get m :line))
              (lines (or (gethash file cache)
                         (puthash file
                                  (with-temp-buffer
                                    (let ((coding-system-for-read 'utf-8))
                                      (insert-file-contents file))
                                    (vconcat (split-string (buffer-string) "\n")))
                                  cache)))
              (n     (length lines))
              (idx   (1- line))
              (lo    (max 0 (- idx context-lines)))
              (hi    (min (1- n) (+ idx context-lines)))
              (window (cl-loop for i from lo to hi
                               collect (aref lines i)))
              (headline (cl-loop for i from (1- idx) downto 0
                                 for ln = (aref lines i)
                                 when (string-match-p
                                       satan-tools-atsatan--headline-re ln)
                                 return ln))
              (mtime (format-time-string
                      "%Y-%m-%dT%H:%M:%S%z"
                      (file-attribute-modification-time
                       (file-attributes file)))))
         (append m
                 (list :context (mapconcat #'identity window "\n")
                       :headline headline
                       :mtime mtime
                       :id (satan-tools-atsatan--hash file line)))))
     matches)))

(defun satan-tool/notes-at-satan-scan (args _ctx)
  "Implements notes_at_satan_scan. Returns (ok PLIST) | (error STR)."
  (let* ((ctx-lines (satan-tools-atsatan--clamp
                     (plist-get args :context-lines)
                     satan-tools-atsatan-default-context-lines
                     0 satan-tools-atsatan--context-max))
         (max-res   (satan-tools-atsatan--clamp
                     (plist-get args :max-results)
                     30 1 satan-tools-atsatan--results-max))
         (glob      (or (plist-get args :path-glob)
                        satan-tools-atsatan--default-path-glob))
         (argv      (satan-tools-atsatan--rg-argv max-res glob))
         (run       (satan-tools-atsatan--run-rg argv))
         (exit      (plist-get run :exit)))
    (cond
     ;; rg exits 1 when no matches; that is success-with-empty for us.
     ((not (memql exit '(0 1)))
      (cons 'error (format "rg failed: exit=%s %s"
                           exit (string-trim (plist-get run :stderr)))))
     (t
      (let* ((raw     (satan-tools-atsatan--parse-matches
                       (plist-get run :stdout)))
             (capped  (if (> (length raw) max-res)
                          (cl-subseq raw 0 max-res)
                        raw))
             (truncated (> (length raw) max-res))
             (enriched (satan-tools-atsatan--enrich capped ctx-lines)))
        (satan-tools-atsatan--remember enriched)
        (cons 'ok
              (list :scope "notes_at_satan_scan"
                    :root satan-tools-atsatan-root
                    :context-lines ctx-lines
                    :max-results max-res
                    :count (length enriched)
                    :truncated truncated
                    :matches enriched)))))))
```

### Worked output example

Two `@satan` hits, one in an org file under a `** Maintenance` headline,
one in a markdown file under `## Onboarding`. After JSON conversion the
LLM sees:

```json
{
  "scope": "notes_at_satan_scan",
  "root": "/home/david/notes/",
  "context_lines": 3,
  "max_results": 30,
  "count": 2,
  "truncated": false,
  "matches": [
    {
      "file": "/home/david/notes/journal/20260519.org",
      "line": 42,
      "content": "- @satan summarise the three points above this line",
      "context": "Three things I want to remember:\n1. addressability\n2. resonance loop\n3. visible wrongness\n- @satan summarise the three points above this line\n",
      "headline": "** Maintenance",
      "mtime": "2026-05-19T07:30:00+0100",
      "id": "M-d3a2f17b8c4e"
    },
    {
      "file": "/home/david/notes/projects/foo.md",
      "line": 17,
      "content": "@satan follow the maintenance steps in the code block below",
      "context": "## Onboarding\n\nWhen you see this note, @satan follow the maintenance steps in the code block below\n\n```sh",
      "headline": "## Onboarding",
      "mtime": "2026-05-17T11:02:11+0100",
      "id": "M-9c41a08bd2e1"
    }
  ]
}
```

The `id` field is the stable anchor for the round-trip into
`notes_at_satan_done` within the same scan cycle.

---

## Tool: `notes_at_satan_done`

### Schema

```elisp
(satan-tool-register
 (list :name "notes_at_satan_done"
       :risk 'low
       :args-schema '(match-id (:type string :required t)
                      comment  (:type string :required nil))
       :handler 'satan-tool/notes-at-satan-done))
```

| Arg | Type | Required | Description |
|-----|------|----------|-------------|
| `match-id` | string | yes | The `:id` from a `notes_at_satan_scan` entry. |
| `comment`  | string | no  | Short summary recorded in the claim block. Split on the first `:` — left becomes a tag appended to the block header (after the run-id, comma-separated), right becomes the body. No colon → whole string is body, header has no tag. |

### Handler (verbatim — the subtle bit)

Single-file in-place line edit with optimistic re-read.

```elisp
(defvar satan-tools-atsatan--id-index (make-hash-table :test 'equal)
  "Maps :id → (FILE . LINE) within a single Emacs session.
Populated by the scan handler so the done handler does not need to
re-scan to resolve an id.")

(defun satan-tools-atsatan--remember (matches)
  "Store FILE/LINE for each match's id in the session index."
  (dolist (m matches)
    (puthash (plist-get m :id)
             (cons (plist-get m :file) (plist-get m :line))
             satan-tools-atsatan--id-index)))

(defun satan-tools-atsatan--marker (run-id comment)
  "Build `@satan-done(<run-id>[,<comment>])'. Strips parens/newlines from comment."
  (let ((c (and comment
                (replace-regexp-in-string "[()\n\r]" " " comment))))
    (if (and c (not (string-empty-p (string-trim c))))
        (format "@satan-done(%s,%s)" (or run-id "") (string-trim c))
      (format "@satan-done(%s)" (or run-id "")))))

(defun satan-tools-atsatan--rewrite-line (file line marker)
  "Replace the first `@satan' on LINE of FILE with MARKER.
Optimistic re-read: if the line no longer contains a bare `@satan' (or
already contains `@satan-done'), return :status \"already-done\". Other
content on the line is preserved."
  (let ((coding-system-for-read 'utf-8)
        (coding-system-for-write 'utf-8))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (forward-line (1- line))
      (let* ((line-start (point))
             (line-end   (line-end-position))
             (current    (buffer-substring-no-properties line-start line-end))
             (id         (satan-tools-atsatan--hash file line)))
        (cond
         ((string-match-p satan-tools-atsatan--done-re current)
          (cons 'ok (list :match-id id :status "already-done")))
         ((not (string-match-p (regexp-quote satan-tools-atsatan--mark)
                               current))
          (cons 'ok (list :match-id id :status "already-done")))
         (t
          (let ((replaced
                 (replace-regexp-in-string
                  (regexp-quote satan-tools-atsatan--mark)
                  marker current t t nil 1)))
            (delete-region line-start line-end)
            (goto-char line-start)
            (insert replaced)
            (write-region (point-min) (point-max) file nil 'silent)
            (cons 'ok (list :match-id id :status "done")))))))))

(defun satan-tool/notes-at-satan-done (args ctx)
  "Implements notes_at_satan_done. Returns (ok PLIST) | (error STR).
Refused unless TOOL-CTX `:capabilities' includes `write-notes'.
Idempotent: claiming an already-done line returns :status \"already-done\"."
  (let* ((id      (plist-get args :match-id))
         (comment (plist-get args :comment))
         (caps    (plist-get ctx :capabilities))
         (run-id  (plist-get ctx :id))
         (pair    (gethash id satan-tools-atsatan--id-index)))
    (cond
     ((not (memq 'write-notes caps))
      (cons 'error "mode lacks capability write-notes"))
     ((not (stringp id))
      (cons 'error "match-id must be string"))
     ((null pair)
      (cons 'error (format "unknown match-id: %s (no prior scan in this session)" id)))
     ((not (file-exists-p (car pair)))
      (cons 'error (format "file no longer exists: %s" (car pair))))
     (t
      (let* ((file (car pair))
             (line (cdr pair))
             (marker (satan-tools-atsatan--marker run-id comment)))
        (satan-tools-atsatan--rewrite-line file line marker))))))
```

Notes on the handler:

- The id index is **per-Emacs-session**, not persisted. A tick-agent run
  always scans before claiming, so the lookup is populated. A morning
  run scans without claiming (write capability absent) and the index
  entries are harmless.
- Only the first `@satan` on the line is replaced. A line with
  multiple `@satan` tokens (rare; malformed) claims one at a time.
- Idempotency: a second call against a line that already bears
  `@satan-was-here` returns `:status "already-done"` without rewriting
  the file.
- The embedded code excerpts in this section are a snapshot; the
  canonical source is `satan/satan-tools-atsatan.el`.

### Why not delete the line outright?

1. **Audit trail.** `@satan-was-here` plus the appended quote block
   lets a human grep for what SATAN has processed, when (run-id), and
   what it did (block body).
2. **Idempotency.** Filtering out `@satan-was-here` lines at scan time
   is load-bearing; deleting would make absence the only signal, which
   is fragile against backups, undo, or re-imports.
3. **User trust.** Replacing in place with a completion marker is
   honest and reversible. Deletion is not.

### Run-id source

Read from `(plist-get tool-ctx :id)`. The broker populates this at
`satan-broker.el:107` (`:id (satan-run-id run-ctx)`) when it
builds the tool-ctx for each handler invocation.

---

## Mode: `tick-agent`

Registered via `satan-tick-register`:

```elisp
(satan-tick-register
 "agent"  ; → full mode name "tick-agent"; prompt at <prompts>/tick/agent.txt
 :tools '("notes_at_satan_scan" "notes_at_satan_done"
          "org_read_context"
          "inbox_append"
          "hippocampus_write"
          "memory_mark" "memory_resonate" "memory_show_trace"
          "bough_read"
          "agenda_read")
 :capabilities '(write-notes inbox-write memory-write)
 :budget-tokens 60000
 :budget-tool-calls 15
 :timeout-seconds 120)
```

Note the short-name / full-name convention: `satan-tick-register`
prepends `tick-` and resolves the prompt file to
`<prompts>/tick/<short>.txt`. So short-name `"agent"` produces mode
`tick-agent` and reads the prompt from
`~/notes/satan/prompts/tick/agent.txt`.

### `write-notes` capability

New capability symbol. Checked in the done handler via
`(memq 'write-notes (plist-get ctx :capabilities))` — the same pattern
the org and inbox handlers use. The broker passes mode `:capabilities`
through as a symbol list at `satan-broker.el:109`. No central
capability registry exists yet; that is a future refactor noted at the
end of this document.

### Tick pool weights

Edit the `satan-tick-pool` defcustom default to:

```elisp
(defcustom satan-tick-pool
  '(("tick-pulse" . 5)
    ("tick-agent" . 3))
  ...)
```

**Customisation note.** Users with `M-x customize` overrides will not
pick up the new entry from a default change; re-add manually.

### Morning mode integration

Add `notes_at_satan_scan` (but **not** `notes_at_satan_done`) to the
morning mode's `:tools` list in `satan-mode.el`. Anchor: the
`(list :name "morning" ...)` form's `:tools` key. Morning gets the
read-only scan so SATAN can surface outstanding directives in the
morning summary; write-back stays in `tick-agent`.

---

## Model-facing tool descriptions

### `~/notes/satan/tools/notes_at_satan_scan.md`

```markdown
Search every document under the user's notes corpus for lines
containing `@satan` — a directive instructing you to perform an action
on the surrounding context. These are user-authored triggers placed in
journal entries, project notes, or reference documents.

Each result entry provides the file path, line number, the matching
line, a window of surrounding context lines, the org or markdown
headline the line falls under, and a stable `id`. Pass `id` directly to
`notes_at_satan_done` when you have acted on the directive.

Use this tool to discover what the user wants you to do. Read the
context. Perform the action via your other tools (read more file
context if needed, write an inbox entry with results, mark a memory
trace, stage a proposal). Then call `notes_at_satan_done` with the
`id` to claim the directive. Do not claim a directive you did not
actually act on.

Lines already bearing `@satan-was-here` are excluded automatically.
If a directive is ambiguous, skip it — do not guess. If a directive
needs a tool you do not have access to in this mode, write a
hippocampus entry noting the gap and leave the directive unclaimed.
```

### `~/notes/satan/tools/notes_at_satan_done.md`

```markdown
Mark a `@satan` directive as completed. Takes the `id` from a
`notes_at_satan_scan` result entry and an optional `comment`
summarising what you did.

Effect: replaces `@satan` on the matched line with `@satan-was-here`
(preserving the rest of the line) and inserts a quoted summary block
below it carrying the run-id and `comment`. The `comment` is split on
the first `:` — left becomes a tag in the block header (after the
run-id, comma-separated), right becomes the body. The directive will
not appear in future `notes_at_satan_scan` results.

Example: `comment = "inbox_append: noted three open items"` →

```org
@satan-was-here <rest of line>
#+BEGIN_QUOTE satan <run-id>,inbox_append
noted three open items
#+END_QUOTE
```

Call this immediately after acting on the directive — do not batch
claims at the end of your run. Claim only directives you have actually
handled. If the line has already been claimed by another run, the
result returns `status: already-done` and no rewrite happens; this is
not an error.
```

---

## Tick-agent prompt (verbatim)

Goes at `~/notes/satan/prompts/tick/agent.txt`. This is the behavioural
frame for the entire mode — the highest-leverage artifact in this
effort.

```text
You are SATAN's tick-agent. Your one job per run: find any active
`@satan` directives in the user's notes and act on them.

DEFAULT FLOW

1. Call `notes_at_satan_scan` exactly once at the start of the run.
   Use default arguments unless you have a reason. Do not re-scan
   mid-run; the result you have is sufficient for one tick.

2. For each match, in the order returned:
   a. Read the `context` and `headline` fields. They are usually enough.
   b. If the directive references work elsewhere (a project file, a
      different headline), call `org_read_context` to expand the
      relevant subtree. Do this only when the scan context is
      insufficient — not by reflex.
   c. Perform the action using the registered tools available to you:
        - summarise / report → `inbox_append`
        - durable observation → `memory_mark` (typed hints only;
          do not invent handles)
        - related prior context → `memory_resonate` before acting
        - durable semantic note → `hippocampus_write`
        - check overdue items → `bough_read`, `agenda_read`
   d. Immediately call `notes_at_satan_done` with the match `id` and a
      one-line `comment` describing what you did. Do not batch claims.

3. After all matches are claimed (or skipped), terminate with
   `satan_final`. The summary should list which ids you acted on and
   which you skipped, with one-line reasons for skips.

DISCIPLINE

- Scan first, act second. One scan per run.
- Claim each immediately after acting. Do not let a tick end with
  unclaimed directives you acted on.
- Prefer existing tools. The right tool almost always exists. If it
  does not, write a hippocampus entry naming the gap and skip the
  directive (do not claim it).
- Skip ambiguous directives. Do not guess what the user meant. A
  skipped directive will appear again next tick; a claimed directive
  with a wrong action wastes user trust.
- No side effects without a tool call. The `satan_final` summary is
  for audit. Do not embed instructions to the user there; surface them
  via `inbox_append`.
- If memory influenced the action, expose the matched reason in the
  comment passed to `notes_at_satan_done` ("rings prior trace: X").

TONE

Adversarially intimate, not managerial. Name the pressure only when it
changes the next action. Terse, dry, operational.

Most ticks will find no matches. That is normal. Return immediately
with `satan_final` summarising "no @satan directives".
```

---

## Claim lifecycle summary

```
User writes "@satan summarise the maintenance steps" in daily note.
                                │
                                ▼
         tick-agent run fires ──┤
                                │
                                ▼
    notes_at_satan_scan  ──►  returns { file, line, id, context, headline }
                                │
                                ▼
        LLM reads context, performs action (e.g. inbox_append with the
        summarised steps, or memory_mark for an observed pattern)
                                │
                                ▼
        notes_at_satan_done(id, "summarised 4 maintenance steps")
                                │
                                ▼
   File updated: "@satan-was-here …" + quote block
                  carrying run-id and "summarised 4 maintenance steps".
   Next scan: excluded by the @satan-was-here filter.
```

---

## Future tools (design sketch, not v1)

### Tool: `background_enqueue`

In some runs SATAN may want to defer work — e.g. a web fetch that takes
time, or a computation that must run after a dependency resolves.
Rather than blocking the harness, SATAN could enqueue a background
task that fires as a subsequent SATAN run.

**Schema sketch:**

```elisp
:name "background_enqueue"
:risk 'low
:args-schema '(mode-name (:type string :required t
                          :enum ("tick-agent" "self-edit-mind" ...))
                prompt   (:type string :required t)
                context  (:type string :required nil))
```

The handler writes a record under `~/notes/satan/pending/` (one file
per enqueued task). A companion systemd timer or a `satan-tick`
adapter checks for pending items and spawns them. Pending directory
gitignored and cleaned after dispatch. Enqueued runs carry
`trace_origin = background_enqueue` in the memory store for audit.

**Not in v1** — requires a pending-task watcher, a new directory, and
careful idempotency (two enqueues of the same task should not
duplicate).

### Tool: `web_fetch`

SATAN needs read-only access to URLs to follow links or resolve
references found in notes. Downloads a URL and returns its content as
markdown or plain text.

**Schema sketch:**

```elisp
:name "web_fetch"
:risk 'read
:args-schema '(url       (:type string :required t)
                mode      (:type string :required nil
                           :enum ("markdown" "text" "html"))
                max-chars (:type integer :required nil))
```

Backend: shell-out to `pandoc` / `readability-cli` / `lynx -dump` or a
lightweight Python script.

**Not in v1** — the jailed harness needs network access (bwrap
`--ro-bind /etc/resolv.conf` and `--share-net`), a backend choice, and
careful timeout + truncation.

---

## Resolved design decisions

| Question | Decision | Rationale |
|---|---|---|
| Separate scan and done tools? | Yes | Scan is `:risk 'read`; done is `:risk 'low` + write-notes capability. Splitting keeps the risk model honest and lets morning offer the scan without the write-back. |
| Hash function | `(secure-hash 'md5 (format "%s:%d" file line))` → first 12 hex | Deterministic, built-in to Emacs 30.2, no dep. 48 bits comfortable for ≤200 results. |
| Hash stability | Single-scan-cycle only | `(file . line)` shifts under edits that insert/delete above the match line. Do not use as a cross-run anchor. |
| `rg` vs `fd`+`grep` | `rg --json -n --fixed-strings @satan` | rg already standard in the Nix env; JSON output avoids cascaded split bugs around colons/NULs. |
| `rg --json` field map | path = `.data.path.text`; line = `.data.line_number`; content = `.data.lines.text`; filter `.type == "match"` | Locks the parse surface so the elisp doesn't drift on rg version bumps. |
| Exclude `satan/` dir | `--glob '!satan/**'` (extensible via `satan-tools-atsatan--exclude-globs`) | Single mechanism for exclusions; matches the `satan-tools-notes--exclude` pattern. |
| Exclude `@satan-was-here` lines | Post-parse elisp filter via `string-match-p` | Pipe-through-grep breaks NUL/JSON framing; PCRE lookahead is PCRE-only with `-P`. |
| Context window | In-elisp line slice from the file buffer (±N around `:line`) | rg context records are fragile to re-associate; buffer already opened for headline walk-up. |
| Headline walk-up | Regex `^\(\*+\|#+\) ` (org and markdown) | Single mechanism. Return sigil-inclusive text so the LLM sees the level. |
| Concurrent claim of same line | Optimistic re-read; if already `@satan-was-here`, return `:status "already-done"` | Idempotent. No error on race. |
| Concurrent edit of different lines in same file | Accepted limitation for v1 | Probability near zero under 30-min systemd timer. Future: `make-lock-file`. |
| `write-notes` capability | New symbol, checked in handler via `(memq 'write-notes (plist-get ctx :capabilities))` | Matches `inbox-write` / `write-daily` pattern at `satan-tools-inbox.el:51` and `satan-tools-org.el:73-76`. Capabilities are symbols at the handler interface (broker propagates them at `satan-broker.el:109`); they are stringified only for harness/LLM-facing JSON metadata at `satan-broker.el:266-267`. |
| Run-id source for marker | `(plist-get tool-ctx :id)` populated at `satan-broker.el:107` | Avoids the green-implementer fumble looking for it in run-state or env. |
| Default path glob | `*.{org,md}`, overridable via `:path-glob` | Limits scan to text formats; binary files (.pdf, .png) excluded by default. |
| `@satan` inside code blocks | Included in results; LLM uses judgment | Avoids a parser; tick-agent prompt instructs skipping ambiguous matches. |
| Soft truncation | `:truncated t` flag when result count clamps | LLM can narrow via `:path-glob` or raise `:max-results` next run. |
| Require chain | `satan-tools-atsatan` requires after `satan-tick` in `satan.el` | Tools file calls `satan-tick-register` at load time. |
| Mode short-name vs full name | `satan-tick-register "agent"` → mode `tick-agent`, prompt `<prompts>/tick/agent.txt` | Convention enforced by `satan-tick-register`. |
| Test fixture shape | `make-temp-file ... 'dir` + `let`-bound `satan-tools-atsatan-root` + `unwind-protect` cleanup | Keeps `~/notes/` clean during ert. |
| Verify command | `emacs -batch -l ert -l <test> --eval '(ert-run-tests-batch-and-exit "notes-at-satan-")'` | Non-zero exit + stdout output on failure. emacsclient eval swallows results. |

---

## Design invariants

1. **The `@satan` convention is plain-text, not a DSL.** No parser, no
   grammar. The LLM interprets the line in context. Trivial mechanism,
   minimal bug surface.
2. **Claim is idempotent.** Two `notes_at_satan_done` calls for the
   same line produce the same observable result (second is a no-op
   with `:status "already-done"`).
3. **Claim is audit-traced.** Every claim leaves a visible
   `@satan-was-here` token plus a quote block carrying the run-id and
   summary in the user's note, and is logged in the run's audit
   bundle. No silent state mutation.
4. **Scan is cheap.** `rg` over a notes corpus with <10K files takes
   under 500ms. The scan is one of the cheapest tool calls SATAN can
   make.
5. **Mode scope is narrow.** `tick-agent` only has scan + claim +
   supporting tools. No `org_update_owned_block`, no `notify_send`.
   If the agent needs to notify, it writes an inbox entry. This
   prevents runaway writes to daily notes during agent ticks.
6. **No new external dependencies.** `rg` is already in the Nix env;
   `secure-hash`, `json-parse-string` are built-in to Emacs 30.2.
7. **Inter-file concurrency: known limitation.** Two ticks editing
   different lines of the same file concurrently can lose a claim —
   each reads the full file, edits one line, writes whole file; last
   write wins. Probability near zero under the 30-min systemd timer.
   Document and revisit if it bites.

---

## Future-proofing: tool-level capability metadata

The `background_enqueue` and `web_fetch` tools share a requirement:
they admit new capability symbols. The current system checks
capabilities via `(memq need caps)` in a handful of handlers (e.g.
`org_update_owned_block` checks `write-daily`,
`inbox_append` checks `inbox-write`, `notes_at_satan_done` checks
`write-notes`). As the tool surface grows, consider:

1. A central capability registry (list of known symbols + docstrings).
2. A `:capability` key in the tool-spec itself, checked automatically
   by `satan-tool-dispatch` before the handler runs — removing the
   ad-hoc `(memq ...)` checks from individual handlers.
3. A per-capability allowlist in the mode spec: not just which tools,
   but which capabilities the mode is *allowed* to use (so a mode can
   carry a tool but still be blocked from a specific capability).

The last two are out of scope for this document but worth flagging in
AGENTS.md if/when the capability surface grows beyond ~8 symbols.

---

# Implementation guide

This section is the actionable build order. Phase B above has resolved
every design question; the work below is mechanical.

## Verbatim-content scope

These artifacts are quoted verbatim above and must be reproduced
exactly:

- The tick-agent prompt (`~/notes/satan/prompts/tick/agent.txt`).
- `satan-tool/notes-at-satan-done` and its helpers
  (`--marker`, `--rewrite-line`, `--id-index`, `--remember`).
- The model-facing `.md` descriptions for both tools.

Other artifacts (scan handler, ert tests, registration forms) are
described in enough detail that the implementer can produce them
straight from the spec above.

## Files to create

| Path | Contents |
|---|---|
| `satan/satan-tools-atsatan.el` | All elisp shown in this document, in declaration order: header → defcustoms/defconsts → helpers (`--clamp`, `--hash`, `--rg-argv`, `--run-rg`, `--parse-matches`, `--enrich`, `--id-index`, `--remember`) → scan handler → done helpers (`--marker`, `--rewrite-line`) and the done handler → two `satan-tool-register` forms → one `satan-tick-register` form → `(provide 'satan-tools-atsatan)`. |
| `satan/test/satan-tools-atsatan-test.el` | Ert suite (5 tests, see below). |
| `~/notes/satan/tools/notes_at_satan_scan.md` | Verbatim from above. |
| `~/notes/satan/tools/notes_at_satan_done.md` | Verbatim from above. |
| `~/notes/satan/prompts/tick/agent.txt` | Verbatim from above. |

## Files to modify

| Path | Anchor | Change |
|---|---|---|
| `satan/satan.el` | The block of `(require 'satan-tools-*)` lines, **after** `(require 'satan-tick)` | Insert `(require 'satan-tools-atsatan)`. Order matters: tick must load first. |
| `satan/satan-mode.el` | The `(list :name "morning" ...)` form's `:tools` list | Add `"notes_at_satan_scan"` (not `_done`). |
| `satan/satan-tick.el` | `defcustom satan-tick-pool` form | Change default to `'(("tick-pulse" . 5) ("tick-agent" . 3))`. |

## Ert test plan

One verbatim round-trip test plus four described.

### Verbatim round-trip test

```elisp
(require 'ert)
(require 'satan-tools-atsatan)

(defmacro satan-tools-atsatan-test--with-root (root-sym &rest body)
  "Bind ROOT-SYM to a fresh temp dir, let-bind it as the scan root, cleanup on exit."
  (declare (indent 1))
  `(let* ((,root-sym (make-temp-file "satan-atsatan-test-" 'dir))
          (satan-tools-atsatan-root ,root-sym))
     (unwind-protect (progn ,@body)
       (delete-directory ,root-sym 'recursive))))

(ert-deftest notes-at-satan/scan-then-done-then-rescan ()
  "Full round-trip: scan finds a match, done claims it, rescan excludes it."
  (satan-tools-atsatan-test--with-root root
    (let* ((file (expand-file-name "trip.org" root))
           (ctx  (list :id "TEST-RUN" :capabilities '(write-notes))))
      ;; Seed file.
      (let ((coding-system-for-write 'utf-8))
        (write-region "* H\nfirst line\n- @satan summarise me\nlast line\n"
                      nil file))
      ;; Scan: one match.
      (let* ((res (satan-tool/notes-at-satan-scan nil ctx)))
        (should (eq (car res) 'ok))
        (let* ((payload (cdr res))
               (matches (plist-get payload :matches))
               (m       (car matches))
               (id      (plist-get m :id)))
          (should (= 1 (length matches)))
          (should (string-match-p "summarise me" (plist-get m :content)))
          (should (equal "* H" (plist-get m :headline)))
          ;; Done: claim it.
          (let ((done (satan-tool/notes-at-satan-done
                       (list :match-id id :comment "ok")
                       ctx)))
            (should (eq (car done) 'ok))
            (should (equal "done" (plist-get (cdr done) :status))))
          ;; File now bears @satan-done with the run-id.
          (with-temp-buffer
            (insert-file-contents file)
            (should (string-match-p "@satan-done(TEST-RUN,ok)"
                                    (buffer-string))))
          ;; Idempotent: second done is a no-op.
          (let ((done2 (satan-tool/notes-at-satan-done
                        (list :match-id id) ctx)))
            (should (equal "already-done"
                           (plist-get (cdr done2) :status))))
          ;; Rescan: no matches.
          (let ((rescan (satan-tool/notes-at-satan-scan nil ctx)))
            (should (eq (car rescan) 'ok))
            (should (zerop (plist-get (cdr rescan) :count)))))))))
```

### Described tests

- **`notes-at-satan-scan/excludes-satan-dir`** — seed `<root>/satan/x.org`
  with `@satan x`; scan; assert `:count 0`. Verifies the `!satan/**`
  glob.
- **`notes-at-satan-scan/markdown-headline`** — seed `foo.md` with
  `## Onboarding\n@satan x`; scan; assert `:headline "## Onboarding"`.
- **`notes-at-satan-scan/context-window`** — seed a file with 10 lines,
  `@satan` on line 5; scan with `:context-lines 2`; assert `:context`
  contains lines 3-7 joined by `\n`.
- **`notes-at-satan-done/refuses-without-capability`** — call done with
  `ctx` lacking `'write-notes`; assert `(car res) == 'error`, message
  mentions capability.

## Build-verify sequence

```sh
# 1. Stage the new elisp under flake-tracked dotfiles.
git -C ~/.emacs.d add satan/satan-tools-atsatan.el
git -C ~/.emacs.d add satan/test/satan-tools-atsatan-test.el
# Notes-side files (~/notes/satan/{tools,prompts}/...) live in a
# separate repo and do not feed the Nix flake build.

# 2. Rebuild the home-manager environment so the new file is parsed
# and any new use-package forms (none here, but in general) are
# resolved.
cd ~/flakes && home-manager switch --flake .#david

# 3. Run the ert suite headless. Exits non-zero on failure; failure
# output goes to stdout.
emacs -batch \
  -L ~/.emacs.d/satan -L ~/.emacs.d/satan/test \
  -l ert -l satan-tools-atsatan-test \
  --eval '(ert-run-tests-batch-and-exit "notes-at-satan-")'

# 4. Smoke-test one live tick-agent run.
emacsclient --eval '(satan-run "tick-agent")'

# 5. Inspect the audit bundle.
ls ~/notes/satan/runs/most-recent/
```

## Done criteria

- All five ert tests pass under the batch command.
- A live `tick-agent` run with no `@satan` directives in `~/notes/`
  terminates cleanly with `satan_final` summarising "no @satan
  directives".
- A live `tick-agent` run with one seeded `@satan` directive: scan
  surfaces it, agent acts (writes inbox or hippocampus entry), claim
  succeeds, file now bears `@satan-was-here` + the quote block, second
  tick finds nothing.
- `CHANGELOG.md` carries a concise entry.
