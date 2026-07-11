;;; dl-satan-patch-listener.el --- postgres NOTIFY → inbox handoff -*- lexical-binding: t; -*-

;; Long-running `satan-attrd notify-stream' subprocess that LISTENs on
;; the two channels the runner daemon emits at terminal job
;; transitions, and feeds each payload to `dl-satan-patch-inbox-handoff'
;; via `dl-satan-patch-store-get'.
;;
;; The listener exists so the inbox keeps working when the elisp
;; runner is disabled (`dl-satan-patch-runner-enabled' = nil) and the
;; daemon owns the queue.  When the elisp runner is enabled the
;; runner-hook in `dl-satan-patch-inbox.el' is the path; they share
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
(require 'dl-satan-patch-store)
(require 'dl-satan-patch-inbox)

(declare-function notifications-notify "notifications" (&rest args))

;; ---------------------------------------------------------------------
;; customisation
;; ---------------------------------------------------------------------

(defcustom dl-satan-patch-listener-enabled t
  "When non-nil, `dl-satan-patch-listener-start' spawns the LISTEN process.
Set to nil to disable the postgres LISTEN bridge and fall back to
manual inbox checks."
  :type 'boolean :group 'dl-satan-patch)

(defcustom dl-satan-patch-listener-notify-app "SATAN"
  "Application name used for the D-Bus death notification."
  :type 'string :group 'dl-satan-patch)

(defcustom dl-satan-patch-listener-program
  (or (executable-find "satan-attrd") "satan-attrd")
  "Path to the `satan-attrd' binary used as the LISTEN transport."
  :type 'string :group 'dl-satan-patch)

;; ---------------------------------------------------------------------
;; internals
;; ---------------------------------------------------------------------

(defvar dl-satan-patch-listener--proc nil
  "Live LISTEN subprocess, or nil.")

(defconst dl-satan-patch-listener--channels
  '("patch_jobs_done" "patch_jobs_failed")
  "Notification channels we subscribe to.")

(defun dl-satan-patch-listener--parse-line (line)
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

(defun dl-satan-patch-listener--dispatch (channel job-id)
  "Look up JOB-ID and feed the row to the inbox handoff.
CHANNEL is informational; payload is already on a registered channel."
  (ignore channel)
  (pcase (dl-satan-patch-store-get job-id)
    (`(ok . ,row)
     (when row (dl-satan-patch-inbox-handoff row)))
    (`(error . ,msg)
     (message "dl-satan-patch-listener: store-get %s: %s" job-id msg))
    (other
     (message "dl-satan-patch-listener: unexpected store-get result: %S" other))))

(defun dl-satan-patch-listener--maybe-dispatch (line)
  "If LINE is a notification on a registered channel, dispatch it."
  (when-let* ((evt (dl-satan-patch-listener--parse-line line))
              (channel (plist-get evt :channel))
              ((member channel dl-satan-patch-listener--channels)))
    (dl-satan-patch-listener--dispatch channel (plist-get evt :payload))))

(defun dl-satan-patch-listener--make-filter ()
  "Return a stateful filter closure parsing notifications line-by-line."
  (let ((buf ""))
    (lambda (_proc chunk)
      (setq buf (concat buf chunk))
      (let ((lines (split-string buf "\n")))
        (setq buf (car (last lines)))
        (dolist (line (butlast lines))
          (dl-satan-patch-listener--maybe-dispatch line))))))

(defun dl-satan-patch-listener--report-death (status code stderr-tail)
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
           :app-name dl-satan-patch-listener-notify-app))
      (error
       (message "dl-satan-patch-listener: notify failed: %s"
                (error-message-string err))))))

(defun dl-satan-patch-listener--stderr-tail (buf)
  "Return the last 10 lines of BUF as a string, or nil."
  (when (buffer-live-p buf)
    (with-current-buffer buf
      (let ((lines (split-string (buffer-string) "\n" t)))
        (when lines
          (mapconcat #'identity (last lines 10) "\n"))))))

(defun dl-satan-patch-listener--sentinel (proc _event)
  "Sentinel: on exit/signal, report loudly and clear the procvar."
  (when (memq (process-status proc) '(exit signal))
    (let* ((stderr-buf  (process-get proc 'stderr-buffer))
           (stderr-tail (dl-satan-patch-listener--stderr-tail stderr-buf))
           (status      (process-status proc))
           (code        (process-exit-status proc)))
      (dl-satan-patch-listener--report-death status code stderr-tail)
      (when (buffer-live-p stderr-buf) (kill-buffer stderr-buf))
      (when (eq proc dl-satan-patch-listener--proc)
        (setq dl-satan-patch-listener--proc nil)))))

;; ---------------------------------------------------------------------
;; public API
;; ---------------------------------------------------------------------

;;;###autoload
(defun dl-satan-patch-listener-start ()
  "Spawn the `satan-attrd notify-stream' subprocess if enabled.
No-op when already running.  Returns the process, or nil if disabled
or the program is missing."
  (interactive)
  (cond
   ((not dl-satan-patch-listener-enabled) nil)
   ((process-live-p dl-satan-patch-listener--proc)
    dl-satan-patch-listener--proc)
   (t
    (let* ((prog dl-satan-patch-listener-program)
           (db   dl-satan-patch-store-database)
           (host dl-satan-patch-store-host)
           (database-url (format "postgres:///%s?host=%s" db host))
           (process-environment
            (cons (concat "DATABASE_URL=" database-url) process-environment))
           (stderr (generate-new-buffer
                    (format " *dl-satan-patch-listener-stderr*")))
           (proc (make-process
                  :name "dl-satan-patch-listener"
                  :command (append (list prog "notify-stream")
                                   dl-satan-patch-listener--channels)
                  :connection-type 'pipe
                  :coding 'utf-8
                  :noquery t
                  :stderr stderr
                  :filter (dl-satan-patch-listener--make-filter)
                  :sentinel #'dl-satan-patch-listener--sentinel)))
      (process-put proc 'stderr-buffer stderr)
      (setq dl-satan-patch-listener--proc proc)
      proc))))

;;;###autoload
(defun dl-satan-patch-listener-stop ()
  "Stop the LISTEN subprocess if running.  Idempotent."
  (interactive)
  (when (process-live-p dl-satan-patch-listener--proc)
    (let ((stderr-buf (process-get dl-satan-patch-listener--proc 'stderr-buffer)))
      (set-process-sentinel dl-satan-patch-listener--proc #'ignore)
      (delete-process dl-satan-patch-listener--proc)
      (when (buffer-live-p stderr-buf) (kill-buffer stderr-buf))))
  (setq dl-satan-patch-listener--proc nil))

;;;###autoload
(defun dl-satan-patch-listener-status ()
  "Return `running', `stopped', or `dead' depending on the listener.
When called interactively, also `message' the same."
  (interactive)
  (let ((state
         (cond
          ((process-live-p dl-satan-patch-listener--proc) 'running)
          ((null dl-satan-patch-listener--proc)           'stopped)
          (t                                              'dead))))
    (when (called-interactively-p 'interactive)
      (message "dl-satan-patch-listener: %s%s"
               state
               (if (eq state 'running)
                   (format " (pid=%s)"
                           (process-id dl-satan-patch-listener--proc))
                 "")))
    state))

(when (and (not noninteractive) dl-satan-patch-listener-enabled)
  (dl-satan-patch-listener-start))

(provide 'dl-satan-patch-listener)
;;; dl-satan-patch-listener.el ends here
