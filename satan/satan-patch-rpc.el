;;; satan-patch-rpc.el --- client for the patch runner's control socket -*- lexical-binding: t; -*-

;; SL-023 (DEC-058): the malebolge patch runner owns patch jobs; Emacs
;; reaches it over one NDJSON unix socket.  This module is the only
;; client: the tools, the inbox watch and promotion all go through it.
;;
;;   satan-patch-rpc-call        one request, one fresh connection, a
;;                               bounded deadline, never retried
;;   satan-patch-rpc-watch-open  a persistent `watch' connection
;;   satan-patch-rpc-project     a wire job (camelCase) as the model and
;;                               the inbox see it (snake_case)
;;
;; Fail closed: an unreachable runner, a missed deadline, a dropped
;; connection or a garbled answer is an error, never a guess.  A
;; request whose answer was lost may still have taken effect, so
;; nothing here retries.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'satan-custom)
(require 'satan-jsonl)

(defcustom satan-patch-rpc-socket nil
  "The patch runner's control socket; nil means the runner's default.
The default is $XDG_RUNTIME_DIR/satan-runner/control.sock, resolved at
call time: a runtime location outside SATAN's three roots, like the MCP
socket."
  :type '(choice (const :tag "Runner default" nil) file)
  :group 'satan)

(defcustom satan-patch-rpc-timeout 5
  "Seconds `satan-patch-rpc-call' waits for the runner's answer."
  :type 'number
  :group 'satan)

(defun satan-patch-rpc--socket-path ()
  "The control socket's path, or nil when it cannot be known."
  (or satan-patch-rpc-socket
      (when-let* ((runtime (getenv "XDG_RUNTIME_DIR")))
        (expand-file-name "satan-runner/control.sock" runtime))))

