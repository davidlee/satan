;;; satan-tools-memory-test.el --- memory_* tool ert -*- lexical-binding: t; -*-

;; Step 8 of memory.design.md.  Cover the three `memory_*` tools
;; (mark, resonate, show_trace):
;;   - schema validation (delegated to satan-tools.el)
;;   - handler-side validation of array/object args (no :type 'array yet)
;;   - canon → evidence → store wiring (cl-letf stubs)
;;   - DB end-to-end round-trip against satan_memory_test
;;
;; The DB-touching tests skip-unless the test DB is reachable; everything
;; else runs without psql.

(require 'ert)
(require 'cl-lib)
(require 'subr-x)
(require 'satan-tools)
(require 'satan-tools-memory)
(require 'satan-memory-grammar)
(require 'satan-memory-canon)
(require 'satan-memory-evidence)
(require 'satan-memory-store)
(require 'satan-memory-migrate)

;; ---------------------------------------------------------------------
;; Fixtures
;; ---------------------------------------------------------------------

(defconst satan-tools-memory-test--db "satan_memory_test")

(defconst satan-tools-memory-test--tool-ctx
  '(:id "20260519T100000-motd-deadbe"
    :mode-name motd
    :capabilities (memory-write)
    :run-dir "/tmp/satan-run"
    :hippocampus-dir "/tmp/hipp"))

(defconst satan-tools-memory-test--evidence-stub
  '(:current_window (:app_id "firefox")
    :focus_segments nil
    :browser_segments nil
    :bough_recent nil
    :bough_active nil
    :bough_day nil
    :git_state nil
    :fs_state nil
    :window_start_at "2026-05-19T09:50:00+10:00"
    :window_end_at   "2026-05-19T10:00:00+10:00"))

(defmacro satan-tools-memory-test--stub-evidence (&rest body)
  "Stub `satan-memory-evidence-assemble' to return the fixture."
  (declare (indent 0))
  `(cl-letf (((symbol-function 'satan-memory-evidence-assemble)
              (lambda (_ctx &optional _opts)
                satan-tools-memory-test--evidence-stub)))
     ,@body))

(defmacro satan-tools-memory-test--capture-evidence-opts (var &rest body)
  "Stub `satan-memory-evidence-assemble' to return the fixture; bind
VAR to the OPTS plist it was called with."
  (declare (indent 1))
  `(let ((,var nil))
     (cl-letf (((symbol-function 'satan-memory-evidence-assemble)
                (lambda (_ctx &optional o)
                  (setq ,var o)
                  satan-tools-memory-test--evidence-stub)))
       ,@body)))

(defmacro satan-tools-memory-test--capture (var fn-sym &rest body)
  "Bind VAR to a closure that records its args into a list, and stub
FN-SYM to call it.  After BODY, VAR holds the captured arg list."
  (declare (indent 2))
  `(let ((,var nil))
     (cl-letf (((symbol-function ',fn-sym)
                (lambda (&rest args)
                  (setq ,var args)
                  (cons 'ok "20260519T100000-stubid"))))
       ,@body)))

(defun satan-tools-memory-test--reachable-p ()
  (pcase (let ((satan-memory-migrate-database
                satan-tools-memory-test--db))
           (satan-db-psql
            satan-tools-memory-test--db satan-memory-migrate-host satan-memory-migrate-psql-program
            (list "-A" "-t" "-c" "SELECT 1")))
    (`(ok . ,_) t)
    (_ nil)))

(defun satan-tools-memory-test--reset-and-migrate ()
  (let ((satan-memory-migrate-database satan-tools-memory-test--db))
    (satan-db-psql
     satan-tools-memory-test--db satan-memory-migrate-host satan-memory-migrate-psql-program
     (list "-c"
           (concat
            "DROP TABLE IF EXISTS "
            "satan_pattern_outcomes, satan_patterns, "
            "satan_intervention_outcomes, satan_interventions, "
            "patch_job_events, patch_jobs, "
            "trace_links, trace_handles, traces, "
            "handle_aliases, handle_weights, grammar_versions, "
            "schema_migrations CASCADE; "
            "DROP FUNCTION IF EXISTS "
            "memory_mark_trace(jsonb), memory_show_trace(text), "
            "memory_resonate(text[], smallint, double precision, integer, text[]), "
            "handle_weight_for(text, smallint) CASCADE;")))
    (satan-memory-migrate-apply)))

(defmacro satan-tools-memory-test--with-db (&rest body)
  (declare (indent 0))
  `(progn
     (skip-unless (satan-tools-memory-test--reachable-p))
     (satan-tools-memory-test--reset-and-migrate)
     (let ((satan-memory-store-database
            satan-tools-memory-test--db))
       ,@body)))

;; ---------------------------------------------------------------------
;; Mind-doc files exist
;; ---------------------------------------------------------------------

(ert-deftest satan-tools-memory/mind-docs-exist ()
  ;; Model-facing descriptions live in the host-only ~/notes/satan/ corpus
  ;; (SL-012 D4/POL), not shipped in the package.
  (skip-unless (file-readable-p
                (expand-file-name "memory_mark.md" satan-tools-descriptions-dir)))
  (dolist (name '("memory_mark" "memory_resonate" "memory_show_trace"))
    (let ((path (expand-file-name (concat name ".md")
                                  satan-tools-descriptions-dir)))
      (should (file-readable-p path)))))

;; ---------------------------------------------------------------------
;; Tool registration
;; ---------------------------------------------------------------------

(ert-deftest satan-tools-memory/registered ()
  (dolist (name '("memory_mark" "memory_resonate" "memory_show_trace"))
    (should (satan-tool-lookup name)))
  (should (eq 'low  (plist-get (satan-tool-lookup "memory_mark") :risk)))
  (should (eq 'read (plist-get (satan-tool-lookup "memory_resonate") :risk)))
  (should (eq 'read (plist-get (satan-tool-lookup "memory_show_trace") :risk))))

;; ---------------------------------------------------------------------
;; ctx helper
;; ---------------------------------------------------------------------

(ert-deftest satan-tools-memory/ctx-from-tool-ctx ()
  (cl-letf (((symbol-function 'satan-tools-memory--now)
             (lambda () "2026-05-19T10:00:00+10:00")))
    (let ((ctx (satan-tools-memory--ctx-from
                satan-tools-memory-test--tool-ctx)))
      (should (equal (plist-get ctx :time_now) "2026-05-19T10:00:00+10:00"))
      (should (equal (plist-get ctx :mode_name) "motd"))
      (should (equal (plist-get ctx :run_id) "20260519T100000-motd-deadbe"))
      (should (equal (plist-get ctx :current_grammar_version)
                     satan-memory-grammar-current-version)))))

(ert-deftest satan-tools-memory/ctx-from-tool-ctx-string-mode ()
  (cl-letf (((symbol-function 'satan-tools-memory--now)
             (lambda () "2026-05-19T10:00:00+10:00")))
    (let ((ctx (satan-tools-memory--ctx-from
                '(:id "r1" :mode-name "morning"))))
      (should (equal (plist-get ctx :mode_name) "morning")))))

(ert-deftest satan-tools-memory/ctx-from-prefers-tool-ctx-time-now ()
  (cl-letf (((symbol-function 'satan-tools-memory--now)
             (lambda () "WALL-CLOCK-FALLBACK")))
    (let ((ctx (satan-tools-memory--ctx-from
                '(:id "r1" :mode-name "motd"
                  :time-now "2026-05-19T10:00:00+10:00"
                  :run-started-at "2026-05-19T09:45:00+10:00"))))
      (should (equal (plist-get ctx :time_now)
                     "2026-05-19T10:00:00+10:00"))
      (should (equal (plist-get ctx :run_started_at)
                     "2026-05-19T09:45:00+10:00")))))

(ert-deftest satan-tools-memory/ctx-from-falls-back-to-wall-clock ()
  (cl-letf (((symbol-function 'satan-tools-memory--now)
             (lambda () "WALL-CLOCK-FALLBACK")))
    (let ((ctx (satan-tools-memory--ctx-from
                '(:id "r1" :mode-name "motd"))))
      (should (equal (plist-get ctx :time_now) "WALL-CLOCK-FALLBACK"))
      (should (null (plist-get ctx :run_started_at))))))

;; ---------------------------------------------------------------------
;; Schema validation (delegates to satan-tools dispatch)
;; ---------------------------------------------------------------------

(defun satan-tools-memory-test--dispatch (name args)
  "Run dispatch with the memory_* tool allowlist temporarily open."
  (satan-tool-dispatch
   (list :type "tool_call" :id "call-1" :name name :args args)
   '("memory_mark" "memory_resonate" "memory_show_trace")
   satan-tools-memory-test--tool-ctx))

(ert-deftest satan-tools-memory/mark-missing-payload-rejected ()
  (let ((res (satan-tools-memory-test--dispatch
              "memory_mark" '())))
    (should (eq (plist-get res :ok) :false))
    (should (string-match-p "payload" (plist-get res :error)))))

(ert-deftest satan-tools-memory/mark-bad-hint-kind-rejected ()
  ;; :enum on hints.kind is schema-enforced before the handler runs.
  (satan-tools-memory-test--stub-evidence
    (let ((res (satan-tools-memory-test--dispatch
                "memory_mark"
                '(:payload "x" :hints (:kind "guessing")))))
      (should (eq (plist-get res :ok) :false))
      (should (string-match-p "kind" (plist-get res :error))))))

(ert-deftest satan-tools-memory/mark-bad-valence-rejected ()
  (satan-tools-memory-test--stub-evidence
    (let ((res (satan-tools-memory-test--dispatch
                "memory_mark"
                '(:payload "x" :valence "happy"))))
      (should (eq (plist-get res :ok) :false))
      (should (string-match-p "valence" (plist-get res :error))))))

(ert-deftest satan-tools-memory/show-missing-trace-id-rejected ()
  (let ((res (satan-tools-memory-test--dispatch
              "memory_show_trace" '())))
    (should (eq (plist-get res :ok) :false))
    (should (string-match-p "trace_id" (plist-get res :error)))))

(ert-deftest satan-tools-memory/resonate-bad-min-score-rejected ()
  (let ((res (satan-tools-memory-test--dispatch
              "memory_resonate" '(:min_score "high"))))
    (should (eq (plist-get res :ok) :false))
    (should (string-match-p "min_score" (plist-get res :error)))))

;; ---------------------------------------------------------------------
;; Handler-side validation of array args
;; ---------------------------------------------------------------------

(ert-deftest satan-tools-memory/mark-non-string-topic-rejected ()
  (satan-tools-memory-test--stub-evidence
    (let ((res (satan-tools-memory-test--dispatch
                "memory_mark"
                '(:payload "x" :hints (:topic ("auth" 99))))))
      (should (eq (plist-get res :ok) :false))
      (should (string-match-p "topic" (plist-get res :error))))))

(ert-deftest satan-tools-memory/mark-bad-link-rejected ()
  (satan-tools-memory-test--stub-evidence
    (let ((res (satan-tools-memory-test--dispatch
                "memory_mark"
                '(:payload "x"
                  :links ((:relation "relates_to"))))))
      (should (eq (plist-get res :ok) :false))
      (should (string-match-p "link" (plist-get res :error))))))

(ert-deftest satan-tools-memory/resonate-non-string-kinds-rejected ()
  (let ((res (satan-tools-memory-test--dispatch
              "memory_resonate" '(:kinds (1 2)))))
    (should (eq (plist-get res :ok) :false))
    (should (string-match-p "kinds" (plist-get res :error)))))

(ert-deftest satan-tools-memory/resonate-non-string-cue-handles-rejected ()
  (let ((res (satan-tools-memory-test--dispatch
              "memory_resonate" '(:cue (:handles (42))))))
    (should (eq (plist-get res :ok) :false))
    (should (string-match-p "handles" (plist-get res :error)))))

;; ---------------------------------------------------------------------
;; mark — canon + store wiring (stubs)
;; ---------------------------------------------------------------------

(ert-deftest satan-tools-memory/mark-packages-handles-with-sources ()
  (satan-tools-memory-test--stub-evidence
    (satan-tools-memory-test--capture
        captured satan-memory-store-mark
      (let ((res (satan-tools-memory-test--dispatch
                  "memory_mark"
                  '(:payload "user pivoted")))
            store-args)
        (should (eq (plist-get res :ok) t))
        (setq store-args captured)
        ;; store-args is a flat keyword arg list.
        (let* ((handles (plist-get store-args :handles))
               (handle-strs (mapcar (lambda (h) (plist-get h :handle)) handles)))
          (should handles)
          ;; The fixture's current_window app_id "firefox" emits at least
          ;; `app:firefox' and `surface:browser'.
          (should (member "app:firefox" handle-strs))
          (should (member "surface:browser" handle-strs))
          ;; Every handle row carries its source plist.
          (dolist (h handles)
            (let ((src (plist-get h :source)))
              (should src)
              (should (plist-get src :rule_id))
              (should (plist-get src :origin)))))
        ;; Trace-level metadata.
        (should (equal "llm_mark" (plist-get store-args :trace-origin)))
        (should (equal "memory_mark@motd" (plist-get store-args :source)))
        (should (equal "observation" (plist-get store-args :kind)))
        (should (equal satan-memory-grammar-current-version
                       (plist-get store-args :grammar-version)))
        (should (equal "2026-05-19T09:50:00+10:00"
                       (plist-get store-args :observed-start-at)))
        (should (equal "2026-05-19T10:00:00+10:00"
                       (plist-get store-args :observed-end-at)))))))

(ert-deftest satan-tools-memory/resonate-derives-cue-with-cue-only-opt ()
  "`memory_resonate' (no explicit handles) re-runs evidence-assemble for
cue derivation with `:cue_only t' so heavy probes are skipped."
  (satan-tools-memory-test--capture-evidence-opts opts
    (cl-letf (((symbol-function 'satan-memory-store-resonate)
               (lambda (&rest _) (cons 'ok nil))))
      (let ((res (satan-tool-dispatch
                  '(:type "tool_call" :id "c1" :name "memory_resonate"
                    :args (:cue (:hints (:topic ("ux")))))
                  '("memory_resonate")
                  '(:id "r1" :mode-name motd
                    :time-now "2026-05-19T10:00:00+10:00"
                    :run-started-at "2026-05-19T09:55:00+10:00"))))
        (should (eq (plist-get res :ok) t))
        (should (eq (plist-get opts :cue_only) t))
        (should (equal (plist-get opts :run_started_at)
                       "2026-05-19T09:55:00+10:00"))))))

(ert-deftest satan-tools-memory/mark-does-not-set-cue-only ()
  "`memory_mark' assembles a full evidence window (no :cue_only)."
  (satan-tools-memory-test--capture-evidence-opts opts
    (satan-tools-memory-test--capture
        _captured satan-memory-store-mark
      (let ((res (satan-tool-dispatch
                  '(:type "tool_call" :id "c2" :name "memory_mark"
                    :args (:payload "p"))
                  '("memory_mark")
                  satan-tools-memory-test--tool-ctx)))
        (should (eq (plist-get res :ok) t))
        (should-not (plist-get opts :cue_only))))))

(ert-deftest satan-tools-memory/mark-forwards-run-started-at-to-evidence ()
  "`memory_mark' threads `:run_started_at' from tool-ctx through to the
evidence assembler so the window can't reach behind the run."
  (satan-tools-memory-test--capture-evidence-opts opts
    (satan-tools-memory-test--capture
        _captured satan-memory-store-mark
      (let ((res (satan-tool-dispatch
                  '(:type "tool_call" :id "c1" :name "memory_mark"
                    :args (:payload "p"))
                  '("memory_mark")
                  '(:id "r1" :mode-name motd
                    :capabilities (memory-write)
                    :time-now "2026-05-19T10:00:00+10:00"
                    :run-started-at "2026-05-19T09:55:00+10:00"))))
        (should (eq (plist-get res :ok) t))
        (should (equal (plist-get opts :run_started_at)
                       "2026-05-19T09:55:00+10:00"))))))

(ert-deftest satan-tools-memory/mark-capability-required ()
  "`memory_mark' is refused by the dispatcher when the run-ctx lacks
the `memory-write' capability (spec `:capability').  Guards the gap
this enforcement closed — the capability was declared on modes but
enforced nowhere before."
  (let ((res (satan-tool-dispatch
              '(:type "tool_call" :id "c1" :name "memory_mark"
                :args (:payload "p"))
              '("memory_mark")
              '(:id "r1" :mode-name motd
                :capabilities (write-daily)))))
    (should (eq (plist-get res :ok) :false))
    (should (string-match-p "memory-write" (plist-get res :error)))))

(ert-deftest satan-tools-memory/mark-result-shape ()
  (satan-tools-memory-test--stub-evidence
    (satan-tools-memory-test--capture
        captured satan-memory-store-mark
      (let ((res (satan-tools-memory-test--dispatch
                  "memory_mark"
                  '(:payload "p"))))
        (should (eq (plist-get res :ok) t))
        (should captured)
        (let ((result (plist-get res :result)))
          (should (equal (plist-get result :trace_id) "20260519T100000-stubid"))
          (should (listp (plist-get result :handles)))
          (should (listp (plist-get result :rejected))))))))

(ert-deftest satan-tools-memory/mark-top-level-valence-wins ()
  (satan-tools-memory-test--stub-evidence
    (satan-tools-memory-test--capture
        captured satan-memory-store-mark
      (satan-tools-memory-test--dispatch
       "memory_mark"
       '(:payload "p" :valence "negative"
         :hints (:valence "positive")))
      (should (equal "negative" (plist-get captured :valence))))))

(ert-deftest satan-tools-memory/mark-hint-valence-fallback ()
  (satan-tools-memory-test--stub-evidence
    (satan-tools-memory-test--capture
        captured satan-memory-store-mark
      (satan-tools-memory-test--dispatch
       "memory_mark"
       '(:payload "p" :hints (:valence "positive")))
      (should (equal "positive" (plist-get captured :valence))))))

(ert-deftest satan-tools-memory/mark-rejected-pass-through ()
  ;; Schema admits hints.phase as a free string (canon validates); a
  ;; bogus phase value lands in `rejected' rather than schema-error.
  (satan-tools-memory-test--stub-evidence
    (satan-tools-memory-test--capture
        captured satan-memory-store-mark
      (let* ((res (satan-tools-memory-test--dispatch
                   "memory_mark"
                   '(:payload "p" :hints (:phase "bogus"))))
             (result (plist-get res :result)))
        (should (eq (plist-get res :ok) t))
        (should captured)
        (let* ((rejected (plist-get result :rejected))
               (rj (car rejected)))
          (should (= 1 (length rejected)))
          (should (eq (plist-get rj :field) 'phase))
          (should (equal (plist-get rj :value) "bogus")))))))

(ert-deftest satan-tools-memory/mark-propagates-store-error ()
  (satan-tools-memory-test--stub-evidence
    (cl-letf (((symbol-function 'satan-memory-store-mark)
               (lambda (&rest _) (cons 'error "boom"))))
      (let ((res (satan-tools-memory-test--dispatch
                  "memory_mark"
                  '(:payload "p"))))
        (should (eq (plist-get res :ok) :false))
        (should (string-match-p "boom" (plist-get res :error)))))))

;; ---------------------------------------------------------------------
;; resonate — store wiring (stubs)
;; ---------------------------------------------------------------------

(ert-deftest satan-tools-memory/resonate-explicit-handles ()
  ;; Explicit cue.handles bypasses the evidence assembler.
  (let (evidence-called)
    (cl-letf (((symbol-function 'satan-memory-evidence-assemble)
               (lambda (&rest _) (setq evidence-called t) nil))
              ((symbol-function 'satan-memory-store-resonate)
               (lambda (&rest args)
                 (cons 'ok
                       (list
                        (list :trace_id "t1" :score 1.5
                              :matched_handles (plist-get args :cue-handles)))))))
      (let* ((res (satan-tools-memory-test--dispatch
                   "memory_resonate"
                   '(:cue (:handles ("app:firefox" "mode:motd")))))
             (result (plist-get res :result)))
        (should (eq (plist-get res :ok) t))
        (should (null evidence-called))
        (should (equal '("app:firefox" "mode:motd")
                       (plist-get result :cue_handles)))
        (should (= 1 (length (plist-get result :matches))))))))

(ert-deftest satan-tools-memory/resonate-derives-from-hints ()
  ;; No explicit cue.handles → assemble evidence, canonicalize the hints.
  (satan-tools-memory-test--stub-evidence
    (let (passed-args)
      (cl-letf (((symbol-function 'satan-memory-store-resonate)
                 (lambda (&rest args)
                   (setq passed-args args)
                   (cons 'ok nil))))
        (let* ((res (satan-tools-memory-test--dispatch
                     "memory_resonate"
                     '(:cue (:hints (:topic ("auth"))))))
               (result (plist-get res :result))
               (cue (plist-get result :cue_handles)))
          (should (eq (plist-get res :ok) t))
          ;; The fixture's app_id firefox should canon to app:firefox.
          (should (member "app:firefox" cue))
          ;; topic hint propagates as topic:auth.
          (should (member "topic:auth" cue))
          (should (equal cue (plist-get passed-args :cue-handles))))))))

(ert-deftest satan-tools-memory/resonate-empty-cue-is-empty ()
  ;; No cue at all → derive from evidence; with the fixture this yields
  ;; at least one handle.  But if a caller passes :cue {} explicitly with
  ;; neither handles nor hints, the same code path runs.
  (satan-tools-memory-test--stub-evidence
    (cl-letf (((symbol-function 'satan-memory-store-resonate)
               (lambda (&rest _) (cons 'ok nil))))
      (let ((res (satan-tools-memory-test--dispatch
                  "memory_resonate" '())))
        (should (eq (plist-get res :ok) t))))))

(ert-deftest satan-tools-memory/resonate-forwards-limit-kinds-min-score ()
  (let (passed)
    (cl-letf (((symbol-function 'satan-memory-store-resonate)
               (lambda (&rest args)
                 (setq passed args)
                 (cons 'ok nil))))
      (satan-tools-memory-test--dispatch
       "memory_resonate"
       '(:cue (:handles ("app:firefox"))
         :limit 12 :kinds ("prediction" "outcome") :min_score 0.25))
      (should (= 12 (plist-get passed :limit)))
      (should (equal '("prediction" "outcome") (plist-get passed :kinds)))
      (should (= 0.25 (plist-get passed :min-score))))))

(ert-deftest satan-tools-memory/resonate-propagates-store-error ()
  (cl-letf (((symbol-function 'satan-memory-store-resonate)
             (lambda (&rest _) (cons 'error "psql down"))))
    (let ((res (satan-tools-memory-test--dispatch
                "memory_resonate"
                '(:cue (:handles ("app:firefox"))))))
      (should (eq (plist-get res :ok) :false))
      (should (string-match-p "psql down" (plist-get res :error))))))

;; ---------------------------------------------------------------------
;; show_trace — store wiring (stubs)
;; ---------------------------------------------------------------------

(ert-deftest satan-tools-memory/show-pass-through ()
  (cl-letf (((symbol-function 'satan-memory-store-show)
             (lambda (tid &rest _)
               (cons 'ok (list :trace (list :id tid))))))
    (let* ((res (satan-tools-memory-test--dispatch
                 "memory_show_trace" '(:trace_id "abc")))
           (result (plist-get res :result)))
      (should (eq (plist-get res :ok) t))
      (should (equal "abc" (plist-get (plist-get result :trace) :id))))))

(ert-deftest satan-tools-memory/show-missing-trace-ok-nil ()
  (cl-letf (((symbol-function 'satan-memory-store-show)
             (lambda (&rest _) (cons 'ok nil))))
    (let ((res (satan-tools-memory-test--dispatch
                "memory_show_trace" '(:trace_id "absent"))))
      (should (eq (plist-get res :ok) t))
      (should (null (plist-get res :result))))))

;; ---------------------------------------------------------------------
;; DB end-to-end (skip-unless reachable)
;; ---------------------------------------------------------------------

(ert-deftest satan-tools-memory/db-mark-show-round-trip ()
  (satan-tools-memory-test--with-db
    (satan-tools-memory-test--stub-evidence
      (let* ((mark-res (satan-tools-memory-test--dispatch
                        "memory_mark"
                        '(:payload "round-trip" :valence "neutral")))
             (mark-out (plist-get mark-res :result))
             (tid (plist-get mark-out :trace_id)))
        (should (eq (plist-get mark-res :ok) t))
        (should (stringp tid))
        ;; show
        (let* ((show-res (satan-tools-memory-test--dispatch
                          "memory_show_trace"
                          (list :trace_id tid)))
               (show-out (plist-get show-res :result)))
          (should (eq (plist-get show-res :ok) t))
          (should (equal tid (plist-get (plist-get show-out :trace) :id)))
          (should (equal "round-trip"
                         (plist-get (plist-get show-out :trace) :payload))))))))

(ert-deftest satan-tools-memory/db-resonate-finds-mark ()
  (satan-tools-memory-test--with-db
    (satan-tools-memory-test--stub-evidence
      (satan-tools-memory-test--dispatch
       "memory_mark" '(:payload "for recall"))
      (let* ((res (satan-tools-memory-test--dispatch
                   "memory_resonate"
                   '(:cue (:handles ("app:firefox")) :limit 5)))
             (result (plist-get res :result)))
        (should (eq (plist-get res :ok) t))
        (should (>= (length (plist-get result :matches)) 1))
        (should (member "app:firefox" (plist-get result :cue_handles)))))))

(provide 'satan-tools-memory-test)
;;; satan-tools-memory-test.el ends here
