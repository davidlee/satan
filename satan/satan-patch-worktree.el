;;; satan-patch-worktree.el --- git worktree mechanics for patch jobs -*- lexical-binding: t; -*-

;; Phase 1.3 of satan/patch-harness.plan.md.  Branch naming, worktree
;; creation, allowlist verification, and cleanup.  All git operations
;; run via subprocess to the system `git'.
;;
;; Allowed-paths matching: each entry is a repo-root-relative string.
;; A trailing `/' means "this directory and below"; no trailing `/'
;; means an exact file match.  No globs in v1; simple to extend later.

(require 'cl-lib)
(require 'json)
(require 'subr-x)
(require 'satan-patch-store)  ; for the patch group + id helper
(require 'satan-trace)         ; route patch git through the subprocess ledger

(defcustom satan-patch-worktree-root
  (expand-file-name "satan/patch-agent/worktrees/"
                    (or (getenv "XDG_STATE_HOME")
                        (expand-file-name "~/.local/state/")))
  "Filesystem root under which job worktrees are created.
One directory per job, keyed by job id."
  :type 'directory :group 'satan-patch)

(defcustom satan-patch-worktree-git-program
  (or (executable-find "git") "git")
  "Path to the `git' binary."
  :type 'string :group 'satan-patch)

(defcustom satan-patch-worktree-timeout-seconds 30
  "Wall-clock timeout (seconds) for patch git ops routed through the trace ledger."
  :type 'number :group 'satan-patch)

;; ---------------------------------------------------------------------
;; branch naming
;; ---------------------------------------------------------------------

(defun satan-patch-worktree--slugify (s)
  "Lowercase S, replace non-alnum runs with `-', strip leading/trailing `-'."
  (let* ((down (downcase (or s "")))
         (subbed (replace-regexp-in-string "[^a-z0-9]+" "-" down))
         (trimmed (replace-regexp-in-string "\\`-+\\|-+\\'" "" subbed)))
    (if (string-empty-p trimmed) "job" trimmed)))

(defun satan-patch-worktree-branch-name (mode slug &optional time)
  "Return `satan/MODE/YYYYMMDDTHHMMSS-SLUG'.
TIME (epoch seconds or time object) defaults to now.  SLUG is
slugified to lowercase alnum + dashes."
  (let* ((stamp (format-time-string "%Y%m%dT%H%M%S" time))
         (safe-slug (satan-patch-worktree--slugify slug))
         (safe-mode (satan-patch-worktree--slugify mode)))
    (format "satan/%s/%s-%s" safe-mode stamp safe-slug)))

(defun satan-patch-worktree-path-for (job-id)
  "Return the canonical worktree path for JOB-ID."
  (expand-file-name job-id satan-patch-worktree-root))

;; ---------------------------------------------------------------------
;; git plumbing
;; ---------------------------------------------------------------------

(defun satan-patch-worktree--assert-owned (path)
  "Signal an error unless PATH is under `satan-patch-worktree-root'.
Compares `file-truename' of both sides (symlink-escape proof).  Every
mutating git op calls this with its target BEFORE running; writing to a
user tree is corruption, not a slow probe — so this is a hard error."
  (let ((root (file-name-as-directory
               (file-truename satan-patch-worktree-root)))
        (target (file-name-as-directory (file-truename path))))
    (unless (string-prefix-p root target)
      (error "patch-worktree confinement: %s escapes %s" path root))))

(defun satan-patch-worktree--git (repo args &optional input)
  "Run `git -C REPO ARGS', optionally feeding INPUT to stdin.
Return (ok . STDOUT) or (error . MSG).  Routed through `satan-trace-call'
for ledger visibility + a 30s wall timeout; NO `GIT_OPTIONAL_LOCKS' env
(patch ops are exempt)."
  (let* ((full-args (append (list "-C" repo) args))
         (res (satan-trace-call
               satan-patch-worktree-git-program full-args
               :stdin input
               :timeout-secs satan-patch-worktree-timeout-seconds
               :label "patch.git"))
         (exit (plist-get res :exit))
         (out (plist-get res :stdout)))
    (if (and (integerp exit) (zerop exit))
        (cons 'ok out)
      (cons 'error (format "git exit %s: %s" exit (string-trim out))))))

;; ---------------------------------------------------------------------
;; create
;; ---------------------------------------------------------------------

(defun satan-patch-worktree-create (job-spec)
  "Create the git worktree described by JOB-SPEC.
Required keys: :id :repo :base_ref :branch :worktree_path
              :allowed_paths_json (list of strings) :checks_json (list)
Writes a manifest file at `<worktree>/.satan-patch-manifest.json'.

Returns (ok PLIST) with :worktree-path and :branch, or
(error MSG).  Idempotent: refuses to create if worktree_path
exists, but succeeds if the branch already exists and points at
base_ref."
  (let* ((repo (plist-get job-spec :repo))
         (base (plist-get job-spec :base_ref))
         (branch (plist-get job-spec :branch))
         (wt (plist-get job-spec :worktree_path))
         (allowed (plist-get job-spec :allowed_paths_json))
         (checks (plist-get job-spec :checks_json))
         (id (plist-get job-spec :id)))
    (cond
     ((not (file-directory-p repo))
      (cons 'error (format "repo missing: %s" repo)))
     ((file-exists-p wt)
      (cons 'error (format "worktree path exists: %s" wt)))
     (t
      (let* ((parent (file-name-directory (directory-file-name wt))))
        (make-directory parent t))
      (satan-patch-worktree--assert-owned wt)
      (pcase (satan-patch-worktree--git
              repo (list "worktree" "add" wt "-b" branch base))
        (`(error . ,msg)
         (cons 'error (format "worktree add failed: %s" msg)))
        (`(ok . ,_)
         (let ((manifest (expand-file-name ".satan-patch-manifest.json" wt)))
           (with-temp-file manifest
             (insert
              (json-serialize
               (satan-jsonl-prepare
               (list :job_id id
                     :repo repo
                     :base_ref base
                     :branch branch
                     :worktree_path wt
                     :allowed_paths (or allowed '())
                     :checks (or checks '()))))))
           ;; Exclude the manifest from this worktree's git status so a
           ;; clean adapter run shows up as truly clean.  Per-worktree
           ;; exclude lives in the linked worktree's gitdir.
           (pcase (satan-patch-worktree--git
                   wt (list "rev-parse" "--git-path" "info/exclude"))
             (`(ok . ,exclude-rel)
              (let* ((exclude-path
                      (expand-file-name (string-trim exclude-rel) wt))
                     (entry ".satan-patch-manifest.json\n"))
                (make-directory (file-name-directory exclude-path) t)
                (with-temp-buffer
                  (when (file-exists-p exclude-path)
                    (insert-file-contents exclude-path))
                  (unless (save-excursion
                            (goto-char (point-min))
                            (search-forward entry nil t))
                    (goto-char (point-max))
                    (unless (or (= (point) (point-min))
                                (eq (char-before) ?\n))
                      (insert "\n"))
                    (insert entry)
                    (write-region (point-min) (point-max)
                                  exclude-path nil 'silent))))))
           (cons 'ok (list :worktree-path wt :branch branch)))))))))

;; ---------------------------------------------------------------------
;; allowed-paths verify
;; ---------------------------------------------------------------------

(defun satan-patch-worktree--normalize-path (p)
  "Normalise P: strip leading `./', trim whitespace."
  (let ((s (string-trim (or p ""))))
    (if (string-prefix-p "./" s) (substring s 2) s)))

(defun satan-patch-worktree-path-allowed-p (path allowed)
  "Non-nil iff repo-relative PATH is permitted by the ALLOWED list.
Each entry of ALLOWED is repo-relative.  Trailing `/' means prefix
match; no trailing `/' means exact match."
  (let ((np (satan-patch-worktree--normalize-path path)))
    (cl-some
     (lambda (entry)
       (let ((ne (satan-patch-worktree--normalize-path entry)))
         (cond
          ((string-empty-p ne) nil)
          ((string-suffix-p "/" ne)
           (string-prefix-p ne np))
          (t (string= ne np)))))
     allowed)))

(defun satan-patch-worktree-changed-files (job-spec)
  "Return (ok . LIST-OF-PATHS) of files changed between base_ref and HEAD.
Paths are repo-relative.  Runs inside the job's worktree."
  (let* ((wt (plist-get job-spec :worktree_path))
         (base (plist-get job-spec :base_ref)))
    (pcase (satan-patch-worktree--git
            wt (list "diff" "--name-only"
                     (concat base "...HEAD")))
      (`(ok . ,out)
       (cons 'ok (split-string (string-trim out) "\n" t)))
      (err err))))

(defun satan-patch-worktree-verify-allowlist (job-spec changed)
  "Check CHANGED files against JOB-SPEC's allowed paths.
Returns (ok . CHANGED) when every file is allowed, else
\(error . OFFENDING-PATHS)."
  (let* ((allowed (plist-get job-spec :allowed_paths_json))
         (bad (cl-remove-if
               (lambda (p)
                 (satan-patch-worktree-path-allowed-p p allowed))
               changed)))
    (if bad
        (cons 'error bad)
      (cons 'ok changed))))

;; ---------------------------------------------------------------------
;; post-run inspection: commits, diffstat, status
;; ---------------------------------------------------------------------

(defun satan-patch-worktree-commits (job-spec)
  "Return (ok . LIST) of commits between base_ref and HEAD inside JOB-SPEC's
worktree.  Each element is a plist (:sha STR :subject STR).  Returns
\(error . MSG) on git failure."
  (let* ((wt (plist-get job-spec :worktree_path))
         (base (plist-get job-spec :base_ref)))
    (pcase (satan-patch-worktree--git
            wt (list "log" "--pretty=format:%H%x00%s"
                     (concat base "..HEAD")))
      (`(ok . ,out)
       (cons 'ok
             (cl-loop for line in (split-string (string-trim out) "\n" t)
                      for parts = (split-string line "\0")
                      when (= 2 (length parts))
                      collect (list :sha (car parts)
                                    :subject (cadr parts)))))
      (err err))))

(defun satan-patch-worktree-diffstat (job-spec)
  "Return (ok PLIST) of files_changed/insertions/deletions or (error MSG).
Computed from `git diff --shortstat base_ref..HEAD' inside the worktree."
  (let* ((wt (plist-get job-spec :worktree_path))
         (base (plist-get job-spec :base_ref)))
    (pcase (satan-patch-worktree--git
            wt (list "diff" "--shortstat"
                     (concat base "..HEAD")))
      (`(ok . ,out)
       (let* ((s (string-trim out))
              (files (and (string-match "\\([0-9]+\\) files? changed" s)
                          (string-to-number (match-string 1 s))))
              (ins   (and (string-match "\\([0-9]+\\) insertions?" s)
                          (string-to-number (match-string 1 s))))
              (dels  (and (string-match "\\([0-9]+\\) deletions?" s)
                          (string-to-number (match-string 1 s)))))
         (cons 'ok (list :files_changed (or files 0)
                         :insertions (or ins 0)
                         :deletions (or dels 0)))))
      (err err))))

(defun satan-patch-worktree-status-clean-p (job-spec)
  "Non-nil iff JOB-SPEC's worktree has no untracked/staged/modified files.
Returns nil also on git failure (treated as not-clean for safety)."
  (let* ((wt (plist-get job-spec :worktree_path)))
    (pcase (satan-patch-worktree--git
            wt (list "status" "--porcelain"))
      (`(ok . ,out) (string-empty-p (string-trim out)))
      (_ nil))))

;; ---------------------------------------------------------------------
;; cleanup
;; ---------------------------------------------------------------------

(cl-defun satan-patch-worktree-cleanup (job-spec &key delete-branch)
  "Remove the worktree at JOB-SPEC's :worktree_path; optionally delete
branch.  Idempotent.  Returns (ok PLIST) with :removed-worktree and
:deleted-branch booleans, or (error MSG)."
  (let* ((repo (plist-get job-spec :repo))
         (wt (plist-get job-spec :worktree_path))
         (branch (plist-get job-spec :branch))
         (removed nil)
         (deleted nil))
    (when (file-exists-p wt)
      (satan-patch-worktree--assert-owned wt)
      (pcase (satan-patch-worktree--git
              repo (list "worktree" "remove" "--force" wt))
        (`(error . ,msg) (cl-return-from satan-patch-worktree-cleanup
                           (cons 'error msg)))
        (_ (setq removed t))))
    (when delete-branch
      (pcase (satan-patch-worktree--git
              repo (list "branch" "-D" branch))
        (`(error . ,msg)
         ;; Branch may already be gone after `worktree remove'; tolerate
         ;; "branch not found" but surface other errors.
         (unless (string-match-p "not found" msg)
           (cl-return-from satan-patch-worktree-cleanup
             (cons 'error msg))))
        (_ (setq deleted t))))
    (cons 'ok (list :removed-worktree removed
                    :deleted-branch deleted))))

(provide 'satan-patch-worktree)
;;; satan-patch-worktree.el ends here
