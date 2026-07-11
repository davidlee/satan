;;; dl-satan-resonance-test.el --- Phase 2 resonance ert -*- lexical-binding: t; -*-

;; Phase 2 of perceptual-design.md.  Covers:
;;
;;   A4   resonance block IFF gate passes + memory reachable + ≥1 match
;;   A5   gate exclusion comprehensive (mode/day/week/project/file_kind)
;;
;; The store is stubbed via the derive helper's `:store-resonate' opt
;; so tests never touch PG.  Phase 2.4 fixtures cover gate-skip,
;; zero-matches, and psql-down paths explicitly.

(require 'ert)
(require 'cl-lib)
(require 'dl-satan-resonance)

;; ---------------------------------------------------------------------
;; Helpers
;; ---------------------------------------------------------------------

(defun dl-satan-resonance-test--percept (handles sources)
  "Return a minimal percept plist with HANDLES + per-handle SOURCES.
SOURCES is a list of plists in handle order; each carries `:rule_id'."
  (list :handles handles
        :handle_sources sources))

(defun dl-satan-resonance-test--src (rule-id handle)
  "Source row matching `dl-satan-percept--sources-rows' output for HANDLE."
  (list :handle handle :rule_id rule-id))

(defun dl-satan-resonance-test--ok-stub (matches)
  "Return a `:store-resonate' stub returning (ok . MATCHES) regardless of args."
  (lambda (&rest _) (cons 'ok matches)))

(defun dl-satan-resonance-test--err-stub (msg)
  "Return a `:store-resonate' stub returning (error . MSG)."
  (lambda (&rest _) (cons 'error msg)))

;; ---------------------------------------------------------------------
;; Gate (A5 — exclusion comprehensive)
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-resonance/gate-skip-ctx-only ()
  "Cue containing only ctx-derived handles (mode + day + week) is
gate-skipped — no store call, status `gate-skip'."
  (let* ((called 0)
         (percept (dl-satan-resonance-test--percept
                   '("day:2026-05-19" "mode:motd" "week:2026-W21")
                   (list (dl-satan-resonance-test--src
                          "time.day_week" "day:2026-05-19")
                         (dl-satan-resonance-test--src
                          "ctx.mode" "mode:motd")
                         (dl-satan-resonance-test--src
                          "time.day_week" "week:2026-W21"))))
         (stub (lambda (&rest _) (cl-incf called) (cons 'ok nil)))
         (result (dl-satan-resonance-derive
                  percept (list :store-resonate stub))))
    (should (eq (plist-get result :status) 'gate-skip))
    (should (null (plist-get result :matches)))
    (should (= called 0))))

(ert-deftest dl-satan-resonance/gate-skip-project-cwd-only ()
  "Cue with only cwd-derived `project:*' is gate-skipped (§S2)."
  (let* ((percept (dl-satan-resonance-test--percept
                   '("project:emacs.d")
                   (list (dl-satan-resonance-test--src
                          "cwd.project" "project:emacs.d"))))
         (result (dl-satan-resonance-derive
                  percept
                  (list :store-resonate
                        (dl-satan-resonance-test--ok-stub
                         '((:trace_id "t1" :score 5.0
                            :matched_handles ("project:emacs.d"))))))))
    (should (eq (plist-get result :status) 'gate-skip))
    (should (null (plist-get result :matches)))))

(ert-deftest dl-satan-resonance/gate-skip-file-kind-only ()
  "Cue with only `file_kind:*' (cwd-derived) is gate-skipped."
  (let* ((percept (dl-satan-resonance-test--percept
                   '("file_kind:elisp")
                   (list (dl-satan-resonance-test--src
                          "cwd.file_kind" "file_kind:elisp"))))
         (result (dl-satan-resonance-derive
                  percept
                  (list :store-resonate
                        (dl-satan-resonance-test--ok-stub nil)))))
    (should (eq (plist-get result :status) 'gate-skip))))

(ert-deftest dl-satan-resonance/gate-skip-all-excluded-combined ()
  "A5 — full exclude list combined still skips.  Cues that mix every
excluded rule but nothing sensor-observed must NOT admit."
  (let* ((percept (dl-satan-resonance-test--percept
                   '("day:2026-05-19" "file_kind:elisp" "mode:motd"
                     "project:emacs.d" "week:2026-W21")
                   (list (dl-satan-resonance-test--src
                          "time.day_week" "day:2026-05-19")
                         (dl-satan-resonance-test--src
                          "cwd.file_kind" "file_kind:elisp")
                         (dl-satan-resonance-test--src
                          "ctx.mode" "mode:motd")
                         (dl-satan-resonance-test--src
                          "cwd.project" "project:emacs.d")
                         (dl-satan-resonance-test--src
                          "time.day_week" "week:2026-W21"))))
         (result (dl-satan-resonance-derive
                  percept
                  (list :store-resonate
                        (dl-satan-resonance-test--ok-stub nil)))))
    (should (eq (plist-get result :status) 'gate-skip))))

(ert-deftest dl-satan-resonance/gate-skip-empty-cue ()
  "Empty handle list is gate-skipped without calling the store."
  (let* ((called 0)
         (percept (dl-satan-resonance-test--percept nil nil))
         (stub (lambda (&rest _) (cl-incf called) (cons 'ok nil)))
         (result (dl-satan-resonance-derive
                  percept (list :store-resonate stub))))
    (should (eq (plist-get result :status) 'gate-skip))
    (should (= called 0))))

;; ---------------------------------------------------------------------
;; Gate admit
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-resonance/gate-admits-when-panopticon-observed ()
  "A single sensor-observed handle (panopticon.current.app) admits the
cue; the full handle list is forwarded to the store (excluded handles
still contribute score weight per §S2 — gate is admit-only)."
  (let* ((passed nil)
         (percept (dl-satan-resonance-test--percept
                   '("app:firefox" "day:2026-05-19" "mode:motd")
                   (list (dl-satan-resonance-test--src
                          "panopticon.current.app" "app:firefox")
                         (dl-satan-resonance-test--src
                          "time.day_week" "day:2026-05-19")
                         (dl-satan-resonance-test--src
                          "ctx.mode" "mode:motd"))))
         (stub (lambda (&rest args)
                 (setq passed args)
                 (cons 'ok
                       '((:trace_id "20260518T120000-a"
                          :score 7.5
                          :matched_handles ("app:firefox" "mode:motd"))))))
         (result (dl-satan-resonance-derive
                  percept (list :store-resonate stub))))
    (should (eq (plist-get result :status) 'ok))
    (should (equal (plist-get passed :cue-handles)
                   '("app:firefox" "day:2026-05-19" "mode:motd")))
    (should (= 1 (length (plist-get result :matches))))))

(ert-deftest dl-satan-resonance/gate-admits-bough-event ()
  "`bough_event:*' (bough.recent_status_change) admits."
  (let* ((percept (dl-satan-resonance-test--percept
                   '("bough_event:status_changed" "day:2026-05-19")
                   (list (dl-satan-resonance-test--src
                          "bough.recent_status_change"
                          "bough_event:status_changed")
                         (dl-satan-resonance-test--src
                          "time.day_week" "day:2026-05-19"))))
         (result (dl-satan-resonance-derive
                  percept
                  (list :store-resonate
                        (dl-satan-resonance-test--ok-stub
                         '((:trace_id "tid" :score 3.0
                            :matched_handles ("bough_event:status_changed"))))))))
    (should (eq (plist-get result :status) 'ok))))

(ert-deftest dl-satan-resonance/limit-forwarded-to-store ()
  "Default limit is 3 (design §S2 top 1–3); explicit `:limit' overrides."
  (let* ((passed nil)
         (percept (dl-satan-resonance-test--percept
                   '("app:firefox")
                   (list (dl-satan-resonance-test--src
                          "panopticon.current.app" "app:firefox"))))
         (stub (lambda (&rest args) (setq passed args) (cons 'ok nil))))
    (dl-satan-resonance-derive percept (list :store-resonate stub))
    (should (= (plist-get passed :limit) 3))
    (setq passed nil)
    (dl-satan-resonance-derive
     percept (list :store-resonate stub :limit 1))
    (should (= (plist-get passed :limit) 1))))

;; ---------------------------------------------------------------------
;; A4 — block emitted IFF ok + matches
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-resonance/zero-matches-yields-no-match-status ()
  "Gate passes + store returns ok with no rows → status `no-match'
(distinct from gate-skip); block omits."
  (let* ((percept (dl-satan-resonance-test--percept
                   '("app:firefox")
                   (list (dl-satan-resonance-test--src
                          "panopticon.current.app" "app:firefox"))))
         (result (dl-satan-resonance-derive
                  percept
                  (list :store-resonate
                        (dl-satan-resonance-test--ok-stub nil))))
         (block (dl-satan-resonance-render-block
                 '(("resonance_block_header" . "# Resonance"))
                 result)))
    (should (eq (plist-get result :status) 'no-match))
    (should (null block))))

(ert-deftest dl-satan-resonance/psql-down-yields-memory-unreachable ()
  "Store error → status `memory-unreachable' (handover watch-out: not a
run failure); block omits.  Audit consumers can distinguish from
gate-skip via `:status'."
  (let* ((percept (dl-satan-resonance-test--percept
                   '("app:firefox")
                   (list (dl-satan-resonance-test--src
                          "panopticon.current.app" "app:firefox"))))
         (result (dl-satan-resonance-derive
                  percept
                  (list :store-resonate
                        (dl-satan-resonance-test--err-stub "psql exit 1"))))
         (block (dl-satan-resonance-render-block
                 '(("resonance_block_header" . "# Resonance"))
                 result)))
    (should (eq (plist-get result :status) 'memory-unreachable))
    (should (null block))))

(ert-deftest dl-satan-resonance/render-block-shape ()
  "A4 — ok + ≥1 match renders header + per-match trace_id/score/matched
lines.  Header text comes from framing.txt; rendering with a different
key suppresses the block (mind owns the header)."
  (let* ((framing '(("resonance_block_header" . "# Resonance")))
         (result (list :status 'ok
                       :cue '("app:firefox")
                       :matches
                       '((:trace_id "20260518T120000-aaa"
                          :score 11.2
                          :matched_handles ("project:emacs.d"
                                            "surface_transition:terminal->browser"
                                            "domain_kind:docs"))
                         (:trace_id "20260515T080000-bbb"
                          :score 6.5
                          :matched_handles ("app:firefox" "mode:motd")))))
         (lines (dl-satan-resonance-render-block framing result)))
    (should (equal (car lines) "# Resonance"))
    (should (equal (nth 1 lines)
                   "- 20260518T120000-aaa  score 11.2"))
    (should (equal (nth 2 lines)
                   (concat "    matched: project:emacs.d, "
                           "surface_transition:terminal->browser, "
                           "domain_kind:docs")))
    (should (equal (nth 3 lines)
                   "- 20260515T080000-bbb  score 6.5"))
    (should (equal (nth 4 lines)
                   "    matched: app:firefox, mode:motd"))))

(ert-deftest dl-satan-resonance/render-block-includes-payload-line ()
  "A match carrying `:payload' emits a third indented, quoted line so the
model reads the recalled context without a `memory_show_trace' round-trip."
  (let* ((framing '(("resonance_block_header" . "# Resonance")))
         (result (list :status 'ok
                       :matches
                       (list (list :trace_id "20260518T120000-aaa"
                                   :score 11.2
                                   :matched_handles '("domain_kind:docs")
                                   :payload
                                   (concat "after terminal error in emacs.d, "
                                           "user moved to docs and produced "
                                           "no artifact")))))
         (lines (dl-satan-resonance-render-block framing result)))
    (should (equal (nth 1 lines) "- 20260518T120000-aaa  score 11.2"))
    (should (equal (nth 2 lines) "    matched: domain_kind:docs"))
    (should (equal (nth 3 lines)
                   (concat "    \"after terminal error in emacs.d, "
                           "user moved to docs and produced no artifact\"")))))

(ert-deftest dl-satan-resonance/render-block-omits-empty-payload-line ()
  "Nil or empty payload self-suppresses the third line (no empty quotes);
the match still renders its trace_id + matched lines."
  (let* ((framing '(("resonance_block_header" . "# Resonance")))
         (result (list :status 'ok
                       :matches
                       (list (list :trace_id "t-nil" :score 1.0
                                   :matched_handles '("app:firefox"))
                             (list :trace_id "t-empty" :score 2.0
                                   :matched_handles '("app:firefox")
                                   :payload "")))))
    (should (equal (dl-satan-resonance-render-block framing result)
                   (list "# Resonance"
                         "- t-nil  score 1.0"
                         "    matched: app:firefox"
                         "- t-empty  score 2.0"
                         "    matched: app:firefox")))))

(ert-deftest dl-satan-resonance/render-block-truncates-long-payload ()
  "An over-long payload is truncated with an ellipsis so one recalled
trace cannot blow the tick capsule budget."
  (let* ((framing '(("resonance_block_header" . "# Resonance")))
         (long (make-string 300 ?x))
         (result (list :status 'ok
                       :matches
                       (list (list :trace_id "t1" :score 1.0
                                   :matched_handles '("app:firefox")
                                   :payload long))))
         (lines (dl-satan-resonance-render-block framing result))
         (payload-line (nth 3 lines)))
    (should (string-prefix-p "    \"" payload-line))
    (should (string-suffix-p "…\"" payload-line))
    (should (< (length payload-line) (length long)))))

(ert-deftest dl-satan-resonance/render-block-without-framing-key-yields-nil ()
  "Mind owns the header text; absent key in framing.txt suppresses the
section.  Guards against silent fallback to a hardcoded header."
  (let* ((framing '(("percept_block_header" . "# Percept")))
         (result (list :status 'ok
                       :matches '((:trace_id "tid" :score 1.0
                                   :matched_handles ("app:firefox"))))))
    (should (null (dl-satan-resonance-render-block framing result)))))

(ert-deftest dl-satan-resonance/render-block-omits-on-gate-skip ()
  "A4 — gate-skip never renders a block, even with framing key present."
  (let* ((framing '(("resonance_block_header" . "# Resonance"))))
    (should (null (dl-satan-resonance-render-block
                   framing (list :status 'gate-skip :matches nil))))))

;; ---------------------------------------------------------------------
;; Real-percept fixtures (2.4) — drive the canon, not synthetic rows.
;;
;; If canon rule_ids drift from the gate's exclude list, the gate
;; silently weakens and the model drowns in low-signal recall.  These
;; tests close the loop: they build a real percept with frozen
;; sensors and assert the gate routes it the way §S2 promises.
;; ---------------------------------------------------------------------

(require 'dl-satan-percept)

(defmacro dl-satan-resonance-test--with-sensor-fixture (vars &rest body)
  "Parallel to `dl-satan-percept-test--with-fixture' — give BODY a tmp
behaviour dir and run dir, with `dl-satan-bough-program' shunted to a
non-existent path so bough probes return nil."
  (declare (indent 1))
  (let ((tmp (plist-get vars :tmp))
        (beh (plist-get vars :behaviour))
        (rd  (plist-get vars :run-dir)))
    `(let* ((,tmp (make-temp-file "satan-resonance-fix-" t))
            (,beh (file-name-as-directory
                   (expand-file-name "behaviour" ,tmp)))
            (,rd  (file-name-as-directory
                   (expand-file-name "run" ,tmp))))
       (unwind-protect
           (let ((dl-satan-bough-program "/nonexistent/bough"))
             (make-directory ,beh t)
             (make-directory ,rd t)
             ,@body)
         (delete-directory ,tmp t)))))

(defun dl-satan-resonance-test--write-sway (behaviour app)
  (let ((dir (expand-file-name "current" behaviour)))
    (make-directory dir t)
    (with-temp-file (expand-file-name "sway.json" dir)
      (insert (format "{\"app_id\":\"%s\",\"workspace\":\"main\"}" app)))))

(defun dl-satan-resonance-test--prepare (run-id time-now)
  (list :run_id run-id :time_now time-now :start_time (current-time)
        :evidence nil :percept nil
        :sensor_status nil :pre_spawn nil :motive nil))

(ert-deftest dl-satan-resonance/fixture-real-percept-gate-skip-when-no-sensors ()
  "A5 — a real percept built from an empty behaviour dir + nonexistent
cwd carries only ctx-derived handles (mode, day, week).  The gate
must skip — no store call, no block.  This locks the gate against
canon-rule renames: if `ctx.mode' or `time.day_week' moves, this
test trips before §S2 silently weakens."
  (dl-satan-resonance-test--with-sensor-fixture (:tmp _t :behaviour beh :run-dir rd)
    (let* ((prepare (dl-satan-resonance-test--prepare
                     "20260519T100000-motd-aaaaaa"
                     "2026-05-19T10:00:00+10:00"))
           (percept (dl-satan-percept-build
                     prepare '(:name "motd")
                     (list :behaviour_dir beh :cwd "/nonexistent/dir/")))
           (called 0)
           (stub (lambda (&rest _) (cl-incf called) (cons 'ok nil)))
           (result (dl-satan-resonance-derive
                    percept (list :store-resonate stub))))
      ;; Canon emitted some handles (mode + day + week at minimum),
      ;; so this is genuinely the "only-excluded" path, not the
      ;; empty-cue short-circuit.
      (should (plist-get percept :handles))
      (should (eq (plist-get result :status) 'gate-skip))
      (should (= called 0)))))

(ert-deftest dl-satan-resonance/fixture-real-percept-gate-admits-on-panopticon ()
  "A real percept with a current_window sensor reading emits
`app:firefox' (rule `panopticon.current.app') alongside the ctx-derived
handles.  The gate admits — the panopticon-observed handle clears the
noise floor."
  (dl-satan-resonance-test--with-sensor-fixture (:tmp _t :behaviour beh :run-dir rd)
    (ignore rd)
    (dl-satan-resonance-test--write-sway beh "firefox")
    (let* ((prepare (dl-satan-resonance-test--prepare
                     "20260519T100000-motd-bbbbbb"
                     "2026-05-19T10:00:00+10:00"))
           (percept (dl-satan-percept-build
                     prepare '(:name "motd")
                     (list :behaviour_dir beh :cwd "/nonexistent/dir/")))
           (passed nil)
           (stub (lambda (&rest args)
                   (setq passed args)
                   (cons 'ok
                         '((:trace_id "20260518T120000-aaa"
                            :score 8.0
                            :matched_handles ("app:firefox")))))))
      (should (member "app:firefox" (plist-get percept :handles)))
      (let ((result (dl-satan-resonance-derive
                     percept (list :store-resonate stub))))
        (should (eq (plist-get result :status) 'ok))
        ;; Excluded handles still ride along in the cue — the gate is
        ;; admit-only; scoring weight comes from every handle that's
        ;; in the index.
        (should (member "app:firefox" (plist-get passed :cue-handles)))
        (should (member "mode:motd" (plist-get passed :cue-handles)))))))

(ert-deftest dl-satan-resonance/fixture-exclude-list-matches-canon-rule-ids ()
  "Lock the gate's exclude list against the canon's actual rule ids.
If a canon rule named in `dl-satan-resonance--excluded-rule-ids' has
been renamed or removed, this test fails loudly — better than the
gate silently weakening because a string compare stopped matching."
  (let ((registered (mapcar (lambda (cell) (symbol-name (car cell)))
                            dl-satan-memory-canon--rules)))
    (dolist (excluded dl-satan-resonance--excluded-rule-ids)
      (should (member excluded registered)))))

;; ---------------------------------------------------------------------
;; Capsule integration (2.3) — block lands between percept and today
;; ---------------------------------------------------------------------

(require 'dl-satan-context)

(defmacro dl-satan-resonance-test--with-framing (tmp-sym &rest body)
  "Bind a tmp dir to TMP-SYM and seed minimal scaffold + framing + prompt
files under it; rebind `dl-satan-system-scaffold-file' and
`dl-satan-system-framing-file' for BODY's dynamic extent.  Framing
includes the resonance + percept headers so render-prompt has both
to inject."
  (declare (indent 1))
  `(let* ((,tmp-sym (make-temp-file "satan-resonance-cap-" t))
          (dl-satan-system-scaffold-file
           (expand-file-name "system/scaffold.txt" ,tmp-sym))
          (dl-satan-system-framing-file
           (expand-file-name "system/framing.txt" ,tmp-sym)))
     (unwind-protect
         (progn
           (make-directory (expand-file-name "prompts" ,tmp-sym))
           (make-directory (expand-file-name "system" ,tmp-sym))
           (with-temp-file dl-satan-system-scaffold-file (insert "SCAFFOLD"))
           (with-temp-file dl-satan-system-framing-file
             (insert "now=# Now\n"
                     "percept_block_header=# Percept\n"
                     "resonance_block_header=# Resonance\n"
                     "today=# Today (raw)\n"
                     "sources=# Source files\n"
                     "recent_runs=# Recent SATAN runs\n"))
           (with-temp-file (expand-file-name "prompts/motd.txt" ,tmp-sym)
             (insert "PROMPT"))
           ,@body)
       (delete-directory ,tmp-sym t))))

(ert-deftest dl-satan-resonance/capsule-renders-resonance-block-from-prepare ()
  "A4 — when PREPARE carries a `:resonance' with status `ok' and ≥1
match, the rendered prompt contains a `# Resonance' header.  The
block lands between `# Percept' and `# Today (raw)' per design §S2."
  (dl-satan-resonance-test--with-framing tmp
    (let* ((spec (list :name "motd"
                       :prompt-file
                       (expand-file-name "prompts/motd.txt" tmp)))
           (prepare (list :run_id "rid-x"
                          :time_now "2026-05-19T10:00:00+10:00"
                          :percept '(:handles ("app:firefox"))
                          :resonance
                          (list :status 'ok
                                :cue '("app:firefox")
                                :matches
                                '((:trace_id "20260518T120000-aaa"
                                   :score 11.2
                                   :matched_handles ("app:firefox"
                                                     "domain_kind:docs"))))))
           (bundle (dl-satan-context-motd spec prepare))
           (prompt (plist-get bundle :prompt))
           (idx-percept (string-match "^# Percept$" prompt))
           (idx-resonance (string-match "^# Resonance$" prompt))
           (idx-today (or (string-match "^# Today (raw)$" prompt)
                          most-positive-fixnum)))
      (should idx-percept)
      (should idx-resonance)
      (should (< idx-percept idx-resonance))
      (should (< idx-resonance idx-today))
      (should (string-match-p "^- 20260518T120000-aaa  score 11.2$" prompt))
      (should (string-match-p
               "^    matched: app:firefox, domain_kind:docs$" prompt)))))

(ert-deftest dl-satan-resonance/capsule-omits-resonance-on-gate-skip ()
  "Gate-skip status → no `# Resonance' header in the prompt."
  (dl-satan-resonance-test--with-framing tmp
    (let* ((spec (list :name "motd"
                       :prompt-file
                       (expand-file-name "prompts/motd.txt" tmp)))
           (prepare (list :run_id "rid-y"
                          :time_now "2026-05-19T10:00:00+10:00"
                          :resonance (list :status 'gate-skip
                                           :cue nil :matches nil)))
           (bundle (dl-satan-context-motd spec prepare))
           (prompt (plist-get bundle :prompt)))
      (should-not (string-match-p "^# Resonance$" prompt)))))

(ert-deftest dl-satan-resonance/capsule-omits-resonance-when-memory-unreachable ()
  "psql-down → no `# Resonance' header (handover watch-out)."
  (dl-satan-resonance-test--with-framing tmp
    (let* ((spec (list :name "motd"
                       :prompt-file
                       (expand-file-name "prompts/motd.txt" tmp)))
           (prepare (list :run_id "rid-z"
                          :time_now "2026-05-19T10:00:00+10:00"
                          :resonance (list :status 'memory-unreachable
                                           :cue '("app:firefox")
                                           :matches nil)))
           (bundle (dl-satan-context-motd spec prepare))
           (prompt (plist-get bundle :prompt)))
      (should-not (string-match-p "^# Resonance$" prompt)))))

(ert-deftest dl-satan-resonance/result-json-serializes-via-jsonl-prepare ()
  "Live failure repro: a resonance result with `:status 'ok' (symbol)
must survive `dl-satan-jsonl-prepare' → `json-serialize' so the audit
layer can write `bundle.json'.  Regression for the run that crashed
with `(wrong-type-argument json-value-p ok)' inside
`dl-satan-audit--write-json'."
  (require 'dl-satan-jsonl)
  (let* ((result (list :status 'ok
                       :cue '("app:firefox" "domain_kind:docs")
                       :matches nil)))
    (should (stringp (json-serialize (dl-satan-jsonl-prepare result)
                                     :null-object :null
                                     :false-object :false)))))

(provide 'dl-satan-resonance-test)
;;; dl-satan-resonance-test.el ends here
