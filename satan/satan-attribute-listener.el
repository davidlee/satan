;;; satan-attribute-listener.el --- LISTEN satan_audit_inbox -*- lexical-binding: t; -*-

;; Long-running `satan-attrd notify-stream' subprocess that LISTENs on
;; the daemon → broker audit-event queue.  On notify the listener
;; claims the inbox row, runs the §5.1 validator
;; (`satan-audit-validate-attribute-event'), and either:
;;
;;   accept → append `attribute.delta_applied' to the run's transcript.jsonl
;;            (the canonical audit-truth surface — design-contract §17.1)
;;            and DELETE the inbox row.
;;
;;   reject → INSERT (inbox_id, error_msg) into satan_audit_replies,
;;            DELETE the inbox row, NOTIFY satan_audit_reply <inbox_id>.
;;            Daemon logs ERROR per §17.4 log-and-drop.
;;
;; Transport rationale: a raw `psql ... LISTEN ...' subprocess buffers
;; async notifications until the next stdin command, so notifies never
;; surface in a long-running pipe consumer.  `satan-attrd notify-stream'
;; holds a real libpq connection (via tokio-postgres in the daemon
;; binary) and writes one JSON line per notification, flushed.

(require 'cl-lib)
(require 'json)
(require 'rx)
(require 'subr-x)
(require 'satan-audit)
(require 'satan-attribute)
(require 'satan-jsonl)

(declare-function notifications-notify "notifications" (&rest args))
(declare-function satan-broker-locate-run-dir "satan-broker"
                  (run-id &optional runs-dir))

;; ---------------------------------------------------------------------
;; customisation
;; ---------------------------------------------------------------------

(defcustom satan-attribute-listener-enabled t
  "When non-nil, `satan-attribute-listener-start' spawns the LISTEN process.
Set to nil to disable the postgres LISTEN bridge and rely on the broker's
manual transcript-write path."
  :type 'boolean :group 'satan-attribute)

(defcustom satan-attribute-listener-notify-app "SATAN"
  "Application name used for the D-Bus death notification."
  :type 'string :group 'satan-attribute)

(defcustom satan-attribute-listener-program
  (or (executable-find "satan-attrd") "satan-attrd")
  "Path to the `satan-attrd' binary used as the LISTEN transport."
  :type 'string :group 'satan-attribute)

;; ---------------------------------------------------------------------
;; internals
;; ---------------------------------------------------------------------

(defvar satan-attribute-listener--proc nil
  "Live LISTEN subprocess, or nil.")

(defconst satan-attribute-listener--channels
  '("satan_audit_inbox")
  "Channels we subscribe to.  Daemon writes audit events here.")

