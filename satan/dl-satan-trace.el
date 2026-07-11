;;; dl-satan-trace.el --- Tick telemetry core: stage/tick macros + subprocess ledger -*- lexical-binding: t; -*-

;; SL-011 telemetry core.  A pure, dependency-light instrumentation
;; substrate for the SATAN tick: per-stage timing, a per-tick roll-up
;; row, and a subprocess ledger — all appended as JSONL to a
;; day-bucketed file under the XDG state dir.
;;
;; Design posture (locked design §1):
;;   - Telemetry NEVER fails the tick.  Every write path is wrapped in
;;     a `condition-case' that swallows errors and `message's them; no
;;     signal escapes the writer.
;;   - The macros are transparent passthroughs.  When no accumulator is
;;     dynamically bound (the MCP boot path, unit tests, any non-tick
;;     caller) `dl-satan-trace-stage' runs BODY and records nothing.
;;   - No psql, no subprocess in the write path.
;;
;; This module owns the mechanism only; call sites are converted in a
;; later phase.  `dl-satan-trace--current' is let-bound by
;; `dl-satan-trace-with-tick' for the dynamic extent of one tick and is
;; the sole shared mutable state.

(require 'dl-satan-jsonl)
(require 'cl-lib)
(require 'json)

(defgroup dl-satan-trace nil
  "Tick telemetry: stage/tick timing and a subprocess ledger."
  :group 'dl-satan)

(defcustom dl-satan-trace-enabled t
  "When non-nil, telemetry rows are written.
House convention: every new mechanism ships a kill switch.  When nil
the writer no-ops and the macros still run BODY as pure passthroughs."
  :type 'boolean :group 'dl-satan-trace)

(defcustom dl-satan-trace-dir
  (expand-file-name "satan/"
                    (or (getenv "XDG_STATE_HOME")
                        (expand-file-name ".local/state" "~")))
  "Directory holding day-bucketed `tick-trace-<YYYY-MM-DD>.jsonl' files.
Mirrors the XDG state idiom used by the SATAN sensors."
  :type 'directory :group 'dl-satan-trace)

(defcustom dl-satan-trace-tick-budget-seconds 10
  "Wall-clock budget (seconds) for a tick's OPTIONAL stages; nil = unbounded.
Checked before each `dl-satan-trace-stage-optional' body: once elapsed
tick time meets this budget the remaining optional stages shed their
work and record onto the skipped list.  Core stages never skip.  House
convention: nil disables the bound (unbounded tick)."
  :type '(choice (const :tag "Unbounded" nil) number)
  :group 'dl-satan-trace)

(defvar dl-satan-trace--current nil
  "The per-tick accumulator plist, or nil outside a tick.
Dynamically let-bound by `dl-satan-trace-with-tick'.  Slots:
`:t0' (float-time at tick start), `:run-id', `:mode', `:stages'
\(alist of (NAME . MS), newest first), `:skipped' (list of names,
newest first), `:budget-ms' (nil = unbounded) and `:outcome' (a
domain outcome string stamped via `dl-satan-trace-outcome', nil
until stamped).")

;; --- Writer (private) ------------------------------------------

(defun dl-satan-trace--now-iso ()
  "Return an ISO-8601 timestamp for the current instant."
  (format-time-string "%Y-%m-%dT%H:%M:%S%z"))

(defun dl-satan-trace--file ()
  "Return today's day-bucketed trace file path."
  (expand-file-name
   (format "tick-trace-%s.jsonl" (format-time-string "%Y-%m-%d"))
   dl-satan-trace-dir))

(defun dl-satan-trace--write (row)
  "Append ROW as one JSONL line to today's trace file.
No-op when `dl-satan-trace-enabled' is nil.  Creates the directory if
absent.  Posture: this NEVER signals — any error is swallowed and
messaged so telemetry cannot fail the tick."
  (when dl-satan-trace-enabled
    (condition-case err
        (let ((line (json-serialize (dl-satan-jsonl-prepare row))))
          (make-directory dl-satan-trace-dir t)
          (write-region (concat line "\n") nil (dl-satan-trace--file)
                        'append 'silent))
      (error
       (message "dl-satan-trace: write failed: %s"
                (error-message-string err))))))

