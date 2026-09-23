;;; satan-tick-test.el --- ert tests for satan-tick -*- lexical-binding: t; -*-

;; Run from CLI:
;;   emacs --batch \
;;     -L ~/.emacs.d/core -L ~/.emacs.d/lisp -L ~/.emacs.d/org \
;;     -L ~/.emacs.d/satan -L ~/.emacs.d/satan/test \
;;     -l satan-tick-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'satan-tick)
(require 'satan-mode)
(require 'satan-output)
(require 'satan-tools-inbox)

(ert-deftest satan-tick/quiet-hours-wraparound ()
  "Default 22..7 window suppresses overnight, lets daytime pass."
  (let ((satan-tick-quiet-hours '(22 . 7)))
    (cl-letf (((symbol-function 'format-time-string)
               (lambda (fmt &optional _time &rest _) (if (equal fmt "%H") "23" "x"))))
      (should (satan-tick-quiet-p)))
    (cl-letf (((symbol-function 'format-time-string)
               (lambda (fmt &optional _time &rest _) (if (equal fmt "%H") "03" "x"))))
      (should (satan-tick-quiet-p)))
    (cl-letf (((symbol-function 'format-time-string)
               (lambda (fmt &optional _time &rest _) (if (equal fmt "%H") "09" "x"))))
      (should-not (satan-tick-quiet-p)))
    (cl-letf (((symbol-function 'format-time-string)
               (lambda (fmt &optional _time &rest _) (if (equal fmt "%H") "21" "x"))))
      (should-not (satan-tick-quiet-p)))))

(ert-deftest satan-tick/quiet-hours-disabled ()
  "nil quiet hours means never quiet."
  (let ((satan-tick-quiet-hours nil))
    (should-not (satan-tick-quiet-p))))

;; ── explicit WINDOW argument (design sec-7): one predicate, two windows ────

(defmacro satan-tick-test--at-hour (hour &rest body)
  "Stub `format-time-string' so its `%H' formatting reports HOUR; run BODY."
  (declare (indent 1))
  `(cl-letf (((symbol-function 'format-time-string)
              (lambda (fmt &optional _time &rest _)
                (if (equal fmt "%H") ,hour "x"))))
     ,@body))

(ert-deftest satan-tick/quiet-p-explicit-window-wraps-midnight ()
  "An explicit (22 . 9) window wraps midnight, same shape as the default."
  (let ((satan-tick-quiet-hours nil))
    (satan-tick-test--at-hour "23" (should (satan-tick-quiet-p nil '(22 . 9))))
    (satan-tick-test--at-hour "03" (should (satan-tick-quiet-p nil '(22 . 9))))
    (satan-tick-test--at-hour "09" (should-not (satan-tick-quiet-p nil '(22 . 9))))
    (satan-tick-test--at-hour "21" (should-not (satan-tick-quiet-p nil '(22 . 9))))))

(ert-deftest satan-tick/quiet-p-explicit-window-non-wrapping ()
  "An explicit non-wrapping window, e.g. (13 . 15)."
  (satan-tick-test--at-hour "14" (should (satan-tick-quiet-p nil '(13 . 15))))
  (satan-tick-test--at-hour "13" (should (satan-tick-quiet-p nil '(13 . 15))))
  (satan-tick-test--at-hour "15" (should-not (satan-tick-quiet-p nil '(13 . 15))))
  (satan-tick-test--at-hour "12" (should-not (satan-tick-quiet-p nil '(13 . 15)))))

(ert-deftest satan-tick/quiet-p-explicit-window-wins-over-global ()
  "An explicit window applies even when the global default is nil."
  (let ((satan-tick-quiet-hours nil))
    (satan-tick-test--at-hour "23" (should (satan-tick-quiet-p nil '(22 . 9))))))

(ert-deftest satan-tick/quiet-p-explicit-nil-window-never-quiet ()
  "An explicit nil WINDOW means never quiet, even when the global
`satan-tick-quiet-hours' covers TIME — an omitted WINDOW still falls
back to the global (design sec-7: the ask path passes
`satan-goad-quiet-hours' and a user-disabled (nil) goad window must
not inherit the tick window)."
  (let ((satan-tick-quiet-hours '(22 . 9)))
    (satan-tick-test--at-hour "23"
      (should-not (satan-tick-quiet-p nil nil))
      (should (satan-tick-quiet-p nil)))))

(ert-deftest satan-tick/pick-single-deterministic ()
  (should (equal (satan-tick-pick '(("tick-pulse" . 1))) "tick-pulse")))

(ert-deftest satan-tick/pick-zero-weight-nil ()
  (should (null (satan-tick-pick '(("x" . 0))))))

(ert-deftest satan-tick/pick-distribution-respects-weight ()
  "Over many draws, weights determine relative frequency."
  (let* ((pool '(("a" . 3) ("b" . 1)))
         (counts (make-hash-table :test 'equal))
         (n 4000))
    (random "tick-test-seed")
    (dotimes (_ n)
      (let ((p (satan-tick-pick pool)))
        (puthash p (1+ (gethash p counts 0)) counts)))
    (let ((a (gethash "a" counts 0))
          (b (gethash "b" counts 0)))
      (should (= (+ a b) n))
      ;; expect ~3:1; allow generous slack so the test is not flaky
      (should (> a (* b 2))))))

(ert-deftest satan-tick/default-pulse-mode-registered ()
  "tick-pulse is registered with the documented budget defaults."
  (let ((mode (satan-mode-resolve "tick-pulse")))
    (should (equal (plist-get mode :budget-tokens) 100000))
    (should (equal (plist-get mode :budget-tool-calls) 10))
    (should (equal (plist-get mode :timeout-seconds) 120))
    (should (eq (plist-get mode :output-handler) 'satan-output/tick))
    (should (member "notify_send" (plist-get mode :tools)))
    (should (member "inbox_append" (plist-get mode :tools)))
    (should-not (member "org_update_owned_block" (plist-get mode :tools)))))

(ert-deftest satan-tick/output-only-auto-applies-inbox ()
  "Tick output handler stages everything except `inbox_append'."
  (let ((final '(:summary ""
                 :actions ((:type "inbox_append"
                            :args (:title "x" :body "y"))
                           (:type "notify_send"
                            :args (:title "x" :body "y")))))
        (ctx (list :id "r1" :mode-name "tick-pulse"
                   :capabilities '(notify inbox-write)))
        (called nil))
    (cl-letf (((symbol-function 'satan-tool/inbox-append)
               (lambda (&rest _) (setq called t) (cons 'ok '(:path "/x")))))
      (let ((p (satan-output/tick final ctx)))
        (should called)
        (should (equal (length (plist-get p :applied)) 1))
        (should (equal (length (plist-get p :staged)) 1))
        (should (equal (plist-get (car (plist-get p :applied)) :type)
                       "inbox_append"))))))

(provide 'satan-tick-test)
;;; satan-tick-test.el ends here
