;;; dl-satan-budget-test.el --- ert tests for dl-satan-budget -*- lexical-binding: t; -*-

;; Run from CLI:
;;   emacs --batch \
;;     -L ~/.emacs.d/core -L ~/.emacs.d/satan -L ~/.emacs.d/satan/test \
;;     -l dl-satan-budget-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'json)
(require 'dl-satan-jsonl)
(require 'dl-satan-broker)               ; dl-satan-broker-run-dirs-for-date
(require 'dl-satan-budget)

(defun dl-satan-budget-test--write-transcript (dir lines)
  "Write LINES (each a plist) as transcript.jsonl under DIR."
  (make-directory dir t)
  (let ((coding-system-for-write 'utf-8))
    (with-temp-file (expand-file-name "transcript.jsonl" dir)
      (dolist (l lines)
        (insert (json-serialize
                 (dl-satan-jsonl-prepare l)
                 :null-object :null :false-object :false))
        (insert "\n")))))

(defun dl-satan-budget-test--usage-record (tokens-total)
  (list :ts "2026-05-19T09:00:00.000000+1000"
        :dir "in" :event "log"
        :payload (list :type "log" :kind "usage"
                       :tokens_in 0 :tokens_out 0
                       :tokens_total tokens-total)))

(ert-deftest dl-satan-budget/run-tokens-takes-max-cumulative ()
  (let ((dir (make-temp-file "satan-bud-run-" t)))
    (unwind-protect
        (progn
          (dl-satan-budget-test--write-transcript
           dir (list (dl-satan-budget-test--usage-record 100)
                     (dl-satan-budget-test--usage-record 350)
                     (dl-satan-budget-test--usage-record 350)))
          (should (equal (dl-satan-budget--run-tokens dir) 350)))
      (delete-directory dir t))))

(ert-deftest dl-satan-budget/run-tokens-zero-when-no-usage ()
  (let ((dir (make-temp-file "satan-bud-run-" t)))
    (unwind-protect
        (progn
          (dl-satan-budget-test--write-transcript
           dir (list (list :ts "x" :dir "in" :event "ready"
                           :payload (list :type "ready"))))
          (should (equal (dl-satan-budget--run-tokens dir) 0)))
      (delete-directory dir t))))

(ert-deftest dl-satan-budget/today-total-sums-today-prefix-only ()
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
          (dl-satan-budget-test--write-transcript
           today-a (list (dl-satan-budget-test--usage-record 1000)))
          (dl-satan-budget-test--write-transcript
           today-b (list (dl-satan-budget-test--usage-record 2500)))
          (dl-satan-budget-test--write-transcript
           older   (list (dl-satan-budget-test--usage-record 999999)))
          (should (equal (dl-satan-budget-today-total root now) 3500)))
      (delete-directory root t))))

(ert-deftest dl-satan-budget/exceeded-p-respects-ceiling ()
  (let* ((root (make-temp-file "satan-bud-root-" t))
         (now (current-time))
         (today (format-time-string "%Y%m%dT" now))
         (dir (expand-file-name (concat today "090000-x-aaaaaa") root)))
    (unwind-protect
        (progn
          (dl-satan-budget-test--write-transcript
           dir (list (dl-satan-budget-test--usage-record 400000)))
          (let ((dl-satan-budget-daily-tokens 400000))
            (should (dl-satan-budget-exceeded-p root now)))
          (let ((dl-satan-budget-daily-tokens 400001))
            (should-not (dl-satan-budget-exceeded-p root now)))
          (let ((dl-satan-budget-daily-tokens nil))
            (should-not (dl-satan-budget-exceeded-p root now))))
      (delete-directory root t))))

(provide 'dl-satan-budget-test)
;;; dl-satan-budget-test.el ends here
