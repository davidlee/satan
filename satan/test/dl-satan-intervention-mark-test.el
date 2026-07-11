;;; dl-satan-intervention-mark-test.el --- ert for manual-mark commands -*- lexical-binding: t; -*-

;; T1.5b PR 4 — interactive manual override path.
;;
;; Run from CLI:
;;   emacs --batch \
;;     -L ~/.emacs.d/core -L ~/.emacs.d/satan -L ~/.emacs.d/satan/test \
;;     -l dl-satan-intervention-mark-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'dl-satan-audit)
(require 'dl-satan-intervention)
(require 'dl-satan-intervention-mark)
(require 'dl-satan-intervention-test nil 'noerror)

;; ---------- pure unit tests (no DB) ----------

(ert-deftest dl-satan-intervention-mark/run-id-of-extracts-prefix ()
  (should (equal "20260523T120000-morning-aaaaaa"
                 (dl-satan-intervention-mark--run-id-of
                  "20260523T120000-morning-aaaaaa.iv03"))))

(ert-deftest dl-satan-intervention-mark/run-id-of-rejects-malformed ()
  (should-error
   (dl-satan-intervention-mark--run-id-of "no-suffix-here")
   :type 'user-error))

(ert-deftest dl-satan-intervention-mark/next-revisit-at-derives-window-close ()
  (let* ((iv (list :ts "2026-05-23T12:00:00+1000"
                   :outcome_window_minutes 30))
         (got (dl-satan-intervention-mark--next-revisit-at iv)))
    (should (equal "2026-05-23T12:30:00+1000" got))))

;; ---------- recent (DB) ----------

(ert-deftest dl-satan-intervention-mark/recent-orders-newest-first ()
  (skip-unless (fboundp 'dl-satan-intervention-test--with-db))
  (dl-satan-intervention-test--with-db
   (dl-satan-intervention--reset-counters)
   (let* ((root (make-temp-file "satan-iv-recent-" t))
          (old-run "20260522T120000-morning-aaaaaa")
          (new-run "20260523T120000-morning-bbbbbb")
          (audit-old (dl-satan-intervention-test--open-audit root old-run))
          (audit-new (dl-satan-intervention-test--open-audit root new-run))
          (ctx-old (dl-satan-intervention-test--build-ctx
                    audit-old old-run "2026-05-22T12:00:00+1000"))
          (ctx-new (dl-satan-intervention-test--build-ctx
                    audit-new new-run "2026-05-23T12:00:00+1000")))
     (unwind-protect
         (let ((iv-old (dl-satan-intervention-create
                        :ctx ctx-old :kind "notify"
                        :target-surface "dbus" :message "old"
                        :expected-outcome "x" :outcome-window-minutes 30
                        :severity "low"))
               (iv-new (dl-satan-intervention-create
                        :ctx ctx-new :kind "notify"
                        :target-surface "dbus" :message "new"
                        :expected-outcome "x" :outcome-window-minutes 30
                        :severity "low")))
           ;; Within 24h of new-run ts → both visible
           (let ((rows (dl-satan-intervention-recent
                        "2026-05-23T12:05:00+1000" :limit 10)))
             (should (= 2 (length rows)))
             (should (equal iv-new (plist-get (nth 0 rows) :intervention_id)))
             (should (equal iv-old (plist-get (nth 1 rows) :intervention_id))))
           ;; Far future → both stale; default excludes; include-stale recovers
           (let ((default (dl-satan-intervention-recent
                           "2026-06-01T00:00:00+1000" :limit 10))
                 (with-stale (dl-satan-intervention-recent
                              "2026-06-01T00:00:00+1000"
                              :include-stale t :limit 10)))
             (should (= 0 (length default)))
             (should (= 2 (length with-stale)))))
       (delete-directory root t)))))

;; ---------- dispatch end-to-end (DB + stubs) ----------

(ert-deftest dl-satan-intervention-mark/dispatch-routes-to-writer ()
  (skip-unless (fboundp 'dl-satan-intervention-test--with-db))
  (dl-satan-intervention-test--with-db
   (dl-satan-intervention--reset-counters)
   (let* ((root (make-temp-file "satan-iv-dispatch-" t))
          (run-id "20260523T120000-morning-aaaaaa")
          (audit (dl-satan-intervention-test--open-audit root run-id))
          (ctx (dl-satan-intervention-test--build-ctx audit run-id))
          (mark-calls nil))
     (unwind-protect
         (let ((iv-id (dl-satan-intervention-create
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
                ((symbol-function 'dl-satan-intervention-mark--now-iso)
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
                ((symbol-function 'dl-satan-broker-locate-run-dir)
                 (lambda (rid &optional _runs-dir)
                   (dl-satan-audit-handle-dir audit)))
                ((symbol-function 'dl-satan-memory-store-mark)
                 (lambda (&rest kvs)
                   (push kvs mark-calls)
                   (cons 'ok "trace_stub"))))
             (let ((event (my/satan-mark-intervention-harmful nil)))
               (should (equal "intervention.outcome_classified" event))))
           ;; Projection updated.
           (let* ((row (dl-satan-intervention-lookup iv-id))
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

(provide 'dl-satan-intervention-mark-test)
;;; dl-satan-intervention-mark-test.el ends here
