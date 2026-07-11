;;; dl-satan-patch-prompt.el --- harness directive assembler -*- lexical-binding: t; -*-

;; Phase 2.3 of satan/patch-harness.plan.md.  Combines:
;;
;;   - canonical system prompt   `~/notes/satan/patch-agent/prompt.md'
;;   - per-job directive          (the verb)
;;   - per-job context bundle     (memory matches, note excerpts, etc)
;;   - allowlist string           (explicit "you may only edit ...")
;;   - check list                 (shell commands to run before success)
;;   - mode / job-id / source     (for the commit-message contract)
;;
;; The result is an INPUT plist that any adapter can consume; see
;; `dl-satan-patch-adapter' module commentary for the contract.

(require 'cl-lib)
(require 'subr-x)
(require 'dl-notes-paths)
(require 'dl-satan-patch-store)
(require 'dl-satan-patch-worktree)

(defcustom dl-satan-patch-prompt-system-file
  (expand-file-name "satan/patch-agent/prompt.md" dl-notes-root)
  "Path to the patch-agent harness system prompt."
  :type 'file :group 'dl-satan-patch)

(defcustom dl-satan-patch-prompt-log-root
  (expand-file-name "satan/patch-agent/logs/"
                    (or (getenv "XDG_STATE_HOME")
                        (expand-file-name "~/.local/state/")))
  "Directory where adapter stdout/event logs are written."
  :type 'directory :group 'dl-satan-patch)

(defcustom dl-satan-patch-prompt-timeout-seconds 1800
  "Default wall-clock cap for an adapter run."
  :type 'integer :group 'dl-satan-patch)

(defcustom dl-satan-patch-prompt-max-output-bytes (* 8 1024 1024)
  "Cap on captured adapter output bytes (truncated when exceeded)."
  :type 'integer :group 'dl-satan-patch)

;; ---------------------------------------------------------------------
;; directive rendering
;; ---------------------------------------------------------------------

(defun dl-satan-patch-prompt--render-allowlist (allowed)
  "Render ALLOWED (list of strings) as a bullet list."
  (mapconcat (lambda (p) (concat "- " p)) (or allowed '()) "\n"))

(defun dl-satan-patch-prompt--render-checks (checks)
  "Render CHECKS list (strings) for inclusion in the directive."
  (if (null checks)
      "(no automated checks specified)"
    (mapconcat (lambda (c) (concat "- " c)) checks "\n")))

(defun dl-satan-patch-prompt--render-context (context)
  "Render CONTEXT plist (or nil) as a short bullet block.
Recognised keys: :note_context :memory_matches :proposal_id
:mode_run_id :source.  Unknown keys are dropped quietly."
  (let* ((parts
          (delq nil
                (list
                 (when-let* ((s (plist-get context :note_context)))
                   (format "note context:\n%s" s))
                 (when-let* ((m (plist-get context :memory_matches)))
                   (format "memory matches: %d" (length m)))
                 (when-let* ((p (plist-get context :proposal_id)))
                   (format "proposal: %s" p))
                 (when-let* ((r (plist-get context :mode_run_id)))
                   (format "mode run: %s" r))
                 (when-let* ((src (plist-get context :source)))
                   (format "source: %S" src))))))
    (if parts (mapconcat #'identity parts "\n\n") "")))

(defun dl-satan-patch-prompt--render-source (source)
  "Build the `Source:' line for the commit-message footer.
SOURCE is the row's :source_json plist; nil returns \"none\"."
  (cond
   ((null source) "none")
   ((plist-get source :kind)
    (let ((kind (plist-get source :kind))
          (file (plist-get source :file))
          (line (plist-get source :line)))
      (if (and file line)
          (format "%s %s:%s" kind file line)
        (or file (format "%s" kind)))))
   (t (format "%S" source))))

(defun dl-satan-patch-prompt-build-directive (job)
  "Build the directive string passed to the adapter.

JOB is a row plist as returned by `dl-satan-patch-store-get'.
The string is self-contained: identity (job-id, mode, source),
the verb (job's :directive), the allowlist, the checks, the
context bundle, and the commit-message footer the agent must use."
  (let* ((job-id    (plist-get job :id))
         (mode      (plist-get job :mode))
         (directive (plist-get job :directive))
         (allowed   (plist-get job :allowed_paths_json))
         (checks    (plist-get job :checks_json))
         (context   (plist-get job :context_json))
         (source    (plist-get job :source_json))
         (branch    (plist-get job :branch))
         (rendered-context (dl-satan-patch-prompt--render-context context))
         (source-line (dl-satan-patch-prompt--render-source source)))
    (mapconcat
     #'identity
     (delq nil
           (list
            (format "# patch-agent job %s" job-id)
            (format "Mode: %s" mode)
            (format "Branch: %s" branch)
            ""
            "## Directive"
            ""
            directive
            ""
            "## Allowed paths"
            ""
            (dl-satan-patch-prompt--render-allowlist allowed)
            ""
            "## Checks"
            ""
            (dl-satan-patch-prompt--render-checks checks)
            (when (and rendered-context (not (string-empty-p rendered-context)))
              (concat "\n## Context\n\n" rendered-context))
            ""
            "## Commit footer"
            ""
            "When you commit, use this exact footer (after a blank line):"
            ""
            (format "    Patch-agent job: %s" job-id)
            (format "    Source: %s" source-line)
            ""
            "Subject line format: `<mode>: <short imperative summary>`,"
            (format "with mode=%s." mode)))
     "\n")))

;; ---------------------------------------------------------------------
;; INPUT plist for adapters
;; ---------------------------------------------------------------------

(defun dl-satan-patch-prompt-log-path (job-id)
  "Return the canonical adapter-log path for JOB-ID."
  (expand-file-name (concat job-id ".jsonl")
                    dl-satan-patch-prompt-log-root))

(cl-defun dl-satan-patch-prompt-build
    (job &key
         (system-prompt-file dl-satan-patch-prompt-system-file)
         (timeout-seconds dl-satan-patch-prompt-timeout-seconds)
         (max-output-bytes dl-satan-patch-prompt-max-output-bytes)
         provider model)
  "Build the adapter INPUT plist for JOB (a row plist).

Required JOB keys: :id :mode :directive :branch
                   :allowed_paths_json :checks_json :context_json
                   :source_json.

Honors keyword overrides for the system prompt file, caps, and
provider/model.  Ensures the log directory exists."
  (let* ((job-id (plist-get job :id))
         (log-path (dl-satan-patch-prompt-log-path job-id)))
    (make-directory (file-name-directory log-path) t)
    (list :system-prompt-file system-prompt-file
          :directive (dl-satan-patch-prompt-build-directive job)
          :timeout-seconds timeout-seconds
          :max-output-bytes max-output-bytes
          :log-path log-path
          :provider provider
          :model model)))

(provide 'dl-satan-patch-prompt)
;;; dl-satan-patch-prompt.el ends here