(defun satan-patch-rpc--unreachable (why)
  "The error for a runner that did not answer, saying WHY."
  (cons 'error (format "patch runner unreachable: %s" why)))

(defun satan-patch-rpc--fault (err)
  "ERR, a fault reaching the runner, as a short message.
A connection's `file-error' carries the connection's whole argument
list after its reason strings; keep the reasons and name the socket."
  (if (memq 'file-error (get (car err) 'error-conditions))
      (format "%s (%s)"
              (string-join (seq-take-while #'stringp (cdr err)) ": ")
              (or (satan-patch-rpc--socket-path) "no socket path"))
    (error-message-string err)))

(defun satan-patch-rpc-new-id ()
  "A fresh id: a requestId, or a submit's submissionId."
  (format "sat-%s-%06x"
          (format-time-string "%Y%m%dT%H%M%S%6N" nil t)
          (random #x1000000)))

(defun satan-patch-rpc--connect (name filter sentinel)
  "Open connection NAME to the runner with FILTER and SENTINEL.
Signals `file-error' when there is no runner to connect to."
  (let ((path (satan-patch-rpc--socket-path)))
    (unless path
      (signal 'file-error (list "XDG_RUNTIME_DIR is unset")))
    (make-network-process
     :name name :family 'local :service path :coding 'utf-8
     :noquery t :filter filter :sentinel sentinel)))

(defun satan-patch-rpc--garbled (text)
  "The message for a line TEXT that is not JSON."
  (format "patch runner protocol error: unparseable line %S" text))

(defun satan-patch-rpc--refusal (response)
  "The error for an ok:false RESPONSE: its code and message."
  (let ((err (plist-get response :error)))
    (cons 'error (format "%s: %s" (plist-get err :code) (plist-get err :message)))))

(defun satan-patch-rpc--body (response)
  "RESPONSE without its envelope keys (`:requestId', `:ok')."
  (cl-loop for (key value) on response by #'cddr
           unless (memq key '(:requestId :ok))
           append (list key value)))

(defun satan-patch-rpc--answer (request-id line open-p)
  "The call's result from LINE, the first thing read for REQUEST-ID.
LINE is (json . PLIST), (garbled . TEXT), or nil when nothing came;
OPEN-P says whether the connection was still open (the deadline passed)."
  (pcase line
    ('nil
     (satan-patch-rpc--unreachable
      (if open-p
          (format "no response within %ss" satan-patch-rpc-timeout)
        "connection closed without a response")))
    (`(garbled . ,text)
     (cons 'error (satan-patch-rpc--garbled text)))
    (`(json . ,response)
     (pcase (plist-get response :ok)
       (:false (satan-patch-rpc--refusal response))
       ('t (if (equal (plist-get response :requestId) request-id)
               (cons 'ok (satan-patch-rpc--body response))
             (cons 'error (format "patch runner protocol error: requestId %S, sent %S"
                                  (plist-get response :requestId) request-id))))
       (_ (cons 'error (format "patch runner protocol error: %S" response)))))))

(defun satan-patch-rpc-call (op &optional fields)
  "Send OP with FIELDS (a plist) to the runner; wait for its answer.
Returns `(ok . BODY)', BODY the answer's plist without its envelope, or
`(error . MSG)': MSG is \"<code>: <message>\" for a refusal, and
starts \"patch runner unreachable\" when no answer came within
`satan-patch-rpc-timeout'.  One fresh connection per call; never
retried (a lost answer may hide a request that took effect)."
  (let ((request-id (satan-patch-rpc-new-id))
        (deadline (+ (float-time) satan-patch-rpc-timeout))
        line proc)
    (condition-case err
        (unwind-protect
            (progn
              (setq proc (satan-patch-rpc--connect
                          "satan-patch-rpc"
                          (satan-jsonl-make-filter
                           (lambda (obj) (unless line (setq line (cons 'json obj))))
                           (lambda (bad) (unless line (setq line (cons 'garbled (car bad))))))
                          #'ignore))
              (satan-jsonl-send
               proc (append (list :op op :requestId request-id) fields))
              ;; Waiting on PROC returns when it closes, too; JUST-THIS-ONE
              ;; nil still serves every other process, so an in-process
              ;; peer (the test fixture) can answer.
              (while (and (null line) (process-live-p proc)
                          (< (float-time) deadline))
                (accept-process-output proc (- deadline (float-time))))
              (satan-patch-rpc--answer request-id line (process-live-p proc)))
          (when proc (delete-process proc)))
      (error (satan-patch-rpc--unreachable (satan-patch-rpc--fault err))))))

(defun satan-patch-rpc--watch-filter (on-frame on-open close)
  "A watch connection's line handler.
The first line answers the watch: ok calls ON-OPEN, a refusal calls
CLOSE with its message.  Every later line with an `:event' goes to
ON-FRAME."
  (let (answered)
    (lambda (obj)
      (cond
       (answered (when (plist-get obj :event) (funcall on-frame obj)))
       ((eq (plist-get obj :ok) t)
        (setq answered t)
        (when on-open (funcall on-open)))
       (t (funcall close (cdr (satan-patch-rpc--refusal obj))))))))

(defun satan-patch-rpc-watch-open (on-frame on-close &optional on-open)
  "Open a `watch' on the runner.  Returns `(ok . PROCESS)' or `(error . MSG)'.
ON-FRAME is called with each frame plist (`:event', `:job').  ON-OPEN,
when given, is called once the runner accepts the watch.  ON-CLOSE is
called once with a reason string when the connection ends, including
after `delete-process' on PROCESS."
  (let (reason proc)
    (cl-flet ((close (why)
                (setq reason why)
                (delete-process proc)))
      (condition-case err
          (progn
            (setq proc (satan-patch-rpc--connect
                        "satan-patch-watch"
                        (satan-jsonl-make-filter
                         (satan-patch-rpc--watch-filter on-frame on-open #'close)
                         (lambda (bad) (close (satan-patch-rpc--garbled (car bad)))))
                        (lambda (_proc event)
                          (funcall on-close (or reason (string-trim event))))))
            (satan-jsonl-send
             proc (list :op "watch" :requestId (satan-patch-rpc-new-id)))
            (cons 'ok proc))
        (error
         (when proc
           ;; The caller hears of this failure from the return value alone.
           (set-process-sentinel proc #'ignore)
           (delete-process proc))
         (satan-patch-rpc--unreachable (satan-patch-rpc--fault err)))))))

;; ---------------------------------------------------------------------
;; the job as SATAN sees it
;; ---------------------------------------------------------------------

(defconst satan-patch-rpc--job-fields
  '((:jobId . :job_id) (:state . :state) (:mode . :mode) (:repo . :repo)
    (:baseRef . :base_ref) (:class . :class) (:endReason . :end_reason)
    (:reviewedOid . :reviewed_oid) (:createdAt . :created_at)
    (:updatedAt . :updated_at) (:failure . :failure) (:baseOid . :base_oid)
    (:quarantine . :quarantine) (:quarantineRef . :quarantine_ref)
    (:commits . :commits) (:diffstat . :diffstat))
  "Wire keys of a job summary or `result' body, and their projected names.")

(defconst satan-patch-rpc--client-fields
  '((:announcedAt . :announced_at) (:repoPath . :repo_path))
  "Wire keys only Emacs itself reads (the inbox and promotion).
Kept from the model: the real repo path is runner config, and whether a
notice was announced is the inbox's business.")

(defun satan-patch-rpc-field (job key)
  "JOB's value for KEY, or nil when it is absent, null or empty."
  (let ((value (plist-get job key)))
    (unless (or (eq value :null) (equal value "")) value)))

(defun satan-patch-rpc-project (job &optional client)
  "JOB, a summary or `result' body, as snake_case for the model and the inbox.
Only fields JOB carries appear.  Once the class is known, `:partial' says
whether it is \"partial\" as t or `:false' (never nil, which would cross
the wire as {}).  `result' usage becomes `:model_requests'.  CLIENT
non-nil adds the fields only Emacs reads (`satan-patch-rpc--client-fields')."
  (append
   (cl-loop for (wire . name) in (append satan-patch-rpc--job-fields
                                         (when client satan-patch-rpc--client-fields))
            when (plist-member job wire)
            append (list name (plist-get job wire)))
   (when-let* ((class (plist-get job :class)))
     (list :partial (if (equal class "partial") t :false)))
   (when-let* ((usage (plist-get job :usage)))
     (list :model_requests (plist-get usage :modelRequests)))))

(provide 'satan-patch-rpc)
;;; satan-patch-rpc.el ends here
