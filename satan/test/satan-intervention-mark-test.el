;;; satan-intervention-mark-test.el --- ert for manual-mark commands -*- lexical-binding: t; -*-

;; T1.5b PR 4 — interactive manual override path.
;;
;; Run from CLI, at the repo root:
;;   emacs --batch \
;;     -L satan -L dev -L satan/test \
;;     -l satan-intervention-mark-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'satan-audit)
(require 'satan-intervention)
(require 'satan-intervention-mark)
(require 'satan-intervention-test nil 'noerror)

;; ---------- pure unit tests (no DB) ----------

(ert-deftest satan-intervention-mark/run-id-of-extracts-prefix ()
  (should (equal "20260523T120000-morning-aaaaaa"
                 (satan-intervention-mark--run-id-of
                  "20260523T120000-morning-aaaaaa.iv03"))))

(ert-deftest satan-intervention-mark/run-id-of-rejects-malformed ()
  (should-error
   (satan-intervention-mark--run-id-of "no-suffix-here")
   :type 'user-error))

(ert-deftest satan-intervention-mark/next-revisit-at-derives-window-close ()
  (let* ((iv (list :ts "2026-05-23T12:00:00+1000"
                   :outcome_window_minutes 30))
         (got (satan-intervention-mark--next-revisit-at iv)))
    (should (equal "2026-05-23T12:30:00+1000" got))))

;; ---------- recent (DB) ----------

(ert-deftest satan-intervention-mark/recent-orders-newest-first ()
  (skip-unless (fboundp 'satan-intervention-test--with-db))
  (satan-intervention-test--with-db
   (satan-intervention--reset-counters)
   (let* ((root (make-temp-file "satan-iv-recent-" t))
          (old-run "20260522T120000-morning-aaaaaa")
          (new-run "20260523T120000-morning-bbbbbb")
          (audit-old (satan-intervention-test--open-audit root old-run))
          (audit-new (satan-intervention-test--open-audit root new-run))
          (ctx-old (satan-intervention-test--build-ctx
                    audit-old old-run "2026-05-22T12:00:00+1000"))
          (ctx-new (satan-intervention-test--build-ctx
                    audit-new new-run "2026-05-23T12:00:00+1000")))
     (unwind-protect
         (let ((iv-old (satan-intervention-create
                        :ctx ctx-old :kind "notify"
                        :target-surface "dbus" :message "old"
                        :expected-outcome "x" :outcome-window-minutes 30
                        :severity "low"))
               (iv-new (satan-intervention-create
                        :ctx ctx-new :kind "notify"
                        :target-surface "dbus" :message "new"
                        :expected-outcome "x" :outcome-window-minutes 30
                        :severity "low")))
           ;; Within 24h of new-run ts → both visible
           (let ((rows (satan-intervention-recent
                        "2026-05-23T12:05:00+1000" :limit 10)))
             (should (= 2 (length rows)))
             (should (equal iv-new (plist-get (nth 0 rows) :intervention_id)))
             (should (equal iv-old (plist-get (nth 1 rows) :intervention_id))))
           ;; Far future → both stale; default excludes; include-stale recovers
           (let ((default (satan-intervention-recent
                           "2026-06-01T00:00:00+1000" :limit 10))
                 (with-stale (satan-intervention-recent
                              "2026-06-01T00:00:00+1000"
                              :include-stale t :limit 10)))
             (should (= 0 (length default)))
             (should (= 2 (length with-stale)))))
       (delete-directory root t)))))

;; ---------- dispatch end-to-end (DB + stubs) ----------

;; PRESERVED-BOUNDARY PIN — SL-002 §2.D / §9 (RN-2c).  The `bough_node:abc'
;; handle below is NOT integration residue: it pins that the manual mark path
;; copies a stored intervention's cue handles verbatim into the counter-memory
;; trace.  Copy-forward is content-agnostic and survives the removal; scrubbing
;; the residue is IMP-016.
(ert-deftest satan-intervention-mark/dispatch-routes-to-writer ()
  (skip-unless (fboundp 'satan-intervention-test--with-db))
  (satan-intervention-test--with-db
   (satan-intervention--reset-counters)
   (let* ((root (make-temp-file "satan-iv-dispatch-" t))
          (run-id "20260523T120000-morning-aaaaaa")
          (audit (satan-intervention-test--open-audit root run-id))
          (ctx (satan-intervention-test--build-ctx audit run-id))
          (mark-calls nil))
     (unwind-protect
         (let ((iv-id (satan-intervention-create
                       :ctx ctx :kind "notify"
                       :target-surface "dbus" :message "m"
                       :expected-outcome "x" :outcome-window-minutes 30
                       :severity "low"
                       :cue-handles '("bough_node:abc"))))
           (cl-letf*
               ( ;; Pin the read-path clock so the iv (ts 2026-05-23T12:00,
                ;; 30-min window) is mature but not stale at mark time:
                ;; ts+30m < now < ts+30m+24h.  Without this, wall-clock "now"
                ;; reads it stale (excluded) or — too soon — pending (marking
                ;; a pending iv violates outcome-semantics invariant 3).
                ((symbol-function 'satan-intervention-mark--now-iso)
                 (lambda () "2026-05-23T13:00:00+1000"))
                ((symbol-function 'completing-read)
                 (lambda (prompt collection &optional _p _r _i _h def)
                   (cond
                    ((string-prefix-p "Intervention" prompt)
                     ;; Pick the first candidate; collection is labels.
                     (car collection))
                    ((string-prefix-p "Confidence" prompt) "high")
                    (t (or def "")))))
                ((symbol-function 'read-string)
                 (lambda (prompt &optional _i _h def &rest _)
                   (cond
                    ((string-prefix-p "Reason" prompt) "interrupted focus")
                    ((string-prefix-p "Evidence pointer" prompt)
                     (or def "/notes/x.org:1"))
                    ((string-prefix-p "Notes" prompt) "deep work")
                    (t ""))))
                ((symbol-function 'satan-run-locate-dir)
                 (lambda (rid &optional _runs-dir)
                   (satan-audit-handle-dir audit)))
                ((symbol-function 'satan-memory-store-mark)
                 (lambda (&rest kvs)
                   (push kvs mark-calls)
                   (cons 'ok "trace_stub"))))
             (let ((event (satan-mark-intervention-harmful nil)))
               (should (equal "intervention.outcome_classified" event))))
           ;; Projection updated.
           (let* ((row (satan-intervention-lookup iv-id))
                  (outcome (plist-get row :outcome)))
             (should (equal "harmful" (plist-get outcome :classification)))
             (should (equal "high" (plist-get outcome :confidence)))
             (should (equal "manual" (plist-get outcome :source)))
             (should (equal "interactive-command"
                            (plist-get outcome :marked_by)))
             (should (equal "deep work" (plist-get outcome :notes))))
           ;; Counter-memory trace written via stub.
           (should (= 1 (length mark-calls)))
           (let* ((kvs (car mark-calls))
                  (handles (plist-get kvs :handles)))
             (should (equal '("bough_node:abc")
                            (mapcar (lambda (h) (plist-get h :handle))
                                    handles)))
             (should (equal "negative" (plist-get kvs :valence)))))
       (delete-directory root t)))))

;; ---------- attribution: manual marks carry no run (SL-032 / DEC-123) ----------

;; The M-x path marks an intervention from outside any run: it must say so
;; explicitly (nil run-id) rather than inherit whatever run happens to
;; enclose the command, so no trace_marked signal is ever attributed to a
;; live broker run.  Only the DB-touching collaborators are stubbed.

(defmacro satan-intervention-mark-test--stub-projection (&rest body)
  "Run BODY with the projection readers/writers the manual path consults
stubbed, so no DB is reached."
  (declare (indent 0))
  `(cl-letf (((symbol-function 'satan-intervention-recent)
              (lambda (&rest _)
                (list (list :intervention_id
                            "20260523T120000-morning-aaaaaa.iv01"
                            :kind "notify"
                            :ts "2026-05-23T12:00:00+1000"
                            :message "m"))))
            ((symbol-function 'satan-intervention-lookup)
             (lambda (iv-id &optional _db)
               (list :intervention
                     (list :intervention_id iv-id
                           :kind "notify"
                           :ts "2026-05-23T12:00:00+1000"
                           :outcome_window_minutes 30
                           :cue_handles '("project:emacs.d")))))
            ((symbol-function 'satan-intervention-classify)
             (lambda (&rest _) "intervention.outcome_classified")))
     ,@body))

(defmacro satan-intervention-mark-test--stub-interactive-input (&rest body)
  "Run BODY with the interactive prompt surface of the M-x mark stubbed."
  (declare (indent 0))
  `(cl-letf (((symbol-function 'satan-intervention-mark--now-iso)
              (lambda () "2026-05-23T13:00:00+1000"))
            ((symbol-function 'completing-read)
             (lambda (prompt collection &optional _p _r _i _h def)
               (cond
                ((string-prefix-p "Intervention" prompt)
                 (car collection))
                ((string-prefix-p "Confidence" prompt) "high")
                (t (or def "")))))
            ((symbol-function 'read-string)
             (lambda (prompt &optional _i _h def &rest _)
               (cond
                ((string-prefix-p "Reason" prompt) "interrupted focus")
                ((string-prefix-p "Evidence pointer" prompt)
                 (or def "/notes/x.org:1"))
                ((string-prefix-p "Notes" prompt) "deep work")
                (t "")))))
     ,@body))

(ert-deftest satan-intervention-mark/mx-mark-passes-nil-run-id ()
  "DEC-123 — the M-x mark hands the counter-memory writer a nil `:run-id'
(an explicit absence), never the intervention's historical run nor an
ambient broker run."
  (let ((root (make-temp-file "satan-iv-mx-run-id-" t))
        (mark-calls nil))
    (unwind-protect
        (cl-letf* (((symbol-function 'satan-run-locate-dir)
                    (lambda (_rid &optional _runs-dir) root))
                   ((symbol-function 'satan-audit-reopen)
                    (lambda (_dir) (list :stub-audit t)))
                   ((symbol-function 'satan-memory-store-mark)
                    (lambda (&rest kvs)
                      (push kvs mark-calls)
                      (cons 'ok "trace_stub"))))
          (satan-intervention-mark-test--stub-projection
           (satan-intervention-mark-test--stub-interactive-input
            (should (equal "intervention.outcome_classified"
                           (satan-mark-intervention-harmful nil)))
            (should (= 1 (length mark-calls)))
            (let ((kvs (car mark-calls)))
              (should (plist-member kvs :run-id))
              (should (null (plist-get kvs :run-id)))))))
      (delete-directory root t))))

(ert-deftest satan-intervention-mark/manual-nil-run-id-emits-no-trace_marked ()
  "V7/DEC-123 — the M-x shape (no run behind the mark) drives the real
store and emitter, yet no trace_marked is enqueued: a manual mark
attributes to nothing."
  (let* ((satan-attribute-updates-enabled t)
         (real-db-query (symbol-function 'satan-db-query))
         (enqueued nil))
    (cl-letf* (((symbol-function 'satan-db-query)
                (lambda (db host program sql &optional variables)
                  (if (equal db satan-memory-store-database)
                      (cons 'ok "tid-x")
                    (funcall real-db-query db host program sql variables))))
               ((symbol-function 'satan-attribute-enqueue)
                (lambda (payload &optional _db)
                  (push payload enqueued)
                  (cons 'ok 1))))
      (satan-intervention-mark-test--stub-projection
       (satan-intervention-write-manual-outcome
        :ctx (list :id "20260523T120000-morning-aaaaaa"
                   :mode-name "manual-mark"
                   :time-now "2026-05-23T13:00:00+1000"
                   :capabilities '())
        :intervention-id "20260523T120000-morning-aaaaaa.iv01"
        :classification "harmful"
        :confidence "high"
        :reason "interrupted focus"
        :evidence-pointer nil
        :marked-by "interactive-command"
        :maturity "mature"
        :next-revisit-at "2026-05-23T12:30:00+1000"
        :classified-at "2026-05-23T13:00:00+1000"
        :run-id nil)
       (should (null enqueued))))))

(provide 'satan-intervention-mark-test)
;;; satan-intervention-mark-test.el ends here
