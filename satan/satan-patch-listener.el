;;; satan-patch-listener.el --- postgres NOTIFY → inbox handoff -*- lexical-binding: t; -*-

;; Long-running `satan-attrd notify-stream' subprocess that LISTENs on
;; the two channels the runner daemon emits at terminal job
;; transitions, and feeds each payload to `satan-patch-inbox-handoff'
;; via `satan-patch-store-get'.
;;
;; The listener exists so the inbox keeps working when the elisp
;; runner is disabled (`satan-patch-runner-enabled' = nil) and the
;; daemon owns the queue.  When the elisp runner is enabled the
;; runner-hook in `satan-patch-inbox.el' is the path; they share
;; the same handoff function.
;;
;; Transport rationale: a raw `psql ... LISTEN ...' subprocess buffers
;; async notifications until the next stdin command, so notifies never
;; surface in a long-running pipe consumer.  `satan-attrd notify-stream'
;; holds a real libpq connection (via tokio-postgres in the daemon
;; binary) and writes one JSON line per notification, flushed.

(require 'cl-lib)
(require 'json)
(require 'subr-x)
(require 'satan-patch-store)
(require 'satan-patch-inbox)

(declare-function notifications-notify "notifications" (&rest args))

;; ---------------------------------------------------------------------
;; customisation
;; ---------------------------------------------------------------------

(defcustom satan-patch-listener-enabled t
  "When non-nil, `satan-patch-listener-start' spawns the LISTEN process.
Set to nil to disable the postgres LISTEN bridge and fall back to
manual inbox checks."
  :type 'boolean :group 'satan-patch)

(defcustom satan-patch-listener-notify-app "SATAN"
  "Application name used for the D-Bus death notification."
  :type 'string :group 'satan-patch)

(defcustom satan-patch-listener-program
  (or (executable-find "satan-attrd") "satan-attrd")
  "Path to the `satan-attrd' binary used as the LISTEN transport."
  :type 'string :group 'satan-patch)

;; ---------------------------------------------------------------------
;; internals
;; ---------------------------------------------------------------------

(defvar satan-patch-listener--proc nil
  "Live LISTEN subprocess, or nil.")

(defconst satan-patch-listener--channels
  '("patch_jobs_done" "patch_jobs_failed")
  "Notification channels we subscribe to.")

