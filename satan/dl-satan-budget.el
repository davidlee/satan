;;; dl-satan-budget.el --- Daily token ceiling for SATAN -*- lexical-binding: t; -*-

;; Pre-spawn budget gate.  Enumerates today's runs/<run-id>/transcript.jsonl,
;; sums per-run cumulative usage (last usage log event's :tokens_total), and
;; refuses to spawn once the daily ceiling is crossed.  Resets at local
;; midnight because run-ids are prefixed YYYYMMDDT.

(require 'cl-lib)
(require 'json)
(require 'subr-x)
(require 'dl-satan-jsonl)

(declare-function dl-satan-broker-run-dirs-for-date "dl-satan-broker"
  (runs-dir date-prefix))

(defcustom dl-satan-budget-daily-tokens 2500000
  "Maximum tokens SATAN may spend per local day across all runs.
Set to nil to disable the gate."
  :type '(choice (integer :tag "Tokens") (const :tag "Disabled" nil))
  :group 'dl-satan)

(defun dl-satan-budget--today-prefix (&optional time)
  "Return the run-id date prefix for TIME (or now)."
  (format-time-string "%Y%m%dT" time))

(defun dl-satan-budget--run-tokens (run-dir)
  "Return total tokens charged to RUN-DIR by reading its transcript.
The harness emits one usage log per provider call with cumulative
`:tokens_total'; we take the maximum across events to be tolerant of
out-of-order writes."
  (let ((path (expand-file-name "transcript.jsonl" run-dir))
         (max-total 0))
    (when (file-readable-p path)
      (let ((coding-system-for-read 'utf-8))
        (with-temp-buffer
          (insert-file-contents path)
          (goto-char (point-min))
          (while (not (eobp))
            (let ((line (buffer-substring-no-properties
                          (point) (line-end-position))))
              (unless (string-empty-p (string-trim line))
                (let* ((rec (ignore-errors
                              (json-parse-string
                                line :object-type 'plist
                                :array-type 'list
                                :null-object :null :false-object :false)))
                        (event (and rec (plist-get rec :event)))
                        (payload (and rec (plist-get rec :payload))))
                  (when (and (equal event "log")
                          (listp payload)
                          (equal (plist-get payload :kind) "usage"))
                    (let ((tt (plist-get payload :tokens_total)))
                      (when (and (integerp tt) (> tt max-total))
                        (setq max-total tt)))))))
            (forward-line 1)))))
    max-total))

(defun dl-satan-budget-today-total (runs-dir &optional time)
  "Sum tokens charged today under RUNS-DIR.  TIME defaults to now.
Walks both the bucketed layout (`<runs>/<YYYY-MM-DD>/<run-id>') and the
legacy flat layout (`<runs>/<run-id>') via
`dl-satan-broker-run-dirs-for-date'."
  (let ((prefix (dl-satan-budget--today-prefix time))
         (total 0))
    (dolist (dir (dl-satan-broker-run-dirs-for-date runs-dir prefix))
      (setq total (+ total (dl-satan-budget--run-tokens dir))))
    total))

(defun dl-satan-budget-exceeded-p (runs-dir &optional time)
  "Return non-nil if today's spend in RUNS-DIR meets or exceeds the ceiling.
When `dl-satan-budget-daily-tokens' is nil, the gate is disabled."
  (and dl-satan-budget-daily-tokens
    (>= (dl-satan-budget-today-total runs-dir time)
      dl-satan-budget-daily-tokens)))

(provide 'dl-satan-budget)
;;; dl-satan-budget.el ends here
