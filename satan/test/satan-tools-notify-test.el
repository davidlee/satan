;;; satan-tools-notify-test.el --- ert tests for satan-tools-notify -*- lexical-binding: t; -*-

;; Run from CLI:
;;   emacs --batch -L satan -L dev -L satan/test \
;;     -l satan-announce \
;;     --eval "(let ((satan-announce-sink #'satan-announce-record)) \
;;               (load \"satan-tools-notify-test\") \
;;               (ert-run-tests-batch-and-exit))"
;;
;; The record half of the intervention write API runs for real against a
;; tmp run's audit handle; only the two projection writes are stubbed
;; (`satan-tools-notify-test--with-projection'), so no test here reaches
;; Postgres (SL-017 design sec-5, R9).  The sensor-alert suite reuses
;; these fixtures.

(require 'ert)
(require 'cl-lib)
(require 'satan-announce)
(require 'satan-audit)
(require 'satan-jsonl)
(require 'satan-run)
(require 'satan-tools)
(require 'satan-tools-notify)
(require 'satan-intervention)

;; ---------------------------------------------------------------------
;; Fixtures (shared with satan-sensor-alerts-test.el)
;; ---------------------------------------------------------------------

(defmacro satan-tools-notify-test--with-run (spec &rest body)
  "SPEC is (VAR RUN-ID).  Bind VAR to a `satan-run' RUN-ID with a live
audit handle in a tmp dir; evaluate BODY; delete the dir.  Resets the
intervention id counters, so the first record is `<RUN-ID>.iv001'."
  (declare (indent 1))
  (let ((dir (make-symbol "dir")))
    `(let* ((,dir (make-temp-file "satan-tool-run-" t))
            (,(car spec) (make-satan-run
                          :id ,(cadr spec) :dir ,dir
                          :audit (satan-audit-open ,dir '(:manifest t) nil))))
       (satan-intervention--reset-counters)
       (unwind-protect (progn ,@body)
         (delete-directory ,dir t)))))

(defun satan-tools-notify-test--ctx (run caps time-now)
  "RUN's tool-ctx through the canonical builder, frozen at TIME-NOW.
The mode is the one named in RUN's id, with CAPS as `:capabilities'."
  (let ((r (copy-satan-run run)))
    (setf (satan-run-mode r) (list :name (satan-run-mode-from-id
                                          (satan-run-id run))
                                   :capabilities caps)
          (satan-run-prepare r) (list :time_now time-now))
    (satan-run-tool-ctx r)))

(defun satan-tools-notify-test--events (run event)
  "Payloads of RUN's transcript records named EVENT, in append order."
  (cl-loop for r in (satan-jsonl-read-file
                     (expand-file-name "transcript.jsonl" (satan-run-dir run))
                     :null-object :null)
           when (equal event (plist-get r :event))
           collect (plist-get r :payload)))

(defun satan-tools-notify-test--as-recorded (payload)
  "PAYLOAD as the transcript reads it back (a JSON round trip)."
  (json-parse-string
   (json-serialize (satan-jsonl-prepare payload)
                   :null-object :null :false-object :false)
   :object-type 'plist :array-type 'list :null-object :null))

(defmacro satan-tools-notify-test--with-projection (spec &rest body)
  "SPEC is ([CALLS [FAILING]]).  Evaluate BODY with only the two
projection writes stubbed.  CALLS, when given, is bound to the list of
`(FN . PAYLOAD)' calls, in call order.  Each FN in the list FAILING
signals `user-error', as `satan-intervention--exec-sql' does when
Postgres is down; its call is still captured."
  (declare (indent 1))
  (let ((calls (or (car spec) (make-symbol "calls")))
        (failing (make-symbol "failing"))
        (stub (make-symbol "stub")))
    `(let* ((,calls '())
            (,failing ,(cadr spec))
            (,stub (lambda (fn)
                     (lambda (payload &rest _)
                       (setq ,calls (append ,calls (list (cons fn payload))))
                       (when (memq fn ,failing)
                         (user-error "satan-intervention SQL: %s down" fn))))))
       (cl-letf (((symbol-function 'satan-intervention-project)
                  (funcall ,stub 'satan-intervention-project))
                 ((symbol-function 'satan-intervention-classify-project)
                  (funcall ,stub 'satan-intervention-classify-project)))
         ,@body))))

;; ---------------------------------------------------------------------
;; notify_send
;; ---------------------------------------------------------------------

(defconst satan-tools-notify-test--run-id "20260523T120000-morning-deadbe")

(defconst satan-tools-notify-test--now "2026-05-23T12:00:00+1000")

(defmacro satan-tools-notify-test--with-ctx (spec &rest body)
  "SPEC is (RUN CTX).  Bind RUN to a tmp morning run and CTX to its
tool-ctx with the `notify' capability; evaluate BODY."
  (declare (indent 1))
  `(satan-tools-notify-test--with-run (,(car spec) satan-tools-notify-test--run-id)
     (let ((,(cadr spec) (satan-tools-notify-test--ctx
                          ,(car spec) '(notify) satan-tools-notify-test--now)))
       ,@body)))

(defun satan-tools-notify-test--send (ctx args)
  "Dispatch `notify_send' with ARGS on CTX; return the tool_result plist."
  (satan-tool-dispatch
   (list :type "tool_call" :id "n1" :name "notify_send" :args args)
   '("notify_send")
   ctx))

(defun satan-tools-notify-test--fns (calls)
  "The function names in projection CALLS, in order."
  (mapcar #'car calls))

(ert-deftest satan-notify/dispatch-ok ()
  "notify.send dispatches via the registry, recording the announcement."
  (satan-tools-notify-test--with-ctx (run ctx)
    (satan-tools-notify-test--with-projection ()
      (satan-announce-with-recorder
        (let ((res (satan-tools-notify-test--send
                    ctx '(:title "hi" :body "there"))))
          (should (eq (plist-get res :ok) t))
          (should (equal 1 (plist-get (plist-get res :result) :id)))
          (should (= 1 (length satan-announce-recorded)))
          (should (equal "hi" (plist-get (car satan-announce-recorded) :title)))
          (should (equal "there"
                         (plist-get (car satan-announce-recorded) :body))))))))

(ert-deftest satan-notify/dispatch-surfaces-intervention-id ()
  "tool_result carries the recorded intervention_id, the same one projected."
  (satan-tools-notify-test--with-ctx (run ctx)
    (satan-tools-notify-test--with-projection (calls)
      (satan-announce-with-recorder
        (let ((res (satan-tools-notify-test--send
                    ctx '(:title "hi" :body "there")))
              (iv-id (concat satan-tools-notify-test--run-id ".iv001")))
          (should (equal iv-id (plist-get (plist-get res :result)
                                          :intervention_id)))
          (should (equal (list iv-id)
                         (mapcar (lambda (p) (plist-get p :intervention_id))
                                 (satan-tools-notify-test--events
                                  run "intervention.created"))))
          (should (equal '(satan-intervention-project)
                         (satan-tools-notify-test--fns calls)))
          (should (equal (satan-tools-notify-test--events
                          run "intervention.created")
                         (list (satan-tools-notify-test--as-recorded
                                (cdar calls))))))))))

(ert-deftest satan-notify/intervention-args-shape ()
  "The recorded `intervention.created' carries the §3.1 metadata."
  (satan-tools-notify-test--with-ctx (run ctx)
    (satan-tools-notify-test--with-projection ()
      (satan-announce-with-recorder
        (satan-tools-notify-test--send
         ctx '(:title "hi" :body "do the thing" :urgency "critical"))
        (let ((p (car (satan-tools-notify-test--events
                       run "intervention.created"))))
          (should (equal "notify" (plist-get p :kind)))
          (should (equal "dbus"   (plist-get p :target_surface)))
          (should (equal "high"   (plist-get p :severity)))
          (should (equal 30       (plist-get p :outcome_window_minutes)))
          (should (string-match-p "hi"     (plist-get p :message)))
          (should (string-match-p "do the" (plist-get p :message))))))))

(ert-deftest satan-notify/severity-defaults-medium ()
  "Default urgency maps to medium severity."
  (satan-tools-notify-test--with-ctx (run ctx)
    (satan-tools-notify-test--with-projection ()
      (satan-announce-with-recorder
        (satan-tools-notify-test--send ctx '(:title "t" :body "b"))
        (should (equal "medium"
                       (plist-get (car (satan-tools-notify-test--events
                                        run "intervention.created"))
                                  :severity)))))))

(ert-deftest satan-notify/schema-missing-title ()
  (satan-tools-notify-test--with-ctx (run ctx)
    (let ((res (satan-tools-notify-test--send ctx '(:body "x"))))
      (should (equal (plist-get res :ok) :false))
      (should (string-match-p "title" (plist-get res :error))))))

(ert-deftest satan-notify/schema-urgency-enum ()
  (satan-tools-notify-test--with-ctx (run ctx)
    (let ((res (satan-tools-notify-test--send
                ctx '(:title "t" :body "b" :urgency "screaming"))))
      (should (equal (plist-get res :ok) :false))
      (should (string-match-p "urgency" (plist-get res :error))))))

;; SL-017 DEC-018 — record before emit (I2, I3, I4)

(ert-deftest satan-tools-notify/no-emit-when-record-fails ()
  "I2 — a record that fails shows nothing and projects nothing."
  (satan-tools-notify-test--with-ctx (run ctx)
    (satan-tools-notify-test--with-projection (calls)
      (satan-announce-with-recorder
        (let* ((no-audit (let ((c (copy-sequence ctx))) (cl-remf c :audit) c))
               (res (satan-tools-notify-test--send
                     no-audit '(:title "t" :body "b"))))
          (should (equal :false (plist-get res :ok)))
          (should (string-match-p ":audit" (plist-get res :error)))
          (should-not satan-announce-recorded)
          (should-not calls)
          (should-not (satan-tools-notify-test--events
                       run "intervention.created")))))))

(ert-deftest satan-tools-notify/emits-and-notes-when-projection-fails ()
  "I3 — a failed projection is a note on an `ok' result, not a lost emit."
  (satan-tools-notify-test--with-ctx (run ctx)
    (satan-tools-notify-test--with-projection
        (calls '(satan-intervention-project))
      (satan-announce-with-recorder
        (let* ((res (satan-tools-notify-test--send ctx '(:title "t" :body "b")))
               (result (plist-get res :result)))
          (should (eq t (plist-get res :ok)))
          (should (= 1 (length satan-announce-recorded)))
          (should (equal 1 (plist-get result :id)))
          (should (equal (concat satan-tools-notify-test--run-id ".iv001")
                         (plist-get result :intervention_id)))
          (should (string-match-p "\\`failed: .*down"
                                  (plist-get result :projection)))
          (should (= 1 (length (satan-tools-notify-test--events
                                run "intervention.created"))))
          (should (equal '(satan-intervention-project)
                         (satan-tools-notify-test--fns calls))))))))

(ert-deftest satan-tools-notify/undelivered-pop-classified-unknown ()
  "I4 — a failed pop is `ok' with `:delivered :false', and the record
carries an undelivered `unknown' verdict, projected after its parent."
  (satan-tools-notify-test--with-ctx (run ctx)
    (satan-tools-notify-test--with-projection (calls)
      (let* ((satan-announce-sink (lambda (_) (error "no D-Bus today")))
             (res (satan-tools-notify-test--send ctx '(:title "t" :body "b")))
             (result (plist-get res :result))
             (iv-id (concat satan-tools-notify-test--run-id ".iv001"))
             (verdicts (satan-tools-notify-test--events
                        run "intervention.outcome_classified"))
             (v (car verdicts)))
        (should (eq t (plist-get res :ok)))
        (should (equal :null (plist-get result :id)))
        (should (equal iv-id (plist-get result :intervention_id)))
        (should (equal :false (plist-get result :delivered)))
        (should (equal "no D-Bus today" (plist-get result :error)))
        (should-not (plist-member result :projection))
        (should (= 1 (length (satan-tools-notify-test--events
                              run "intervention.created"))))
        (should (= 1 (length verdicts)))
        (should (equal iv-id (plist-get v :intervention_id)))
        (should (equal "unknown" (plist-get v :classification)))
        (should (equal "high"    (plist-get v :confidence)))
        (should (equal "mature"  (plist-get v :maturity)))
        (should (equal "auto"    (plist-get v :source)))
        (should (equal satan-tools-notify-test--now (plist-get v :classified_at)))
        (should (equal satan-tools-notify-test--now (plist-get v :next_revisit_at)))
        (should (equal "undelivered: no D-Bus today" (plist-get v :notes)))
        (should-not (plist-member v :revises))
        (should (equal '(satan-intervention-project
                         satan-intervention-classify-project)
                       (satan-tools-notify-test--fns calls)))
        (should (equal "unknown" (plist-get (cdr (cadr calls))
                                            :classification)))))))

(ert-deftest satan-tools-notify/undelivered-with-db-down-still-ok ()
  "I4 with Postgres down (RV-009 F-2): the verdict is still recorded, the
result is still `ok', and the verdict projection is not attempted
without its parent row."
  (satan-tools-notify-test--with-ctx (run ctx)
    (satan-tools-notify-test--with-projection
        (calls '(satan-intervention-project
                 satan-intervention-classify-project))
      (let* ((satan-announce-sink (lambda (_) (error "no D-Bus today")))
             (res (satan-tools-notify-test--send ctx '(:title "t" :body "b")))
             (result (plist-get res :result)))
        (should (eq t (plist-get res :ok)))
        (should (equal :false (plist-get result :delivered)))
        (should (string-match-p "\\`failed: " (plist-get result :projection)))
        (should-not (plist-member result :verdict))
        (should (= 1 (length (satan-tools-notify-test--events
                              run "intervention.created"))))
        (should (equal '("undelivered: no D-Bus today")
                       (mapcar (lambda (p) (plist-get p :notes))
                               (satan-tools-notify-test--events
                                run "intervention.outcome_classified"))))
        (should (equal '(satan-intervention-project)
                       (satan-tools-notify-test--fns calls)))))))

(provide 'satan-tools-notify-test)
;;; satan-tools-notify-test.el ends here
