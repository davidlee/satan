;;; satan-tools-atsatan-test.el --- @satan scan/done tool tests -*- lexical-binding: t; -*-

;; Run from CLI:
;;   emacs --batch \
;;     -L ~/.emacs.d/core -L ~/.emacs.d/satan -L ~/.emacs.d/satan/test \
;;     -l ert -l satan-tools-atsatan-test \
;;     --eval '(ert-run-tests-batch-and-exit "notes-at-satan-")'

(require 'ert)
(require 'cl-lib)
(require 'satan-tools-atsatan)
;; Optional fixtures for the live-broker smoke test; tests that need
;; them gate on `satan-intervention-test--with-db' being bound.
(require 'satan-audit)
(require 'satan-intervention)
(require 'satan-intervention-test nil 'noerror)

(defmacro satan-tools-atsatan-test--with-root (root-sym &rest body)
  "Bind ROOT-SYM to a fresh temp dir, let-bind it as the scan root, cleanup on exit."
  (declare (indent 1))
  `(let* ((,root-sym (make-temp-file "satan-atsatan-test-" 'dir))
          (satan-tools-atsatan-root ,root-sym))
     (unwind-protect (progn ,@body)
       (delete-directory ,root-sym 'recursive))))

(ert-deftest notes-at-satan/scan-then-done-then-rescan ()
  "Full round-trip: scan finds a match, done claims it, rescan excludes it."
  (satan-tools-atsatan-test--with-root root
    (let* ((file (expand-file-name "trip.org" root))
           (ctx  (list :id "TEST-RUN" :capabilities '(write-notes))))
      ;; Seed file.
      (let ((coding-system-for-write 'utf-8))
        (write-region "* H\nfirst line\n- @satan summarise me\nlast line\n"
                      nil file))
      ;; Scan: one match.
      (let* ((res (satan-tool/notes-at-satan-scan nil ctx)))
        (should (eq (car res) 'ok))
        (let* ((payload (cdr res))
               (matches (plist-get payload :matches))
               (m       (car matches))
               (id      (plist-get m :id)))
          (should (= 1 (length matches)))
          (should (string-match-p "summarise me" (plist-get m :content)))
          (should (equal "* H" (plist-get m :headline)))
          ;; Done: claim it.
          (let ((done (satan-tool/notes-at-satan-done
                       (list :match-id id
                             :comment "inbox_append: summarised 4 steps")
                       ctx)))
            (should (eq (car done) 'ok))
            (should (equal "done" (plist-get (cdr done) :status))))
          ;; File now bears @satan-was-here plus an org quote block
          ;; carrying the run-id, tag, and body summary.
          (with-temp-buffer
            (insert-file-contents file)
            (let ((s (buffer-string)))
              (should (string-match-p "@satan-was-here summarise me" s))
              (should (string-match-p
                       "#\\+BEGIN_QUOTE satan TEST-RUN,inbox_append" s))
              (should (string-match-p "^summarised 4 steps$" s))
              (should (string-match-p "#\\+END_QUOTE" s))))
          ;; Idempotent: second done is a no-op.
          (let ((done2 (satan-tool/notes-at-satan-done
                        (list :match-id id) ctx)))
            (should (equal "already-done"
                           (plist-get (cdr done2) :status))))
          ;; Rescan: no matches.
          (let ((rescan (satan-tool/notes-at-satan-scan nil ctx)))
            (should (eq (car rescan) 'ok))
            (should (zerop (plist-get (cdr rescan) :count)))))))))

(ert-deftest notes-at-satan-scan/excludes-satan-dir ()
  "Files under <root>/satan/ are excluded by the !satan/** glob."
  (satan-tools-atsatan-test--with-root root
    (let* ((subdir (expand-file-name "satan" root))
           (file   (expand-file-name "x.org" subdir))
           (ctx    (list :id "TEST-RUN" :capabilities '(write-notes))))
      (make-directory subdir t)
      (let ((coding-system-for-write 'utf-8))
        (write-region "@satan x\n" nil file))
      (let ((res (satan-tool/notes-at-satan-scan nil ctx)))
        (should (eq (car res) 'ok))
        (should (zerop (plist-get (cdr res) :count)))))))

(ert-deftest notes-at-satan-scan/excludes-legacy-done-token ()
  "Lines bearing the legacy `@satan-done' claim marker are filtered.
Pre-rename ticks wrote `@satan-done(...)' instead of the current
`@satan-was-here'; historical notes still carry that token."
  (satan-tools-atsatan-test--with-root root
    (let* ((file (expand-file-name "legacy.org" root))
           (ctx  (list :id "TEST-RUN" :capabilities '(write-notes))))
      (let ((coding-system-for-write 'utf-8))
        (write-region "@satan-done(20260520T125209-tick-agent-259270, inbox_append: ok) follow-up?\n"
                      nil file))
      (let ((res (satan-tool/notes-at-satan-scan nil ctx)))
        (should (eq (car res) 'ok))
        (should (zerop (plist-get (cdr res) :count)))))))

(ert-deftest notes-at-satan-scan/markdown-headline ()
  "Markdown `## H' headings are returned in :headline."
  (satan-tools-atsatan-test--with-root root
    (let* ((file (expand-file-name "foo.md" root))
           (ctx  (list :id "TEST-RUN" :capabilities '(write-notes))))
      (let ((coding-system-for-write 'utf-8))
        (write-region "## Onboarding\n@satan x\n" nil file))
      (let* ((res (satan-tool/notes-at-satan-scan nil ctx))
             (m   (car (plist-get (cdr res) :matches))))
        (should (eq (car res) 'ok))
        (should (equal "## Onboarding" (plist-get m :headline)))))))

(ert-deftest notes-at-satan-scan/context-window ()
  "Context window of ±2 around the match line spans lines 3-7 of a 10-line file."
  (satan-tools-atsatan-test--with-root root
    (let* ((file (expand-file-name "ctx.org" root))
           (ctx  (list :id "TEST-RUN" :capabilities '(write-notes)))
           (body (concat "l1\nl2\nl3\nl4\n@satan here\nl6\nl7\nl8\nl9\nl10\n")))
      (let ((coding-system-for-write 'utf-8))
        (write-region body nil file))
      (let* ((res (satan-tool/notes-at-satan-scan
                   (list :context-lines 2) ctx))
             (m   (car (plist-get (cdr res) :matches)))
             (window (plist-get m :context)))
        (should (eq (car res) 'ok))
        (should (equal "l3\nl4\n@satan here\nl6\nl7" window))))))

(ert-deftest notes-at-satan-done/markdown-blockquote ()
  "Markdown files render the claim as a `> '-prefixed blockquote."
  (satan-tools-atsatan-test--with-root root
    (let* ((file (expand-file-name "md-trip.md" root))
           (ctx  (list :id "RUN-MD" :capabilities '(write-notes))))
      (let ((coding-system-for-write 'utf-8))
        (write-region "## H\n@satan act on this\n" nil file))
      (let* ((res (satan-tool/notes-at-satan-scan nil ctx))
             (id  (plist-get (car (plist-get (cdr res) :matches)) :id)))
        (satan-tool/notes-at-satan-done
         (list :match-id id :comment "memory_mark: noted gap") ctx)
        (with-temp-buffer
          (insert-file-contents file)
          (let ((s (buffer-string)))
            (should (string-match-p "@satan-was-here act on this" s))
            (should (string-match-p "^> satan RUN-MD,memory_mark$" s))
            (should (string-match-p "^> noted gap$" s))
            (should-not (string-match-p "#\\+BEGIN_QUOTE" s))))))))

(ert-deftest notes-at-satan-done/no-colon-comment ()
  "A comment without a colon becomes the whole body; header has no tag."
  (satan-tools-atsatan-test--with-root root
    (let* ((file (expand-file-name "no-colon.org" root))
           (ctx  (list :id "RUN-NC" :capabilities '(write-notes))))
      (let ((coding-system-for-write 'utf-8))
        (write-region "@satan plain\n" nil file))
      (let* ((res (satan-tool/notes-at-satan-scan nil ctx))
             (id  (plist-get (car (plist-get (cdr res) :matches)) :id)))
        (satan-tool/notes-at-satan-done
         (list :match-id id :comment "just a summary") ctx)
        (with-temp-buffer
          (insert-file-contents file)
          (let ((s (buffer-string)))
            (should (string-match-p "^#\\+BEGIN_QUOTE satan RUN-NC$" s))
            (should (string-match-p "^just a summary$" s))))))))

(ert-deftest notes-at-satan-done/indent-propagates ()
  "Leading whitespace on the @satan line propagates to every block line."
  (satan-tools-atsatan-test--with-root root
    (let* ((file (expand-file-name "indent.org" root))
           (ctx  (list :id "RUN-IN" :capabilities '(write-notes))))
      (let ((coding-system-for-write 'utf-8))
        (write-region "* H\n  - @satan nested\n" nil file))
      (let* ((res (satan-tool/notes-at-satan-scan nil ctx))
             (id  (plist-get (car (plist-get (cdr res) :matches)) :id)))
        (satan-tool/notes-at-satan-done
         (list :match-id id :comment "tool: did it") ctx)
        (with-temp-buffer
          (insert-file-contents file)
          (let ((s (buffer-string)))
            (should (string-match-p "  - @satan-was-here nested" s))
            (should (string-match-p
                     "^  #\\+BEGIN_QUOTE satan RUN-IN,tool$" s))
            (should (string-match-p "^  did it$" s))
            (should (string-match-p "^  #\\+END_QUOTE$" s))))))))

(ert-deftest notes-at-satan-done/patch-job-arg-renders-queued-block ()
  "Passing :patch-job synthesises the queued-tag block.
The line is marked @satan-was-here so subsequent scans skip it; the
quoted block carries the patch-job tag and queued-<id> body."
  (satan-tools-atsatan-test--with-root root
    (let* ((file (expand-file-name "patch-job.org" root))
           (ctx  (list :id "RUN-PJ" :capabilities '(write-notes))))
      (let ((coding-system-for-write 'utf-8))
        (write-region "* H\n@satan rewrite this\n" nil file))
      (let* ((res (satan-tool/notes-at-satan-scan nil ctx))
             (id  (plist-get (car (plist-get (cdr res) :matches)) :id)))
        (satan-tool/notes-at-satan-done
         (list :match-id id :patch-job "patch_20260520T120000_abcd") ctx)
        (with-temp-buffer
          (insert-file-contents file)
          (let ((s (buffer-string)))
            (should (string-match-p "@satan-was-here rewrite this" s))
            (should (string-match-p
                     "^#\\+BEGIN_QUOTE satan RUN-PJ,patch-job$" s))
            (should (string-match-p
                     "^queued patch_20260520T120000_abcd$" s))))))))

(ert-deftest notes-at-satan-done/refuses-without-capability ()
  "Done refuses when ctx :capabilities lacks 'write-notes."
  (satan-tools-atsatan-test--with-root root
    (let* ((file (expand-file-name "trip.org" root))
           (scan-ctx (list :id "TEST-RUN" :capabilities '(write-notes)))
           (no-cap-ctx (list :id "TEST-RUN" :capabilities '())))
      (let ((coding-system-for-write 'utf-8))
        (write-region "@satan x\n" nil file))
      (let* ((res (satan-tool/notes-at-satan-scan nil scan-ctx))
             (id  (plist-get (car (plist-get (cdr res) :matches)) :id))
             (done (satan-tool/notes-at-satan-done
                    (list :match-id id) no-cap-ctx)))
        (should (eq (car done) 'error))
        (should (string-match-p "capability" (cdr done)))))))

;; ---------- T1.5b PR 4 — @satan-intervention-* directives ----------

(ert-deftest notes-at-satan-intervention/parser-happy ()
  (pcase (satan-tools-atsatan--parse-intervention-directive
          "@satan-intervention-harmful: iv_id=R.iv03 reason=\"interrupted focus\" conf=high evidence=/notes/x.org:88")
    (`(ok . ,p)
     (should (equal "harmful"           (plist-get p :classification)))
     (should (equal "R.iv03"             (plist-get p :iv-id)))
     (should (equal "interrupted focus" (plist-get p :reason)))
     (should (equal "high"              (plist-get p :conf)))
     (should (equal "/notes/x.org:88"   (plist-get p :evidence))))
    (other (ert-fail (format "expected ok, got %S" other)))))

(ert-deftest notes-at-satan-intervention/parser-defaults-conf-low ()
  (pcase (satan-tools-atsatan--parse-intervention-directive
          "@satan-intervention-contradicted: iv_id=R.iv01 reason=\"r\"")
    (`(ok . ,p)
     (should (equal "contradicted" (plist-get p :classification)))
     (should (equal "low"          (plist-get p :conf)))
     (should-not (plist-get p :evidence)))
    (other (ert-fail (format "expected ok, got %S" other)))))

(ert-deftest notes-at-satan-intervention/parser-rejects-missing-iv-id ()
  (let ((r (satan-tools-atsatan--parse-intervention-directive
            "@satan-intervention-harmful: reason=\"r\"")))
    (should (eq 'error (car r)))
    (should (string-match-p "iv_id" (cdr r)))))

(ert-deftest notes-at-satan-intervention/parser-rejects-bad-conf ()
  (let ((r (satan-tools-atsatan--parse-intervention-directive
            "@satan-intervention-harmful: iv_id=R.iv01 reason=\"r\" conf=urgent")))
    (should (eq 'error (car r)))
    (should (string-match-p "conf" (cdr r)))))

(ert-deftest notes-at-satan-intervention/parser-rejects-wrong-prefix ()
  (let ((r (satan-tools-atsatan--parse-intervention-directive
            "@satan summarise me")))
    (should (eq 'error (car r)))))

(ert-deftest notes-at-satan-intervention/rewrite-line-preserves-intervention-prefix ()
  "T1.5b PR 4 — the rewrite must replace the *full* `@satan-intervention-*'
prefix, not just `@satan' (otherwise the line becomes
`@satan-was-here-intervention-harmful', which is not claimed-re)."
  (satan-tools-atsatan-test--with-root root
    (let* ((file (expand-file-name "iv.org" root)))
      (let ((coding-system-for-write 'utf-8))
        (write-region "@satan-intervention-harmful: iv_id=X.iv01 reason=\"r\"\n"
                      nil file))
      ;; rewrite-line is the on-disk action; the helper supplies the
      ;; `iv-<cls>: <body>' tag shape so the tag carries into the QUOTE
      ;; header (after the comma).
      (let* ((tag (satan-tools-atsatan--intervention-rewrite-comment
                   "harmful" ""))
             (res (satan-tools-atsatan--rewrite-line
                   file 1 "RUN-X" tag)))
        (should (eq (car res) 'ok))
        (should (equal "done" (plist-get (cdr res) :status))))
      (with-temp-buffer
        (insert-file-contents file)
        (let ((s (buffer-string)))
          (should (string-match-p "\\`@satan-was-here:" s))
          (should-not (string-match-p "@satan-was-here-intervention" s))
          (should (string-match-p "#\\+BEGIN_QUOTE satan RUN-X,iv-harmful" s)))))))

(ert-deftest notes-at-satan-intervention/scanner-includes-and-rewrites ()
  "Scanner returns the directive (substring of `@satan'); done-handler
parses + rewrites; rescan filters it (now claimed-re matches)."
  (satan-tools-atsatan-test--with-root root
    (let* ((file (expand-file-name "iv.org" root))
           (ctx (list :id "RUN-X" :capabilities '(write-notes)
                      :time-now "2026-05-23T13:00:00+1000")))
      (let ((coding-system-for-write 'utf-8))
        (write-region
         "* heading\n@satan-intervention-harmful: iv_id=X.iv01 reason=\"interrupted\" conf=medium\n"
         nil file))
      (let* ((scan (satan-tool/notes-at-satan-scan nil ctx))
             (matches (plist-get (cdr scan) :matches)))
        (should (eq 'ok (car scan)))
        (should (= 1 (length matches)))
        (should (string-match-p "@satan-intervention-harmful"
                                (plist-get (car matches) :content))))
      ;; Pretend the writer + broker-locate succeed by stubbing.
      (cl-letf*
          (((symbol-function 'satan-intervention-lookup)
            (lambda (iv-id &optional _db)
              (list :intervention
                    (list :intervention_id iv-id
                          :ts "2026-05-23T12:00:00+1000"
                          :outcome_window_minutes 30
                          :cue_handles '("bough_node:abc")))))
           ((symbol-function 'satan-broker-locate-run-dir)
            (lambda (_run-id &optional _runs-dir) root))
           ((symbol-function 'satan-audit-reopen)
            (lambda (_dir) (list :stub-audit t)))
           (writer-calls nil)
           ((symbol-function 'satan-intervention-write-manual-outcome)
            (lambda (&rest kvs)
              (push kvs writer-calls)
              "intervention.outcome_classified")))
        (let* ((scan2 (satan-tool/notes-at-satan-scan nil ctx))
               (id (plist-get (car (plist-get (cdr scan2) :matches)) :id))
               (done (satan-tool/notes-at-satan-intervention-done
                      (list :match-id id) ctx)))
          (should (eq 'ok (car done)))
          (should (equal "done" (plist-get (cdr done) :status)))
          (should (equal "harmful"
                         (plist-get (cdr done) :classification)))
          (should (= 1 (length writer-calls)))
          (let ((kvs (car writer-calls)))
            (should (equal "harmful" (plist-get kvs :classification)))
            (should (equal "medium"  (plist-get kvs :confidence)))
            (should (equal "interrupted" (plist-get kvs :reason)))
            (should (equal "notes-directive"
                           (plist-get kvs :marked-by))))))
      ;; Rescan: claimed marker filters the line.
      (let ((rescan (satan-tool/notes-at-satan-scan nil ctx)))
        (should (zerop (plist-get (cdr rescan) :count)))))))

(ert-deftest notes-at-satan-intervention/done-refuses-without-capability ()
  (satan-tools-atsatan-test--with-root root
    (let* ((file (expand-file-name "iv.org" root))
           (scan-ctx (list :id "RUN-X" :capabilities '(write-notes)))
           (no-cap-ctx (list :id "RUN-X" :capabilities '())))
      (let ((coding-system-for-write 'utf-8))
        (write-region "@satan-intervention-harmful: iv_id=X.iv01 reason=\"r\"\n"
                      nil file))
      (let* ((scan (satan-tool/notes-at-satan-scan nil scan-ctx))
             (id (plist-get (car (plist-get (cdr scan) :matches)) :id))
             (done (satan-tool/notes-at-satan-intervention-done
                    (list :match-id id) no-cap-ctx)))
        (should (eq 'error (car done)))
        (should (string-match-p "capability" (cdr done)))))))

;; ---------- live-broker smoke (follow-up #3) ----------
;;
;; Exercises `notes_at_satan_intervention_done' against:
;;   - real `satan-intervention-create' (seeds projection + audit
;;     transcript with the intervention.created event)
;;   - real `satan-intervention-write-manual-outcome' (classify +
;;     counter-memory trace, append to the iv's own run-dir transcript
;;     via `satan-audit-reopen')
;;   - real `satan-intervention-lookup' against the projection
;;
;; Only stubs:
;;   - `satan-broker-locate-run-dir' → the audit's actual dir
;;     (same as the manual-mark dispatch test; the broker call is a
;;     thin run-id→fs-path translator the broker would otherwise
;;     resolve via its denote chain)
;;   - `satan-memory-store-mark' → record call args + return ok
;;     (avoids requiring the memory store DB write in this suite)

(ert-deftest notes-at-satan-intervention/end-to-end-smoke ()
  "Real broker integration: scan + done against a seeded run-dir and
projection.  Verifies the directive writes a live outcome event into
the iv's original transcript, updates the projection row, fires the
counter-memory mark with inherited cue handles, and rewrites the
notes line to the claimed shape."
  (skip-unless (fboundp 'satan-intervention-test--with-db))
  (satan-tools-atsatan-test--with-root scan-root
    (satan-intervention-test--with-db
     (satan-intervention--reset-counters)
     (let* ((iv-run-root (make-temp-file "satan-iv-smoke-" t))
            (run-id "20260523T120000-morning-aaaaaa")
            (audit (satan-intervention-test--open-audit
                    iv-run-root run-id))
            (iv-ctx (satan-intervention-test--build-ctx audit run-id))
            (consume-ctx (list :id "20260523T130000-tick-bbbbbb"
                               :capabilities '(write-notes)
                               :time-now "2026-05-23T13:00:00+1000"))
            (mark-calls nil))
       (unwind-protect
           (let* ((iv-id (satan-intervention-create
                          :ctx iv-ctx :kind "notify"
                          :target-surface "dbus"
                          :message "morning kanban"
                          :expected-outcome "user opens kanban.org"
                          :outcome-window-minutes 30
                          :severity "low"
                          :cue-handles '("bough_node:abc")))
                  (notes-file (expand-file-name "iv-smoke.org" scan-root)))
             (let ((coding-system-for-write 'utf-8))
               (write-region
                (format
                 "* heading\n@satan-intervention-harmful: iv_id=%s reason=\"interrupted\" conf=high evidence=/notes/x.org:88\n"
                 iv-id)
                nil notes-file))
             (cl-letf*
                 (((symbol-function 'satan-broker-locate-run-dir)
                   (lambda (_rid &optional _runs-dir)
                     (satan-audit-handle-dir audit)))
                  ((symbol-function 'satan-memory-store-mark)
                   (lambda (&rest kvs)
                     (push kvs mark-calls)
                     (cons 'ok "trace_smoke"))))
               (let* ((scan (satan-tool/notes-at-satan-scan nil consume-ctx))
                      (matches (plist-get (cdr scan) :matches))
                      (id (plist-get (car matches) :id))
                      (done (satan-tool/notes-at-satan-intervention-done
                             (list :match-id id) consume-ctx)))
                 (should (eq 'ok (car scan)))
                 (should (= 1 (length matches)))
                 (should (eq 'ok (car done)))
                 (should (equal "done"    (plist-get (cdr done) :status)))
                 (should (equal "harmful" (plist-get (cdr done) :classification)))
                 (should (equal iv-id     (plist-get (cdr done) :intervention-id)))
                 (should (equal "intervention.outcome_classified"
                                (plist-get (cdr done) :event)))))
             ;; Projection row carries the manual outcome.
             (let* ((row (satan-intervention-lookup iv-id))
                    (outcome (plist-get row :outcome)))
               (should (equal "harmful" (plist-get outcome :classification)))
               (should (equal "high"    (plist-get outcome :confidence)))
               (should (equal "manual"  (plist-get outcome :source)))
               (should (equal "notes-directive"
                              (plist-get outcome :marked_by))))
             ;; Outcome event landed in the iv's *original* transcript.
             (let* ((events (satan-intervention-test--transcript-events audit))
                    (outcome-ev (cl-find "intervention.outcome_classified" events
                                         :key (lambda (r) (plist-get r :event))
                                         :test #'equal)))
               (should outcome-ev))
             ;; Counter-memory trace fired with cue-handle inheritance.
             (should (= 1 (length mark-calls)))
             (let* ((kvs (car mark-calls))
                    (handles (plist-get kvs :handles)))
               (should (equal "negative" (plist-get kvs :valence)))
               (should (equal '("bough_node:abc")
                              (mapcar (lambda (h) (plist-get h :handle))
                                      handles))))
             ;; Notes file rewritten: claimed marker + iv-harmful tag.
             (with-temp-buffer
               (insert-file-contents notes-file)
               (let ((s (buffer-string)))
                 (should (string-match-p "@satan-was-here:" s))
                 (should-not (string-match-p "@satan-was-here-intervention" s))
                 (should (string-match-p
                          "#\\+BEGIN_QUOTE satan 20260523T130000-tick-bbbbbb,iv-harmful"
                          s)))))
         (delete-directory iv-run-root t))))))

(provide 'satan-tools-atsatan-test)
;;; satan-tools-atsatan-test.el ends here
