;;; satan-budget-test.el --- ert tests for satan-budget -*- lexical-binding: t; -*-

;; Run from CLI:
;;   emacs --batch \
;;     -L ~/.emacs.d/core -L ~/.emacs.d/satan -L ~/.emacs.d/satan/test \
;;     -l satan-budget-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'json)
(require 'satan-jsonl)
(require 'satan-broker)               ; satan-broker-run-dirs-for-date
(require 'satan-budget)

(defun satan-budget-test--write-transcript (dir lines)
  "Write LINES (each a plist) as transcript.jsonl under DIR."
  (make-directory dir t)
  (let ((coding-system-for-write 'utf-8))
    (with-temp-file (expand-file-name "transcript.jsonl" dir)
      (dolist (l lines)
        (insert (json-serialize
                 (satan-jsonl-prepare l)
                 :null-object :null :false-object :false))
        (insert "\n")))))

(defun satan-budget-test--usage-record (tokens-total)
  (list :ts "2026-05-19T09:00:00.000000+1000"
        :dir "in" :event "log"
        :payload (list :type "log" :kind "usage"
                       :tokens_in 0 :tokens_out 0
                       :tokens_total tokens-total)))

(ert-deftest satan-budget/run-tokens-takes-max-cumulative ()
  (let ((dir (make-temp-file "satan-bud-run-" t)))
    (unwind-protect
        (progn
          (satan-budget-test--write-transcript
           dir (list (satan-budget-test--usage-record 100)
                     (satan-budget-test--usage-record 350)
                     (satan-budget-test--usage-record 350)))
          (should (equal (satan-budget--run-tokens dir) 350)))
      (delete-directory dir t))))

(ert-deftest satan-budget/run-tokens-zero-when-no-usage ()
  (let ((dir (make-temp-file "satan-bud-run-" t)))
    (unwind-protect
        (progn
          (satan-budget-test--write-transcript
           dir (list (list :ts "x" :dir "in" :event "ready"
                           :payload (list :type "ready"))))
          (should (equal (satan-budget--run-tokens dir) 0)))
      (delete-directory dir t))))

(ert-deftest satan-budget/today-total-sums-today-prefix-only ()
  (let* ((root (make-temp-file "satan-bud-root-" t))
         (now (current-time))
         (today (format-time-string "%Y%m%dT" now))
         (yesterday (format-time-string
                     "%Y%m%dT"
                     (time-subtract now (days-to-time 1))))
         (today-a (expand-file-name (concat today "090000-x-aaaaaa") root))
         (today-b (expand-file-name (concat today "100000-x-bbbbbb") root))
         (older   (expand-file-name (concat yesterday "120000-x-cccccc") root)))
    (unwind-protect
        (progn
          (satan-budget-test--write-transcript
           today-a (list (satan-budget-test--usage-record 1000)))
          (satan-budget-test--write-transcript
           today-b (list (satan-budget-test--usage-record 2500)))
          (satan-budget-test--write-transcript
           older   (list (satan-budget-test--usage-record 999999)))
          (should (equal (satan-budget-today-total root now) 3500)))
      (delete-directory root t))))

(ert-deftest satan-budget/exceeded-p-respects-ceiling ()
  (let* ((root (make-temp-file "satan-bud-root-" t))
         (now (current-time))
         (today (format-time-string "%Y%m%dT" now))
         (dir (expand-file-name (concat today "090000-x-aaaaaa") root)))
    (unwind-protect
        (progn
          (satan-budget-test--write-transcript
           dir (list (satan-budget-test--usage-record 400000)))
          (let ((satan-budget-daily-tokens 400000))
            (should (satan-budget-exceeded-p root now)))
          (let ((satan-budget-daily-tokens 400001))
            (should-not (satan-budget-exceeded-p root now)))
          (let ((satan-budget-daily-tokens nil))
            (should-not (satan-budget-exceeded-p root now))))
      (delete-directory root t))))

(provide 'satan-budget-test)
;;; satan-budget-test.el ends here