(defun satan-patch-listener--parse-line (line)
  "Parse one JSON line from `satan-attrd notify-stream'.
Returns a plist (:channel STR :payload STR) or nil if LINE is not a
notification (e.g. tracing diagnostic from the binary)."
  (when (and (> (length line) 0) (= (aref line 0) ?{))
    (condition-case _
        (let* ((obj (json-parse-string line :object-type 'plist))
               (ch (plist-get obj :channel))
               (pl (plist-get obj :payload)))
          (when (and (stringp ch) (stringp pl))
            (list :channel ch :payload pl)))
      (error nil))))

(defun satan-patch-listener--dispatch (channel job-id)
  "Look up JOB-ID and feed the row to the inbox handoff.
CHANNEL is informational; payload is already on a registered channel."
  (ignore channel)
  (pcase (satan-patch-store-get job-id)
    (`(ok . ,row)
     (when row (satan-patch-inbox-handoff row)))
    (`(error . ,msg)
     (message "satan-patch-listener: store-get %s: %s" job-id msg))
    (other
     (message "satan-patch-listener: unexpected store-get result: %S" other))))

(defun satan-patch-listener--maybe-dispatch (line)
  "If LINE is a notification on a registered channel, dispatch it."
  (when-let* ((evt (satan-patch-listener--parse-line line))
              (channel (plist-get evt :channel))
              ((member channel satan-patch-listener--channels)))
    (satan-patch-listener--dispatch channel (plist-get evt :payload))))

(defun satan-patch-listener--make-filter ()
  "Return a stateful filter closure parsing notifications line-by-line."
  (let ((buf ""))
    (lambda (_proc chunk)
      (setq buf (concat buf chunk))
      (let ((lines (split-string buf "\n")))
        (setq buf (car (last lines)))
        (dolist (line (butlast lines))
          (satan-patch-listener--maybe-dispatch line))))))

(defun satan-patch-listener--report-death (status code stderr-tail)
  "Log + fire a critical desktop notification for a dead listener."
  (let* ((title (format "satan-patch listener died (status=%s code=%s)"
                        status code))
         (body  (or stderr-tail "(no stderr captured)")))
    (message "%s\n%s" title body)
    (condition-case err
        (progn
          (require 'notifications)
          (notifications-notify
           :title title
           :body  body
           :urgency 'critical
           :app-name satan-patch-listener-notify-app))
      (error
       (message "satan-patch-listener: notify failed: %s"
                (error-message-string err))))))

(defun satan-patch-listener--stderr-tail (buf)
  "Return the last 10 lines of BUF as a string, or nil."
  (when (buffer-live-p buf)
    (with-current-buffer buf
      (let ((lines (split-string (buffer-string) "\n" t)))
        (when lines
          (mapconcat #'identity (last lines 10) "\n"))))))

(defun satan-patch-listener--sentinel (proc _event)
  "Sentinel: on exit/signal, report loudly and clear the procvar."
  (when (memq (process-status proc) '(exit signal))
    (let* ((stderr-buf  (process-get proc 'stderr-buffer))
           (stderr-tail (satan-patch-listener--stderr-tail stderr-buf))
           (status      (process-status proc))
           (code        (process-exit-status proc)))
      (satan-patch-listener--report-death status code stderr-tail)
      (when (buffer-live-p stderr-buf) (kill-buffer stderr-buf))
      (when (eq proc satan-patch-listener--proc)
        (setq satan-patch-listener--proc nil)))))

;; ---------------------------------------------------------------------
;; public API
;; ---------------------------------------------------------------------

;;;###autoload
(defun satan-patch-listener-start ()
  "Spawn the `satan-attrd notify-stream' subprocess if enabled.
No-op when already running.  Returns the process, or nil if disabled
or the program is missing."
  (interactive)
  (cond
   ((not satan-patch-listener-enabled) nil)
   ((process-live-p satan-patch-listener--proc)
    satan-patch-listener--proc)
   (t
    (let* ((prog satan-patch-listener-program)
           (db   satan-patch-store-database)
           (host satan-patch-store-host)
           (database-url (format "postgres:///%s?host=%s" db host))
           (process-environment
            (cons (concat "DATABASE_URL=" database-url) process-environment))
           (stderr (generate-new-buffer
                    (format " *satan-patch-listener-stderr*")))
           (proc (make-process
                  :name "satan-patch-listener"
                  :command (append (list prog "notify-stream")
                                   satan-patch-listener--channels)
                  :connection-type 'pipe
                  :coding 'utf-8
                  :noquery t
                  :stderr stderr
                  :filter (satan-patch-listener--make-filter)
                  :sentinel #'satan-patch-listener--sentinel)))
      (process-put proc 'stderr-buffer stderr)
      (setq satan-patch-listener--proc proc)
      proc))))

;;;###autoload
(defun satan-patch-listener-stop ()
  "Stop the LISTEN subprocess if running.  Idempotent."
  (interactive)
  (when (process-live-p satan-patch-listener--proc)
    (let ((stderr-buf (process-get satan-patch-listener--proc 'stderr-buffer)))
      (set-process-sentinel satan-patch-listener--proc #'ignore)
      (delete-process satan-patch-listener--proc)
      (when (buffer-live-p stderr-buf) (kill-buffer stderr-buf))))
  (setq satan-patch-listener--proc nil))

;;;###autoload
(defun satan-patch-listener-status ()
  "Return `running', `stopped', or `dead' depending on the listener.
When called interactively, also `message' the same."
  (interactive)
  (let ((state
         (cond
          ((process-live-p satan-patch-listener--proc) 'running)
          ((null satan-patch-listener--proc)           'stopped)
          (t                                              'dead))))
    (when (called-interactively-p 'interactive)
      (message "satan-patch-listener: %s%s"
               state
               (if (eq state 'running)
                   (format " (pid=%s)"
                           (process-id satan-patch-listener--proc))
                 "")))
    state))

(when (and (not noninteractive) satan-patch-listener-enabled)
  (satan-patch-listener-start))

(provide 'satan-patch-listener)
;;; satan-patch-listener.el ends here
