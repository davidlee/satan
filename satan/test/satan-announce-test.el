;;; satan-announce-test.el --- ert tests for satan-announce -*- lexical-binding: t; -*-

;; Unit tests for the announce seam (design.md sec-2, DEC-017).  This is the
;; one file allowed to stub `notifications-notify' / `call-process' directly
;; — delivery is the unit under test here.  Every other suite file goes
;; through `satan-announce-with-recorder' instead (design "Test hermeticity").

(require 'ert)
(require 'cl-lib)
(require 'satan-announce)
;; Loaded eagerly so the two tests below that `cl-letf' stub
;; `notifications-notify' are not clobbered by `satan-announce-deliver''s own
;; lazy `(require 'notifications)', which would otherwise reload the real
;; definition over the stub mid-test.
(require 'notifications)

;; These four exercise `satan-announce-deliver' directly, not `satan-announce'
;; — inside the full suite `satan-announce-sink' is bound to the recorder
;; (dev/satan-test.el), so going through the seam entry point would hit the
;; recorder instead of these local stubs.  Calling the sink function itself
;; is the "own unit tests" exception (design "Test hermeticity").

(ert-deftest satan-announce/deliver-pops-and-journals ()
  "TITLE and JOURNAL both given: one logger line, one D-Bus pop."
  (let (logged popped)
    (cl-letf (((symbol-function 'call-process)
               (lambda (cmd &rest args)
                 (when (equal cmd "logger") (setq logged args))
                 0))
              ((symbol-function 'notifications-notify)
               (lambda (&rest args) (setq popped args) 7)))
      (should (= 7 (satan-announce-deliver
                    (list :app satan-notify-app :title "t" :body "b"
                          :urgency 'normal :timeout nil :journal "j-line")))))
    (should logged)
    (should (member "j-line" logged))
    (should popped)
    (should (equal "t" (plist-get popped :title)))
    (should (equal "b" (plist-get popped :body)))))

(ert-deftest satan-announce/journal-only-when-no-title ()
  "No TITLE: the journal line fires; no D-Bus pop is attempted."
  (let (logged (pops 0))
    (cl-letf (((symbol-function 'call-process)
               (lambda (cmd &rest args)
                 (when (equal cmd "logger") (setq logged args))
                 0))
              ((symbol-function 'notifications-notify)
               (lambda (&rest _args) (cl-incf pops) 7)))
      (satan-announce-deliver (list :journal "j-only")))
    (should logged)
    (should (= 0 pops))))

(ert-deftest satan-announce/journal-failure-is-swallowed ()
  "A `logger' failure (e.g. missing binary) never propagates out."
  (cl-letf (((symbol-function 'call-process)
             (lambda (&rest _) (error "logger not found"))))
    (should-not (satan-announce-deliver (list :journal "whatever")))))

(ert-deftest satan-announce/pop-failure-propagates ()
  "A D-Bus pop failure signals out of the sink, unlike the journal."
  (cl-letf (((symbol-function 'notifications-notify)
             (lambda (&rest _) (error "no D-Bus today"))))
    (should-error (satan-announce-deliver
                   (list :app satan-notify-app :title "t" :body "b"
                         :urgency 'normal :timeout nil)))))

(ert-deftest satan-announce/with-recorder-captures-and-isolates ()
  "The recorder captures announcements, newest first, and resets per use."
  (satan-announce-with-recorder
    (satan-announce :journal "one")
    (satan-announce :title "two" :body "b")
    (should (= 2 (length satan-announce-recorded)))
    (should (equal "two" (plist-get (car satan-announce-recorded) :title)))
    (should (equal "one" (plist-get (car (last satan-announce-recorded))
                                    :journal))))
  ;; A fresh use starts empty again — nothing leaks between invocations.
  (satan-announce-with-recorder
    (should (null satan-announce-recorded))))

(ert-deftest satan-announce/batch-harness-binds-recorder ()
  "Self-check (VT-2): the batch harness binds the recording sink around
the whole suite (`dev/satan-test.el').  Meaningful only when this file
runs as part of `satan-test-run-batch' — standalone it sees the default
production sink instead."
  (should (eq satan-announce-sink #'satan-announce-record)))

(provide 'satan-announce-test)
;;; satan-announce-test.el ends here