(defun satan-attribute-listener--parse-line (line)
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

(defun satan-attribute-listener--claim-row (inbox-id)
  "Atomically claim INBOX-ID's row.  Return its parsed payload plist on
success, nil on race (already claimed), or signal an error on DB failure."
  (let* ((sql (concat
               "WITH claimed AS ("
               "  UPDATE satan_audit_inbox "
               "  SET claimed_at = NOW() "
               "  WHERE id = :'id' AND claimed_at IS NULL "
               "  RETURNING payload_json::text"
               ") SELECT payload_json FROM claimed"))
         (result (satan-db-query
                  satan-attribute-database
                  satan-attribute-host
                  satan-attribute-psql-program
                  sql `(("id" . ,inbox-id)))))
    (pcase result
      (`(ok . ,out)
       (cond
        ((string-empty-p out) nil)
        (t (condition-case err
               ;; `:null-object :null' + `:array-type 'array' for
               ;; lossless round-trip: JSON `null' and `[]' both decode
               ;; as elisp `nil' otherwise (default `:null-object nil',
               ;; default `:array-type list'), and `json-serialize'
               ;; re-emits `nil' as `{}'.  Vectors round-trip as JSON
               ;; arrays; `:null' as JSON null.  Validators downstream
               ;; (`satan-audit--iv-require-array') accept both.
               (json-parse-string out
                                  :object-type 'plist
                                  :array-type 'array
                                  :null-object :null
                                  :false-object :false)
             (error
              (error "satan-attribute-listener: bad JSON in row %s: %s"
                     inbox-id (error-message-string err)))))))
      (`(error . ,msg)
       (error "satan-attribute-listener: claim %s failed: %s" inbox-id msg)))))

(defun satan-attribute-listener--delete-row (inbox-id)
  "DELETE the inbox row.  Returns nil; logs on failure."
  (let* ((sql "DELETE FROM satan_audit_inbox WHERE id = :'id'")
         (result (satan-db-query
                  satan-attribute-database
                  satan-attribute-host
                  satan-attribute-psql-program
                  sql `(("id" . ,inbox-id)))))
    (pcase result
      (`(error . ,msg)
       (message "satan-attribute-listener: delete %s failed: %s" inbox-id msg))
      (_ nil))))

(defun satan-attribute-listener--reject (inbox-id err-msg)
  "Record a broker-side reject (§17.4): write satan_audit_replies row,
DELETE the inbox row, NOTIFY satan_audit_reply.  Daemon LISTENs the
reply channel and logs the rejection."
  (let* ((sql (concat
               "WITH ins AS ("
               "  INSERT INTO satan_audit_replies (inbox_id, error_msg) "
               "  VALUES (:'id', :'msg') "
               "  RETURNING inbox_id"
               "), del AS ("
               "  DELETE FROM satan_audit_inbox WHERE id = :'id'"
               ") "
               "SELECT pg_notify('satan_audit_reply', inbox_id::text) "
               "FROM ins"))
         (result (satan-db-query
                  satan-attribute-database
                  satan-attribute-host
                  satan-attribute-psql-program
                  sql `(("id" . ,inbox-id) ("msg" . ,err-msg)))))
    (pcase result
      (`(error . ,msg)
       (message "satan-attribute-listener: reject-record %s failed: %s"
                inbox-id msg))
      (_ nil))))

(defun satan-attribute-listener--check-schema (payload)
  "Return nil if PAYLOAD's `schema_version' major matches the broker's
compiled value, or an error string otherwise."
  (let ((sv (plist-get payload :schema_version)))
    (cond
     ((null sv) "missing schema_version")
     ((not (stringp sv)) (format "schema_version must be string: %S" sv))
     (t
      (let* ((major-str (car (split-string sv "\\.")))
             (major (and major-str (string-to-number major-str)))
             (want-major (string-to-number
                          (car (split-string
                                satan-attribute-payload-schema-version
                                "\\.")))))
        (cond
         ((not (and major (> major 0)))
          (format "malformed schema_version: %S" sv))
         ((/= major want-major)
          (format "schema_version major %d does not match broker major %d"
                  major want-major))
         (t nil)))))))

(defun satan-attribute-listener--run-id-from-payload (payload)
  "Return the run-id encoded in PAYLOAD's `:id' (`<run-id>.attr<NNN>'),
or nil if the shape is unexpected."
  (let* ((id (plist-get payload :id)))
    (when (stringp id)
      (let ((dot (string-match "\\.attr[0-9]+\\'" id)))
        (when dot (substring id 0 dot))))))

(defun satan-attribute-listener--transcript-path (run-id)
  "Return absolute path to RUN-ID's transcript.jsonl, or nil if no run
directory exists."
  (let ((dir (satan-broker-locate-run-dir run-id)))
    (when dir (expand-file-name "transcript.jsonl" dir))))

(defun satan-attribute-listener--append-transcript (payload)
  "Append PAYLOAD as one `attribute.delta_applied' line to the matching
run's transcript.jsonl.  Returns nil on success or an error string.

Bypasses `satan-audit-record' because the LISTENer does not hold an
audit handle (the handle is owned by the broker run's lifecycle).  The
on-disk line shape is identical."
  (let* ((run-id (satan-attribute-listener--run-id-from-payload payload))
         (path (and run-id (satan-attribute-listener--transcript-path run-id))))
    (cond
     ((null run-id) (format "could not parse run-id from id=%S"
                            (plist-get payload :id)))
     ((null path) (format "no run dir found for run-id %S" run-id))
     ((not (file-exists-p path))
      (format "transcript missing for run-id %S: %s" run-id path))
     (t
      (condition-case err
          (let* ((rec (list :ts (or (plist-get payload :ts)
                                    (format-time-string
                                     "%Y-%m-%dT%H:%M:%S.%6N%z"))
                            :dir "broker"
                            :event "attribute.delta_applied"
                            :payload payload))
                 (line (json-serialize (satan-jsonl-prepare rec)
                                       :null-object :null
                                       :false-object :false))
                 (coding-system-for-write 'utf-8))
            (write-region (concat line "\n") nil path 'append 'silent)
            nil)
        (error (error-message-string err)))))))

(defun satan-attribute-listener--handle (inbox-id)
  "Claim, validate, and dispose of INBOX-ID."
  (condition-case err
      (let ((payload (satan-attribute-listener--claim-row inbox-id)))
        (cond
         ((null payload)
          ;; Already claimed by another consumer or never existed — nothing to do.
          nil)
         (t
          (let* ((schema-err (satan-attribute-listener--check-schema payload))
                 (validator-err
                  (and (null schema-err)
                       (satan-audit-validate-attribute-event
                        "attribute.delta_applied" payload)))
                 (write-err
                  (and (null schema-err) (null validator-err)
                       (satan-attribute-listener--append-transcript payload)))
                 (err-msg (or schema-err validator-err write-err)))
            (if err-msg
                (satan-attribute-listener--reject inbox-id err-msg)
              (satan-attribute-listener--delete-row inbox-id))))))
    (error
     (message "satan-attribute-listener: handler error on %s: %s"
              inbox-id (error-message-string err)))))

(defun satan-attribute-listener--maybe-dispatch (line)
  "If LINE is a satan_audit_inbox notification, dispatch its row."
  (when-let* ((evt (satan-attribute-listener--parse-line line))
              (channel (plist-get evt :channel))
              ((member channel satan-attribute-listener--channels))
              (id (string-to-number (plist-get evt :payload))))
    (when (> id 0)
      (satan-attribute-listener--handle id))))

(defun satan-attribute-listener--make-filter ()
  "Return a stateful filter closure parsing notifications line-by-line."
  (let ((buf ""))
    (lambda (_proc chunk)
      (setq buf (concat buf chunk))
      (let ((lines (split-string buf "\n")))
        (setq buf (car (last lines)))
        (dolist (line (butlast lines))
          (satan-attribute-listener--maybe-dispatch line))))))

(defun satan-attribute-listener--report-death (status code stderr-tail)
  "Log + fire a critical desktop notification for a dead listener."
  (let* ((title (format "satan-attribute listener died (status=%s code=%s)"
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
           :app-name satan-attribute-listener-notify-app))
      (error
       (message "satan-attribute-listener: notify failed: %s"
                (error-message-string err))))))

(defun satan-attribute-listener--stderr-tail (buf)
  "Return last 10 lines of BUF as a string, or nil."
  (when (buffer-live-p buf)
    (with-current-buffer buf
      (let ((lines (split-string (buffer-string) "\n" t)))
        (when lines (mapconcat #'identity (last lines 10) "\n"))))))

(defun satan-attribute-listener--sentinel (proc _event)
  "Sentinel: on exit/signal, report loudly and clear the procvar."
  (when (memq (process-status proc) '(exit signal))
    (let* ((stderr-buf  (process-get proc 'stderr-buffer))
           (stderr-tail (satan-attribute-listener--stderr-tail stderr-buf))
           (status      (process-status proc))
           (code        (process-exit-status proc)))
      (satan-attribute-listener--report-death status code stderr-tail)
      (when (buffer-live-p stderr-buf) (kill-buffer stderr-buf))
      (when (eq proc satan-attribute-listener--proc)
        (setq satan-attribute-listener--proc nil)))))

;; ---------------------------------------------------------------------
;; public API
;; ---------------------------------------------------------------------

;;;###autoload
(defun satan-attribute-listener-start ()
  "Spawn the `satan-attrd notify-stream' subprocess if enabled.
No-op when already running.  Returns the process, or nil if disabled
or the program is missing."
  (interactive)
  (cond
   ((not satan-attribute-listener-enabled) nil)
   ((process-live-p satan-attribute-listener--proc)
    satan-attribute-listener--proc)
   (t
    (let* ((prog satan-attribute-listener-program)
           (db   satan-attribute-database)
           (host satan-attribute-host)
           (database-url (format "postgres:///%s?host=%s" db host))
           (process-environment
            (cons (concat "DATABASE_URL=" database-url) process-environment))
           (stderr (generate-new-buffer
                    (format " *satan-attribute-listener-stderr*")))
           (proc (make-process
                  :name "satan-attribute-listener"
                  :command (append (list prog "notify-stream")
                                   satan-attribute-listener--channels)
                  :connection-type 'pipe
                  :coding 'utf-8
                  :noquery t
                  :stderr stderr
                  :filter (satan-attribute-listener--make-filter)
                  :sentinel #'satan-attribute-listener--sentinel)))
      (process-put proc 'stderr-buffer stderr)
      (setq satan-attribute-listener--proc proc)
      proc))))

;;;###autoload
(defun satan-attribute-listener-stop ()
  "Stop the LISTEN subprocess if running.  Idempotent."
  (interactive)
  (when (process-live-p satan-attribute-listener--proc)
    (let ((stderr-buf (process-get satan-attribute-listener--proc
                                   'stderr-buffer)))
      (set-process-sentinel satan-attribute-listener--proc #'ignore)
      (delete-process satan-attribute-listener--proc)
      (when (buffer-live-p stderr-buf) (kill-buffer stderr-buf))))
  (setq satan-attribute-listener--proc nil))

;;;###autoload
(defun satan-attribute-listener-status ()
  "Return `running', `stopped', or `dead'."
  (interactive)
  (let ((state
         (cond
          ((process-live-p satan-attribute-listener--proc) 'running)
          ((null satan-attribute-listener--proc)           'stopped)
          (t                                                  'dead))))
    (when (called-interactively-p 'interactive)
      (message "satan-attribute-listener: %s%s"
               state
               (if (eq state 'running)
                   (format " (pid=%s)"
                           (process-id satan-attribute-listener--proc))
                 "")))
    state))

(when (and (not noninteractive) satan-attribute-listener-enabled)
  (satan-attribute-listener-start))

(provide 'satan-attribute-listener)
;;; satan-attribute-listener.el ends here
