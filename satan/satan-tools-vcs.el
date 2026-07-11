;;; satan-tools-vcs.el --- vcs_log tool handler -*- lexical-binding: t; -*-

;; Read-only, pwd-INDEPENDENT window into any repo's commit history.
;; The git-activity sensor (post-commit hook → percept) gives the model
;; ambient awareness that a project is active (via the `project:<slug>'
;; handle canon emits from the feed); `vcs_log' lets it then drill into
;; that repo's authoritative full history on demand.
;;
;; `repo' is an absolute path OR a bare slug resolved against
;; `satan-tools-vcs-search-roots'.  Unlike the CWD-anchored
;; `:git_state' in the evidence window, this never reads
;; `default-directory' — it runs `git -C REPO …' so the answer does not
;; depend on where Emacs happens to point.
;;
;; Risk = `read'; no capability required.

(require 'cl-lib)
(require 'subr-x)
(require 'satan-tools)
(require 'satan-memory-evidence)   ; reuse `--git-output'

(defcustom satan-tools-vcs-search-roots
  (list (expand-file-name "~/dev/")
        (expand-file-name "~/.emacs.d/")
        (expand-file-name "~/flakes/"))
  "Roots a bare repo slug is resolved against, in order.
First existing `ROOT/SLUG' directory wins.  Absolute-path `repo'
arguments bypass this list entirely.

User-tunable: this is the user's repo-search list, not package
self-location.  `~/.emacs.d/' stays valid post-extraction and is
intentionally retained."
  :type '(repeat directory) :group 'satan)

(defcustom satan-tools-vcs-default-limit 20
  "Default `:limit' for `vcs_log'."
  :type 'integer :group 'satan)

(defconst satan-tools-vcs--limit-max 200
  "Hard upper bound on `:limit'; clamped without error.")

(defconst satan-tools-vcs--field-sep "\x1f"
  "ASCII unit separator delimiting fields in the `git log' format.
Unlikely to appear in commit metadata, so it parses unambiguously.")

(defun satan-tools-vcs--clamp-limit (raw)
  (cond
   ((null raw) satan-tools-vcs-default-limit)
   ((< raw 1) 1)
   ((> raw satan-tools-vcs--limit-max) satan-tools-vcs--limit-max)
   (t raw)))

(defun satan-tools-vcs--resolve-repo (repo)
  "Return an absolute repo directory for REPO, or nil.
REPO is an absolute/relative path (used as-is if it is a directory) or a
bare slug resolved against `satan-tools-vcs-search-roots'."
  (when (and (stringp repo) (not (string-empty-p repo)))
    (let ((direct (expand-file-name repo)))
      (if (file-directory-p direct)
          direct
        (cl-loop for root in satan-tools-vcs-search-roots
                 for cand = (expand-file-name repo root)
                 when (file-directory-p cand) return cand)))))

(defun satan-tools-vcs--git-repo-p (dir)
  "Return non-nil if DIR is inside a git work tree."
  (let ((process-environment (cons "GIT_OPTIONAL_LOCKS=0" process-environment)))
    (zerop (call-process "git" nil nil nil "-C" dir "rev-parse" "--git-dir"))))

(defun satan-tools-vcs--log (dir limit)
  "Return up to LIMIT commit plists for DIR, newest first.
Each plist: (:sha :at :author :subject).  Runs `git -C DIR log' so it is
independent of `default-directory'."
  (let* ((sep satan-tools-vcs--field-sep)
         (fmt (concat "%h" sep "%cI" sep "%an" sep "%s"))
         (out (satan-memory-evidence--git-output
               "-C" dir "log" "-n" (number-to-string limit)
               (concat "--pretty=format:" fmt))))
    (when (and out (not (string-empty-p out)))
      (mapcar
       (lambda (line)
         (let ((f (split-string line sep)))
           (list :sha (nth 0 f)
                 :at (nth 1 f)
                 :author (nth 2 f)
                 :subject (nth 3 f))))
       (split-string out "\n" t)))))

(defun satan-tool/vcs-log (args _ctx)
  "Implements vcs_log.  ARGS: (:repo STRING :limit INT?).
Returns (ok PLIST) | (error STRING)."
  (let* ((repo (plist-get args :repo))
         (limit (satan-tools-vcs--clamp-limit (plist-get args :limit)))
         (dir (satan-tools-vcs--resolve-repo repo)))
    (cond
     ((null dir) (cons 'error (format "repo not found: %s" repo)))
     ((not (satan-tools-vcs--git-repo-p dir))
      (cons 'error (format "not a git repo: %s" dir)))
     (t (cons 'ok (list :repo (abbreviate-file-name dir)
                        :limit limit
                        :commits (or (satan-tools-vcs--log dir limit)
                                     '())))))))

(satan-tool-register
 (list :name "vcs_log"
       :risk 'read
       :args-schema '(repo  (:type string :required t)
                      limit (:type integer :required nil))
       :handler 'satan-tool/vcs-log))

(provide 'satan-tools-vcs)
;;; satan-tools-vcs.el ends here