;; --- Accumulator mutators (private) ----------------------------

(defun dl-satan-trace--record-stage (name ms)
  "Push (NAME . MS) onto the accumulator's stage list, if bound."
  (when dl-satan-trace--current
    (setq dl-satan-trace--current
          (plist-put dl-satan-trace--current :stages
                     (cons (cons name ms)
                           (plist-get dl-satan-trace--current :stages))))))

(defun dl-satan-trace--record-skip (name)
  "Push NAME onto the accumulator's skipped list, if bound."
  (when dl-satan-trace--current
    (setq dl-satan-trace--current
          (plist-put dl-satan-trace--current :skipped
                     (cons name
                           (plist-get dl-satan-trace--current :skipped))))))

(defun dl-satan-trace-outcome (outcome)
  "Stamp OUTCOME (a string) on the current tick accumulator, if bound."
  (when dl-satan-trace--current
    (setq dl-satan-trace--current
          (plist-put dl-satan-trace--current :outcome outcome))))

(defun dl-satan-trace--budget-exhausted-p ()
  "Non-nil when the accumulator carries a budget and elapsed ms meets it.
Returns nil when no budget slot is set (nil = unbounded)."
  (let ((budget (plist-get dl-satan-trace--current :budget-ms))
        (t0 (plist-get dl-satan-trace--current :t0)))
    (and budget t0
         (>= (round (* 1000 (- (float-time) t0))) budget))))

;; --- Macros (passthrough contract) -----------------------------

(defmacro dl-satan-trace-stage (name &rest body)
  "Time BODY, record (NAME . MS) on the accumulator, return BODY's value.
When no accumulator is bound (`dl-satan-trace--current' nil) run BODY
as a pure passthrough and record nothing."
  (declare (indent 1) (debug (form body)))
  (let ((start (make-symbol "start")))
    `(if dl-satan-trace--current
         (let ((,start (float-time)))
           (prog1 (progn ,@body)
             (dl-satan-trace--record-stage
              ,name (round (* 1000 (- (float-time) ,start))))))
       (progn ,@body))))

