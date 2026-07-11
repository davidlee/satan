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
    (should (equal (plist-get mode :timeout-seconds) 60))
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
