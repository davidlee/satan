;;; satan-patch-inbox.el --- the patch runner's watch, into the inbox -*- lexical-binding: t; -*-

;; SL-023 (DEC-058, DEC-063): the inbox follows the patch runner's
;; `watch'.  The runner replays every needs_review job and every
;; unacknowledged failed/cancelled job on each new watch, then streams
;; transitions; this module turns those frames into inbox entries.
;;
;;   needs_review                       review entry, with the diffstat
;;                                      and commits from `result'
;;                                      (show/promote/reject:
;;                                      satan-patch-promote)
;;   failed/cancelled, not announced    notice, then `ack'
;;   anything else                      ignored
;;
;; Idempotent by job id: an entry carrying :SATAN_PATCH_JOB: <id> is
;; never appended twice, so the replay after a reconnect (or after a
;; refused ack) adds nothing.  A notice is acked even when its entry
;; already exists.  A user who deletes an entry sees it again on the
;; next replay: a missed notice is never lost.
;;
;; The watch reconnects on its own: a dropped or refused connection
;; retries after a backoff that doubles from
;; `satan-patch-inbox-backoff-initial' to `satan-patch-inbox-backoff-max',
;; reset once the runner accepts a watch.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'satan-patch-rpc)
(require 'satan-tools-inbox)

(defcustom satan-patch-inbox-enabled t
  "When non-nil, `satan-patch-inbox-start' opens the runner watch."
  :type 'boolean :group 'satan)

(defcustom satan-patch-inbox-backoff-initial 1
  "Seconds before the first reconnect after the watch drops."
  :type 'number :group 'satan)

(defcustom satan-patch-inbox-backoff-max 60
  "Ceiling, in seconds, of the doubling reconnect backoff."
  :type 'number :group 'satan)

(defvar satan-patch-inbox--watch nil
  "The running watch: a plist (:process P :backoff S :timer T), or nil.
P is the open connection (nil while waiting to reconnect), S the delay
before the next reconnect, T the pending reconnect timer.")

;; ---------------------------------------------------------------------
;; rendering
;; ---------------------------------------------------------------------

(defconst satan-patch-inbox--titles
  '(("needs_review" . "Patch ready")
    ("failed" . "Patch failed")
    ("cancelled" . "Patch cancelled"))
  "Entry title prefix per job state.")

(defun satan-patch-inbox--title (job)
  "The entry title for projected JOB."
  (format "%s: %s %s %s"
          (cdr (assoc (plist-get job :state) satan-patch-inbox--titles))
          (plist-get job :mode) (plist-get job :repo) (plist-get job :job_id)))

(defun satan-patch-inbox--failure-lines (failure)
  "Body lines for a job's FAILURE record."
  (when failure
    (cons (string-join (delq nil (list "Failure:"
                                       (satan-patch-rpc-field failure :reason)
                                       (satan-patch-rpc-field failure :message)))
                       " ")
          (mapcar (lambda (path) (concat "- " path))
                  (satan-patch-rpc-field failure :offending)))))

(defun satan-patch-inbox--diffstat-lines (diffstat)
  "Body lines for a job's DIFFSTAT record."
  (when diffstat
    (list (format "Diffstat: %s files, +%s -%s"
                  (plist-get diffstat :files) (plist-get diffstat :insertions)
                  (plist-get diffstat :deletions)))))

(defun satan-patch-inbox--commit-lines (commits)
  "Body lines for a job's COMMITS, oldest first.
Each commit's full message when the runner sends one, else its
subject; continuation lines are indented, so a message cannot open
an Org heading."
  (unless (seq-empty-p commits)
    (cons "Commits:"
          (seq-mapcat
           (lambda (commit)
             (pcase-let ((`(,first . ,rest)
                          (split-string
                           (string-trim-right
                            (or (satan-patch-rpc-field commit :message)
                                (plist-get commit :subject)))
                           "\n")))
               (cons (format "- %s %s"
                             (substring (plist-get commit :oid) 0 7) first)
                     (mapcar (lambda (line)
                               (if (string-empty-p line) "" (concat "  " line)))
                             rest))))
           commits))))

(defconst satan-patch-inbox--body-fields
  '(("State" . :state) ("Repo" . :repo) ("Base" . :base_ref) ("Class" . :class)
    ("Partial" . :partial) ("Reviewed oid" . :reviewed_oid)
    ("End reason" . :end_reason))
  "Body lines of an entry: label and projected job field, in order.")

(defun satan-patch-inbox--body (job)
  "The entry body for projected JOB: one line per field it carries."
  (concat
   (string-join
    (append
     (cl-loop for (label . key) in satan-patch-inbox--body-fields
              for value = (satan-patch-rpc-field job key)
              when value
              collect (format "%s: %s" label
                              (pcase value ('t "yes") (:false "no") (_ value))))
     (satan-patch-inbox--diffstat-lines (satan-patch-rpc-field job :diffstat))
     (satan-patch-inbox--commit-lines (satan-patch-rpc-field job :commits))
     (satan-patch-inbox--failure-lines (satan-patch-rpc-field job :failure)))
    "\n")
   "\n"))

;; ---------------------------------------------------------------------
;; frames -> entries
;; ---------------------------------------------------------------------

(defun satan-patch-inbox--present-p (job-id)
  "Whether the inbox already holds an entry for JOB-ID."
  (and (file-readable-p satan-inbox-file)
       (with-temp-buffer
         (insert-file-contents satan-inbox-file)
         (re-search-forward
          (format "^:SATAN_PATCH_JOB: %s$" (regexp-quote job-id)) nil t))))

(defun satan-patch-inbox--append (job)
  "Append projected JOB's entry unless the inbox already holds one."
  (let ((id (plist-get job :job_id))
        (state (plist-get job :state)))
    (unless (satan-patch-inbox--present-p id)
      (satan-tools-inbox-write
       :title (satan-patch-inbox--title job)
       :urgency (if (equal state "failed") "urgent" "normal")
       :body (satan-patch-inbox--body job)
       :properties (list :satan_patch_job id
                         :repo (plist-get job :repo)
                         :mode (plist-get job :mode)
                         :state state
                         :reviewed_oid (satan-patch-rpc-field
                                        job :reviewed_oid))))))

(defun satan-patch-inbox--append-reviewed (job)
  "Append needs_review JOB's entry with the diffstat and commits.
They come from `result' (a watch summary lacks them); a refused
`result' appends the entry without them."
  (unless (satan-patch-inbox--present-p (plist-get job :job_id))
    (satan-patch-inbox--append
     (pcase (satan-patch-rpc-call "result" (list :jobId (plist-get job :job_id)))
       (`(ok . ,body)
        (let ((result (satan-patch-rpc-project body)))
          (append (list :diffstat (plist-get result :diffstat)
                        :commits (plist-get result :commits))
                  job)))
       (`(error . ,msg)
        (message "satan-patch-inbox: result %s: %s (entry without its diff summary)"
                 (plist-get job :job_id) msg)
        job)))))

(defun satan-patch-inbox--ack (job-id)
  "Acknowledge JOB-ID's notice to the runner; report a refusal."
  (pcase (satan-patch-rpc-call "ack" (list :jobIds (vector job-id)))
    (`(error . ,msg)
     (message "satan-patch-inbox: ack %s: %s (resent on the next watch)"
              job-id msg))))

(defun satan-patch-inbox-handle (wire-job)
  "Bring WIRE-JOB, a runner job summary, into the inbox.
A needs_review job gets a review entry; a failed or cancelled job not
yet announced gets a notice and is acked.  The review entry's `result'
call and the ack run from a timer: this is called from the watch's
filter, which must not wait on another connection."
  (let* ((job (satan-patch-rpc-project wire-job t))
         (state (plist-get job :state)))
    (cond
     ((equal state "needs_review")
      (run-at-time 0 nil #'satan-patch-inbox--append-reviewed job))
     ((and (member state '("failed" "cancelled"))
           (not (satan-patch-rpc-field job :announced_at)))
      (satan-patch-inbox--append job)
      (run-at-time 0 nil #'satan-patch-inbox--ack (plist-get job :job_id))))))

(defun satan-patch-inbox--on-frame (frame)
  "Handle one watch FRAME; a failure to append is reported, not raised."
  (when (equal (plist-get frame :event) "job_changed")
    (condition-case err
        (satan-patch-inbox-handle (plist-get frame :job))
      (error (message "satan-patch-inbox: %s" (error-message-string err))))))

;; ---------------------------------------------------------------------
;; the watch connection
;; ---------------------------------------------------------------------

(defun satan-patch-inbox--retry ()
  "Schedule the next reconnect, doubling the backoff."
  (let ((delay (plist-get satan-patch-inbox--watch :backoff)))
    (setq satan-patch-inbox--watch
          (list :process nil
                :backoff (min satan-patch-inbox-backoff-max (* 2 delay))
                :timer (run-at-time delay nil #'satan-patch-inbox--connect)))))

(defun satan-patch-inbox--on-close (proc why)
  "The watch PROC closed, saying WHY: reconnect unless it was stopped."
  (when (and satan-patch-inbox--watch
             (eq proc (plist-get satan-patch-inbox--watch :process)))
    (message "satan-patch-inbox: watch closed: %s" why)
    (satan-patch-inbox--retry)))

(defun satan-patch-inbox--on-open ()
  "The runner accepted the watch: reset the backoff."
  (when satan-patch-inbox--watch
    (plist-put satan-patch-inbox--watch :backoff
               satan-patch-inbox-backoff-initial)))

(defun satan-patch-inbox--connect ()
  "Open the watch; on failure, schedule a reconnect."
  (when satan-patch-inbox--watch
    (let (proc)
      (pcase (satan-patch-rpc-watch-open
              #'satan-patch-inbox--on-frame
              (lambda (why) (satan-patch-inbox--on-close proc why))
              #'satan-patch-inbox--on-open)
        (`(ok . ,opened)
         (setq proc opened)
         (plist-put satan-patch-inbox--watch :process proc)
         (plist-put satan-patch-inbox--watch :timer nil))
        (`(error . ,msg)
         (message "satan-patch-inbox: %s" msg)
         (satan-patch-inbox--retry))))))

;;;###autoload
(defun satan-patch-inbox-start ()
  "Watch the patch runner, bringing its jobs into the inbox.
No-op when `satan-patch-inbox-enabled' is nil or the watch already
runs.  Returns non-nil when the watch is running."
  (interactive)
  (when satan-patch-inbox-enabled
    (unless satan-patch-inbox--watch
      (setq satan-patch-inbox--watch
            (list :process nil :timer nil
                  :backoff satan-patch-inbox-backoff-initial))
      (satan-patch-inbox--connect))
    t))

;;;###autoload
(defun satan-patch-inbox-stop ()
  "Stop watching the patch runner.  Idempotent."
  (interactive)
  (when-let* ((watch satan-patch-inbox--watch))
    (setq satan-patch-inbox--watch nil)
    (when-let* ((timer (plist-get watch :timer))) (cancel-timer timer))
    (when-let* ((proc (plist-get watch :process))) (delete-process proc))))

(defun satan-patch-inbox-running-p ()
  "Whether the watch is running (connected, or waiting to reconnect)."
  (and satan-patch-inbox--watch t))

(provide 'satan-patch-inbox)
;;; satan-patch-inbox.el ends here