(defmacro dl-satan-trace-stage-optional (name &rest body)
  "Like `dl-satan-trace-stage', but honour the tick budget.
When an accumulator is bound AND its budget is exhausted, skip BODY,
record NAME onto the skipped list, and return nil.  When no accumulator
is bound OR the budget slot is nil, run BODY (passthrough)."
  (declare (indent 1) (debug (form body)))
  (let ((start (make-symbol "start")))
    `(cond
      ((and dl-satan-trace--current (dl-satan-trace--budget-exhausted-p))
       (dl-satan-trace--record-skip ,name)
       nil)
      (dl-satan-trace--current
       (let ((,start (float-time)))
         (prog1 (progn ,@body)
           (dl-satan-trace--record-stage
            ,name (round (* 1000 (- (float-time) ,start)))))))
      (t (progn ,@body)))))

(defun dl-satan-trace--stages-map (stages)
  "Coerce STAGES alist of (NAME . MS) into a string-keyed alist.
Keys are stringified so `dl-satan-jsonl-prepare' encodes a JSON object.
Every entry is preserved — stages may nest, so duplicate names may
appear and Σ stages need not equal total_ms."
  (mapcar (lambda (s) (cons (format "%s" (car s)) (cdr s))) stages))

(defun dl-satan-trace--flush-tick (outcome)
  "Emit exactly one kind:\"tick\" row for the bound accumulator.
OUTCOME is a string — a stamped domain outcome (see
`dl-satan-trace-outcome') or the \"ok\" / \"error\" fallback.
Computes total_ms from `:t0'
and orders stages/skipped in the sequence they were recorded."
  (when dl-satan-trace--current
    (let* ((acc dl-satan-trace--current)
           (t0 (plist-get acc :t0))
           (total-ms (round (* 1000 (- (float-time) t0))))
           (budget (plist-get acc :budget-ms))
           (stages (nreverse (copy-sequence (plist-get acc :stages))))
           (skipped (nreverse (copy-sequence (plist-get acc :skipped)))))
      (dl-satan-trace--write
       (list :kind "tick"
             :run_id (plist-get acc :run-id)
             :mode (plist-get acc :mode)
             :ts (dl-satan-trace--now-iso)
             :total_ms total-ms
             :budget_ms budget
             :budget_breached (if (and budget (> total-ms budget)) t :false)
             :stages (dl-satan-trace--stages-map stages)
             :skipped (or skipped (vector))
             :outcome outcome)))))

(defmacro dl-satan-trace-with-tick (run-id mode &rest body)
  "Bind a fresh tick accumulator for RUN-ID / MODE, run BODY, flush once.
The single kind:\"tick\" row is flushed inside `unwind-protect' so an
error or other non-local exit still emits exactly one row.  The flushed
outcome is whatever BODY stamped via `dl-satan-trace-outcome', falling
back to \"ok\" / \"error\" when nothing was stamped.  Returns BODY's
value."
  (declare (indent 2) (debug (form form body)))
  (let ((ok (make-symbol "ok")))
    `(let ((dl-satan-trace--current
            (list :t0 (float-time) :run-id ,run-id :mode ,mode
                  :stages nil :skipped nil
                  :budget-ms (and dl-satan-trace-tick-budget-seconds
                                  (round (* 1000 dl-satan-trace-tick-budget-seconds)))
                  :outcome nil))
           (,ok nil))
       (unwind-protect
           (prog1 (progn ,@body)
             (setq ,ok t))
         (dl-satan-trace--flush-tick
          (or (plist-get dl-satan-trace--current :outcome)
              (if ,ok "ok" "error")))))))

;; --- Subprocess ledger -----------------------------------------

(defun dl-satan-trace-subprocess (argv cwd ms exit &optional timed-out label)
  "Append one kind:\"subprocess\" ledger row for a completed call.
ARGV is the LOGICAL program+args (any `timeout' wrapper already
stripped).  RUN-ID is taken from the bound accumulator, else nil.
LABEL is an optional caller-supplied tag."
  (dl-satan-trace--write
   (list :kind "subprocess"
         :run_id (and dl-satan-trace--current
                      (plist-get dl-satan-trace--current :run-id))
         :ts (dl-satan-trace--now-iso)
         :argv argv
         :label label
         :cwd cwd
         :ms ms
         :exit exit
         :timed_out (if timed-out t :false))))

(cl-defun dl-satan-trace-call (program args
                                       &key stdin cwd timeout-secs env label)
  "Run PROGRAM ARGS, ledger the call, return (:exit N :stdout STR :timed-out BOOL).

ENV is a list of \"VAR=VAL\" strings prepended to `process-environment'.
STDIN, when non-nil, is fed to the child via `call-process-region'.
CWD, when non-nil, becomes `default-directory' for the run.
TIMEOUT-SECS non-nil wraps the invocation as
`timeout -k 2 SECS PROGRAM ARGS...' (SIGKILL 2s after SIGTERM so a
TERM-ignoring child still dies); nil runs UNWRAPPED.  A timeout maps
exit 124 to `:timed-out t'; the wrapper's own 125/126/127 map honestly
to `:exit' and NEVER to `:timed-out'.  The ledger row logs the LOGICAL
PROGRAM+ARGS (wrapper prefix stripped) plus LABEL / CWD / ms / exit /
timed_out."
  (let* ((real-program (if timeout-secs "timeout" program))
         (real-args (if timeout-secs
                        (append (list "-k" "2"
                                      (number-to-string timeout-secs)
                                      program)
                                args)
                      args))
         (process-environment (append env process-environment))
         (default-directory (if cwd
                                (file-name-as-directory cwd)
                              default-directory))
         (t0 (float-time))
         (stdout "")
         (exit
          (with-temp-buffer
            (prog1
                (if stdin
                    (apply #'call-process-region stdin nil real-program
                           nil t nil real-args)
                  (apply #'call-process real-program nil t nil real-args))
              (setq stdout (buffer-string)))))
         (ms (round (* 1000 (- (float-time) t0))))
         (timed-out (eql exit 124)))
    (dl-satan-trace-subprocess (vconcat (cons program args))
                               cwd ms exit timed-out label)
    (list :exit exit :stdout stdout :timed-out timed-out)))

(provide 'dl-satan-trace)
;;; dl-satan-trace.el ends here
