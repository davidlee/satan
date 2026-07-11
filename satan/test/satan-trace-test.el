;;; satan-trace-test.el --- ert tests for satan-trace -*- lexical-binding: t; -*-

;; SL-011 PHASE-02.  Telemetry core: stage/tick macros, subprocess
;; ledger, bounded trace-call.
;;
;; VT-1 (satan-trace-stage / satan-trace-with-tick): stage macro
;;   accumulates ms and returns BODY's value; passthrough returns the
;;   value and records nothing when no accumulator is bound; with-tick
;;   flushes exactly one tick row on the ERROR path via unwind-protect.
;; VT-2 (satan-trace-call / timed-out): a runaway child is killed by
;;   the timeout wrapper and reports :timed-out t; :env reaches the
;;   child; :timeout-secs nil runs unwrapped (no timeout prefix in the
;;   ledger argv); :label lands on the row.
;; EX-2: a write failure never signals out of the stage/tick path.

(require 'ert)
(require 'cl-lib)
(require 'json)
(require 'satan-trace)

;; Required at runtime by the EX-2 shared-fn test only (PHASE-04): the
;; enrich path is the wrapped shared fn under test.
(declare-function satan-run-enrich "satan-context" (prepare))

;; --- Helpers ---------------------------------------------------

(defmacro satan-trace-test--with-dir (dir-var &rest body)
  "Bind `satan-trace-dir' to a fresh temp DIR-VAR, run BODY, clean up."
  (declare (indent 1))
  `(let* ((,dir-var (make-temp-file "satan-trace-test-" t))
          (satan-trace-dir ,dir-var)
          (satan-trace-enabled t))
     (unwind-protect
         (progn ,@body)
       (when (file-directory-p ,dir-var)
         (delete-directory ,dir-var t)))))

(defun satan-trace-test--rows (dir)
  "Read every JSONL row written under DIR today as a list of plists."
  (let ((file (expand-file-name
               (format "tick-trace-%s.jsonl" (format-time-string "%Y-%m-%d"))
               dir)))
    (when (file-readable-p file)
      (satan-jsonl-read-file file))))

(defun satan-trace-test--rows-of-kind (dir kind)
  "Rows under DIR today whose :kind equals KIND."
  (cl-remove-if-not (lambda (r) (equal (plist-get r :kind) kind))
                    (satan-trace-test--rows dir)))

;; --- VT-1: stage + with-tick -----------------------------------

(ert-deftest satan-trace-stage-returns-body-value-and-accumulates ()
  "`satan-trace-stage' returns BODY's value and records (name . ms)."
  (satan-trace-test--with-dir dir
    (satan-trace-with-tick "run-1" "wake"
      (should (= 42 (satan-trace-stage "compute" (+ 40 2))))
      (should (assoc "compute"
                     (mapcar (lambda (s) (cons (format "%s" (car s)) (cdr s)))
                             (plist-get satan-trace--current :stages)))))))

(ert-deftest satan-trace-stage-passthrough-records-nothing ()
  "With no accumulator bound, `satan-trace-stage' is a pure passthrough."
  (let ((satan-trace--current nil))
    (should (equal "v" (satan-trace-stage "x" (concat "v"))))
    (should (null satan-trace--current))))

(ert-deftest satan-trace-with-tick-flushes-one-row-on-error ()
  "`satan-trace-with-tick' flushes exactly one tick row on the ERROR path."
  (satan-trace-test--with-dir dir
    (should-error
     (satan-trace-with-tick "run-err" "wake"
       (error "boom")))
    (let ((ticks (satan-trace-test--rows-of-kind dir "tick")))
      (should (= 1 (length ticks)))
      (should (equal "error" (plist-get (car ticks) :outcome)))
      (should (equal "run-err" (plist-get (car ticks) :run_id))))))

(ert-deftest satan-trace-with-tick-flushes-one-row-on-success ()
  "Happy path also flushes exactly one tick row, outcome ok."
  (satan-trace-test--with-dir dir
    (should (= 7 (satan-trace-with-tick "run-ok" "wake"
                   (satan-trace-stage "s" 7))))
    (let ((ticks (satan-trace-test--rows-of-kind dir "tick")))
      (should (= 1 (length ticks)))
      (should (equal "ok" (plist-get (car ticks) :outcome))))))

(ert-deftest satan-trace-with-tick-honours-stamped-outcome ()
  "A domain outcome stamped via `satan-trace-outcome' wins over ok/error."
  (satan-trace-test--with-dir dir
    (satan-trace-with-tick "run-st" "wake"
      (satan-trace-outcome "budget_denied")
      nil)
    (let ((ticks (satan-trace-test--rows-of-kind dir "tick")))
      (should (= 1 (length ticks)))
      (should (equal "budget_denied" (plist-get (car ticks) :outcome))))))

(ert-deftest satan-trace-outcome-noop-without-accumulator ()
  "`satan-trace-outcome' outside a tick is a no-op, not an error."
  (let ((satan-trace--current nil))
    (satan-trace-outcome "spawned")
    (should (null satan-trace--current))))

(ert-deftest satan-trace-tick-row-shape ()
  "VT-2: the tick row shape — kind \"tick\", stages a NAME→ms map,
skipped an array, budget flags present."
  (satan-trace-test--with-dir dir
    (satan-trace-with-tick "run-shape" "wake"
      (satan-trace-stage "alpha" (+ 1 2))
      (satan-trace-stage "beta" (+ 3 4)))
    (let* ((row (car (satan-trace-test--rows-of-kind dir "tick")))
           (stages (plist-get row :stages)))
      (should (equal "tick" (plist-get row :kind)))
      (should (equal "run-shape" (plist-get row :run_id)))
      (should (equal "wake" (plist-get row :mode)))
      ;; stages: JSON object of NAME → ms (decoded as a keyword plist).
      (should (integerp (plist-get stages :alpha)))
      (should (integerp (plist-get stages :beta)))
      ;; skipped: JSON array (decoded as a list; empty here).
      (should (plist-member row :skipped))
      (should (listp (plist-get row :skipped)))
      ;; budget flags present even when no budget was set.
      (should (plist-member row :budget_ms))
      (should (memq (plist-get row :budget_breached) '(:false t)))
      (should (integerp (plist-get row :total_ms))))))

(ert-deftest satan-trace-stage-optional-skips-when-budget-exhausted ()
  "`satan-trace-stage-optional' skips BODY + records skip when budget spent."
  (satan-trace-test--with-dir dir
    (let ((ran nil))
      (satan-trace-with-tick "run-b" "wake"
        ;; Force an already-exhausted budget: 0ms budget, elapsed >= 0.
        (setq satan-trace--current
              (plist-put satan-trace--current :budget-ms 0))
        (should (null (satan-trace-stage-optional "opt" (setq ran t))))
        (should (null ran))
        (should (member "opt"
                        (mapcar (lambda (n) (format "%s" n))
                                (plist-get satan-trace--current :skipped))))))))

(ert-deftest satan-trace-stage-optional-runs-when-no-budget ()
  "With budget nil the optional stage runs BODY (passthrough)."
  (satan-trace-test--with-dir dir
    (let ((ran nil))
      (satan-trace-with-tick "run-nb" "wake"
        (should (equal 9 (satan-trace-stage-optional "opt" (setq ran 9))))
        (should (= 9 ran))))))

;; --- VT-2: trace-call ------------------------------------------

(ert-deftest satan-trace-call-times-out-runaway-child ()
  "A runaway child is killed by the timeout wrapper well under its sleep."
  (satan-trace-test--with-dir dir
    (let* ((t0 (float-time))
           (res (satan-trace-call "sleep" '("10") :timeout-secs 1))
           (elapsed (- (float-time) t0)))
      (should (eq t (plist-get res :timed-out)))
      (should (= 124 (plist-get res :exit)))
      (should (< elapsed 8)))))

(ert-deftest satan-trace-call-env-reaches-child ()
  "`:env' entries are visible to the child process."
  (satan-trace-test--with-dir dir
    (let ((res (satan-trace-call
                "sh" '("-c" "printf %s \"$FOO\"")
                :env '("FOO=bar"))))
      (should (equal "bar" (plist-get res :stdout)))
      (should (= 0 (plist-get res :exit))))))

(ert-deftest satan-trace-call-unwrapped-when-timeout-nil ()
  "`:timeout-secs' nil runs unwrapped: ledger argv carries no timeout prefix."
  (satan-trace-test--with-dir dir
    (satan-trace-call "true" '() :timeout-secs nil :label "probe")
    (let* ((rows (satan-trace-test--rows-of-kind dir "subprocess"))
           (row (car rows))
           (argv (append (plist-get row :argv) nil)))
      (should (= 1 (length rows)))
      (should (equal "true" (car argv)))
      (should-not (member "timeout" argv))
      (should (equal "probe" (plist-get row :label))))))

(ert-deftest satan-trace-call-ledger-strips-timeout-prefix ()
  "Even when wrapped, the ledger logs the logical program, not `timeout'."
  (satan-trace-test--with-dir dir
    (satan-trace-call "true" '() :timeout-secs 5 :label "wrapped")
    (let* ((row (car (satan-trace-test--rows-of-kind dir "subprocess")))
           (argv (append (plist-get row :argv) nil)))
      (should (equal "true" (car argv)))
      (should-not (member "timeout" argv))
      (should (equal "wrapped" (plist-get row :label))))))

;; --- EX-2: telemetry never fails the tick ----------------------

(ert-deftest satan-trace-write-failure-never-signals ()
  "An unwritable trace dir does not signal out of the stage/tick path."
  (let ((satan-trace-dir "/proc/nonexistent-satan-trace/deeper")
        (satan-trace-enabled t))
    ;; No accumulator: the subprocess writer still must swallow the error.
    (should-not
     (condition-case err
         (progn (satan-trace-subprocess ["true"] nil 1 0 nil "l") nil)
       (error err)))
    ;; With an accumulator: the tick flush must not propagate the failure.
    (should
     (= 5 (satan-trace-with-tick "run-w" "wake"
            (satan-trace-stage "s" 5))))))

(ert-deftest satan-trace-ex2-wrapped-shared-fn-writes-no-tick-row ()
  "EX-2: a stage-wrapped shared fn with NO accumulator bound writes NO tick row.
`satan-run-enrich' (the shared enrich path, also called on the MCP
boot path) carries `satan-trace-stage' wraps at its call sites; with
no tick accumulator bound they are pure passthroughs and nothing is
written.  The inner derive/read fns are stubbed — the subject is the
wrap, not the enrichment."
  (require 'satan-context)
  (satan-trace-test--with-dir dir
    (let ((satan-trace--current nil))
      (cl-letf (((symbol-function 'satan-resonance-derive)
                 (lambda (_percept) (list :status 'none)))
                ((symbol-function 'satan-motive-read)
                 (lambda (_file) nil)))
        (satan-run-enrich (list :percept nil)))
      (should (null (satan-trace-test--rows dir))))))

(provide 'satan-trace-test)
;;; satan-trace-test.el ends here
