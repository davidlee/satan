;;; satan-tools-speak-test.el --- ert tests for satan-tools-speak -*- lexical-binding: t; -*-

;; `speak' shares notify's record → emit → project flow
;; (`satan-intervention-emit'), so it reuses notify's run and projection
;; fixtures; speech goes through the announce seam's recorder, so nothing
;; here plays audio or reaches Postgres.

(require 'ert)
(require 'cl-lib)
(require 'satan-announce)
(require 'satan-tools)
(require 'satan)                         ; tools + modes registered
(require 'satan-tools-notify-test)       ; run + projection fixtures

(defconst satan-tools-speak-test--run-id "20261017T120000-tick-agent-deadbe")

(defconst satan-tools-speak-test--now "2026-10-17T12:00:00+1100")

(defmacro satan-tools-speak-test--with-ctx (spec &rest body)
  "SPEC is (RUN CTX).  Bind RUN to a tmp tick-agent run and CTX to its
tool-ctx with the `speak' capability; evaluate BODY with the projection
stubbed and the announce recorder bound."
  (declare (indent 1))
  `(satan-tools-notify-test--with-run (,(car spec) satan-tools-speak-test--run-id)
     (let ((,(cadr spec) (satan-tools-notify-test--ctx
                          ,(car spec) '(speak) satan-tools-speak-test--now))
           (satan-speak-program "say"))
       (satan-tools-notify-test--with-projection ()
         (satan-announce-with-recorder
           ,@body)))))

(defun satan-tools-speak-test--speak (ctx text)
  "Dispatch `speak' with TEXT on CTX; return the tool_result plist."
  (satan-tool-dispatch
   (list :type "tool_call" :id "s1" :name "speak" :args (list :text text))
   '("speak")
   ctx))

(defun satan-tools-speak-test--created (run)
  "RUN's recorded `intervention.created' payloads."
  (satan-tools-notify-test--events run "intervention.created"))

(defun satan-tools-speak-test--refused (run res)
  "Assert dispatch result RES refused, recording and speaking nothing
on RUN; return RES."
  (should (equal :false (plist-get res :ok)))
  (should-not satan-announce-recorded)
  (should-not (satan-tools-speak-test--created run))
  res)

(ert-deftest satan-speak/speaks-recorded-intervention ()
  "Speech is announced and recorded as an `audio' intervention."
  (satan-tools-speak-test--with-ctx (run ctx)
    (let ((res (satan-tools-speak-test--speak ctx "Time to stand up.")))
      (should (eq t (plist-get res :ok)))
      (should (equal (concat satan-tools-speak-test--run-id ".iv001")
                     (plist-get (plist-get res :result) :intervention_id)))
      (should (equal '("Time to stand up.")
                     (mapcar (lambda (a) (plist-get a :speech))
                             satan-announce-recorded)))
      (should-not (plist-get (car satan-announce-recorded) :title))
      (let ((p (car (satan-tools-speak-test--created run))))
        (should (equal "notify" (plist-get p :kind)))
        (should (equal "audio" (plist-get p :target_surface)))
        (should (equal "Time to stand up." (plist-get p :message)))))))

(ert-deftest satan-speak/refuses-without-capability ()
  (satan-tools-speak-test--with-ctx (run ctx)
    (satan-tools-speak-test--refused
     run (satan-tools-speak-test--speak
          (plist-put (copy-sequence ctx) :capabilities nil) "hi"))))

(ert-deftest satan-speak/refuses-blank-text ()
  (satan-tools-speak-test--with-ctx (run ctx)
    (satan-tools-speak-test--refused
     run (satan-tools-speak-test--speak ctx " \n "))))

(ert-deftest satan-speak/refuses-text-over-cap ()
  "Over-long text is refused, not truncated: the model says it shorter."
  (satan-tools-speak-test--with-ctx (run ctx)
    (let ((res (satan-tools-speak-test--refused
                run (satan-tools-speak-test--speak
                     ctx (make-string (1+ satan-speak-max-chars) ?a)))))
      (should (string-match-p "too long" (plist-get res :error))))))

(ert-deftest satan-speak/refuses-when-disabled ()
  "A nil `satan-speak-program' is the kill switch."
  (satan-tools-speak-test--with-ctx (run ctx)
    (let ((satan-speak-program nil))
      (satan-tools-speak-test--refused
       run (satan-tools-speak-test--speak ctx "hi")))))

(ert-deftest satan-speak/unstartable-is-undelivered ()
  "Speech that cannot start is recorded and marked undelivered."
  (satan-tools-speak-test--with-ctx (run ctx)
    (let* ((satan-announce-sink (lambda (_) (error "no say here")))
           (result (plist-get (satan-tools-speak-test--speak ctx "hi")
                              :result)))
      (should (equal :false (plist-get result :delivered)))
      (should (equal "no say here" (plist-get result :error))))))

(ert-deftest satan-speak/enabled-where-notify-is ()
  "Every mode that can notify can also speak (IMP-040)."
  (dolist (name '("morning" "motd" "tick-pulse" "tick-agent"))
    (let ((mode (satan-mode-resolve name)))
      (should (member "speak" (plist-get mode :tools)))
      (should (memq 'speak (plist-get mode :capabilities))))))

(provide 'satan-tools-speak-test)
;;; satan-tools-speak-test.el ends here
