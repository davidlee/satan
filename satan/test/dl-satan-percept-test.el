;;; dl-satan-percept-test.el --- percept skeleton ert -*- lexical-binding: t; -*-

;; Phase 1 of perceptual-design.md.  Covers:
;;
;;   A1   percept.json written next to bundle.json each run
;;   A2   bundle.json + percept.json share run_id + time_now
;;   A3   byte-identical re-runs on frozen sensor + frozen time_now
;;   A4   capsule contains a percept block (resonance / motive deferred)
;;   A6   no rendering of absent handles
;;
;; Sensor surface is quarantined the same way `dl-satan-memory-evidence-test'
;; does it: `:behaviour_dir' points at a tmp tree, `dl-satan-bough-program'
;; points at a non-existent path so bough calls return nil without
;; touching the user's real bough store.

(require 'ert)
(require 'cl-lib)
(require 'json)
(require 'dl-satan-percept)
(require 'dl-satan-memory-grammar)
(require 'dl-satan-audit)

(defmacro dl-satan-percept-test--with-fixture (vars &rest body)
  "Bind VARS plist `(:tmp :behaviour :run-dir)' to a fresh tmp tree.
BODY runs with `dl-satan-bough-program' shunted to /nonexistent/ so
bough probes return nil.  TMP cleaned up on exit."
  (declare (indent 1))
  (let ((tmp (plist-get vars :tmp))
        (behaviour (plist-get vars :behaviour))
        (run-dir (plist-get vars :run-dir)))
    `(let* ((,tmp (make-temp-file "satan-percept-test-" t))
            (,behaviour (file-name-as-directory
                         (expand-file-name "behaviour" ,tmp)))
            (,run-dir (file-name-as-directory
                       (expand-file-name "run" ,tmp))))
       (unwind-protect
           (let ((dl-satan-bough-program "/nonexistent/bough"))
             (make-directory ,behaviour t)
             (make-directory ,run-dir t)
             ,@body)
         (delete-directory ,tmp t)))))

(defun dl-satan-percept-test--write-sway (behaviour app)
  "Write a `current/sway.json' under BEHAVIOUR with APP as `app_id'."
  (let ((dir (expand-file-name "current" behaviour)))
    (make-directory dir t)
    (with-temp-file (expand-file-name "sway.json" dir)
      (insert (format "{\"app_id\":\"%s\",\"workspace\":\"main\"}" app)))))

(defun dl-satan-percept-test--prepare (run-id time-now)
  "Return a minimal prepare run_ctx plist for RUN-ID + TIME-NOW.
Mirrors `dl-satan-broker--prepare' shape so callers don't have to
import the broker just to fake a run."
  (list :run_id run-id
        :time_now time-now
        :start_time (current-time)
        :evidence nil :percept nil
        :sensor_status nil :pre_spawn nil :motive nil))

;; ---------------------------------------------------------------------
;; Build
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-percept/build-returns-shape ()
  "Build returns the documented plist shape with run_id + time_now
mirrored from PREPARE and the canon's emitted handles."
  (dl-satan-percept-test--with-fixture (:tmp tmp :behaviour beh :run-dir rd)
    (dl-satan-percept-test--write-sway beh "firefox")
    (let* ((prepare (dl-satan-percept-test--prepare
                     "20260519T100000-motd-aaaaaa"
                     "2026-05-19T10:00:00+10:00"))
           (mode '(:name "motd"))
           (percept (dl-satan-percept-build
                     prepare mode
                     (list :behaviour_dir beh :cwd tmp))))
      (should (equal (plist-get percept :run_id) (plist-get prepare :run_id)))
      (should (equal (plist-get percept :time_now)
                     (plist-get prepare :time_now)))
      (should (equal (plist-get percept :mode) "motd"))
      (should (= (plist-get percept :grammar_version)
                 dl-satan-memory-grammar-current-version))
      (should (member "app:firefox" (plist-get percept :handles)))
      (should (member "surface:browser" (plist-get percept :handles)))
      (should (member "mode:motd" (plist-get percept :handles)))
      ;; handle_sources mirrors handles ordering, one plist per handle.
      (let* ((handles (plist-get percept :handles))
             (sources (plist-get percept :handle_sources)))
        (should (= (length handles) (length sources)))
        (cl-loop for h in handles
                 for s in sources
                 do (should (equal (plist-get s :handle) h))
                 do (should (stringp (plist-get s :rule_id))))))))

(ert-deftest dl-satan-percept/build-handles-are-sorted ()
  "Canon already sorts; build must preserve it so json-encode output
is deterministic across runs (A3)."
  (dl-satan-percept-test--with-fixture (:tmp tmp :behaviour beh :run-dir rd)
    (dl-satan-percept-test--write-sway beh "emacs")
    (let* ((prepare (dl-satan-percept-test--prepare
                     "rid" "2026-05-19T10:00:00+10:00"))
           (percept (dl-satan-percept-build
                     prepare '(:name "motd")
                     (list :behaviour_dir beh :cwd tmp)))
           (handles (plist-get percept :handles)))
      (should (equal handles (sort (copy-sequence handles) #'string<))))))

(ert-deftest dl-satan-percept/build-empty-sources-yields-only-ctx-handles ()
  "With no panopticon / git / fs / hints, canon still emits ctx-derived
handles (mode, day, week).  A6 — these are present-because-emitted,
not absent-because-padded."
  (dl-satan-percept-test--with-fixture (:tmp tmp :behaviour beh :run-dir rd)
    (let* ((prepare (dl-satan-percept-test--prepare
                     "rid" "2026-05-19T10:00:00+10:00"))
           (percept (dl-satan-percept-build
                     prepare '(:name "motd")
                     (list :behaviour_dir beh :cwd "/nonexistent/dir/")))
           (handles (plist-get percept :handles)))
      (should (member "mode:motd" handles))
      (should (member "day:2026-05-19" handles))
      (should (member "week:2026-W21" handles))
      ;; A6: no absence rendering.  Canon never emits `surface:unknown'
      ;; or `app:none' — this just guards against accidental rule changes.
      (should-not (cl-some (lambda (h)
                             (string-match-p ":\\(none\\|unknown\\)\\'" h))
                           handles)))))

;; ---------------------------------------------------------------------
;; Persist (A1)
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-percept/persist-writes-percept-json ()
  "A1 — `percept.json' lands under the run dir; JSON parseable; carries
the same run_id + time_now as the source plist."
  (dl-satan-percept-test--with-fixture (:tmp tmp :behaviour beh :run-dir rd)
    (dl-satan-percept-test--write-sway beh "firefox")
    (let* ((prepare (dl-satan-percept-test--prepare
                     "20260519T100000-motd-ffeeaa"
                     "2026-05-19T10:00:00+10:00"))
           (percept (dl-satan-percept-build
                     prepare '(:name "motd")
                     (list :behaviour_dir beh :cwd rd)))
           (path (dl-satan-percept-persist rd percept))
           (got (with-temp-buffer
                  (insert-file-contents path)
                  (goto-char (point-min))
                  (json-parse-buffer :object-type 'plist
                                     :array-type 'list
                                     :null-object :null
                                     :false-object :false))))
      (should (equal (file-name-nondirectory path) "percept.json"))
      (should (equal (plist-get got :run_id) (plist-get prepare :run_id)))
      (should (equal (plist-get got :time_now)
                     (plist-get prepare :time_now)))
      (should (member "app:firefox" (plist-get got :handles))))))

;; ---------------------------------------------------------------------
;; Determinism (A3)
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-percept/byte-identical-rerun-on-frozen-inputs ()
  "A3 — two builds over the same frozen sensor fixture + frozen
time_now produce byte-identical `percept.json' encodings.

The percept persist path uses `dl-satan-audit--write-json' which
canonicalizes via `dl-satan-jsonl-prepare' before serializing, so
re-emitted JSON is comparable byte-for-byte."
  (dl-satan-percept-test--with-fixture (:tmp tmp :behaviour beh :run-dir rd)
    (dl-satan-percept-test--write-sway beh "firefox")
    (let* ((prepare (dl-satan-percept-test--prepare
                     "20260519T100000-motd-ffeeaa"
                     "2026-05-19T10:00:00+10:00"))
           (opts (list :behaviour_dir beh :cwd rd))
           (one (dl-satan-percept-build prepare '(:name "motd") opts))
           (two (dl-satan-percept-build prepare '(:name "motd") opts))
           (path-one (expand-file-name "one.json" rd))
           (path-two (expand-file-name "two.json" rd)))
      (dl-satan-audit--write-json path-one one)
      (dl-satan-audit--write-json path-two two)
      (let ((bytes-one (with-temp-buffer
                         (set-buffer-multibyte nil)
                         (insert-file-contents-literally path-one)
                         (buffer-string)))
            (bytes-two (with-temp-buffer
                         (set-buffer-multibyte nil)
                         (insert-file-contents-literally path-two)
                         (buffer-string))))
        (should (equal bytes-one bytes-two))))))

;; ---------------------------------------------------------------------
;; Render block (A4 / A6)
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-percept/render-block-uses-framing-header ()
  "A4 — capsule shows a percept block; A6 — block lines mirror the
canon's emitted handles (no absence padding)."
  (let* ((framing '(("percept_block_header" . "# Percept")))
         (percept '(:handles ("app:firefox" "surface:browser")))
         (lines (dl-satan-percept-render-block framing percept)))
    (should (equal (car lines) "# Percept"))
    (should (equal (cdr lines) '("- app:firefox" "- surface:browser")))))

(ert-deftest dl-satan-percept/render-block-empty-handles-yields-nil ()
  "A6 — empty handle list returns nil so the capsule omits the block
entirely (rather than emitting an empty `# Percept' header)."
  (let* ((framing '(("percept_block_header" . "# Percept")))
         (percept '(:handles ())))
    (should (null (dl-satan-percept-render-block framing percept)))))

(ert-deftest dl-satan-percept/render-block-without-framing-key-yields-nil ()
  "Mind owns the header text; absent key in framing.txt means the
section is suppressed.  This guards against silent fallback to a
hardcoded header in elisp."
  (let* ((framing '(("now" . "# Now")))
         (percept '(:handles ("app:firefox"))))
    (should (null (dl-satan-percept-render-block framing percept)))))

;; ---------------------------------------------------------------------
;; Attention block — raw focus + browser sight in the capsule.
;; Distinct from the handle block: this renders evidence_window segments
;; verbatim (url + title), bypassing canon's closed-world buckets, so
;; the live agent sees what tab/app it was actually on.
;; ---------------------------------------------------------------------

(defconst dl-satan-percept-test--attention-framing
  '(("attention_block_header" . "# Recent attention")))

(ert-deftest dl-satan-percept/attention-block-interleaves-focus-and-browser ()
  "Focus + browser segments render interleaved by start_ts (ascending);
browser lines carry url + title, focus lines carry app + workspace."
  (let* ((percept
          (list :evidence_window
                (list :focus_segments
                      (list (list :app_id "Alacritty" :workspace "01"
                                  :last_title "satan-git-visibility-issue"
                                  :start_ts "2026-05-30T09:55:00+10:00"
                                  :duration_s 180))
                      :browser_segments
                      (list (list :source "firefox"
                                  :url "https://docs.python.org/3/library/json.html"
                                  :domain "docs.python.org"
                                  :title_end "json — JSON encoder and decoder"
                                  :start_ts "2026-05-30T09:58:00+10:00"
                                  :duration_s 65)))))
         (lines (dl-satan-percept-render-attention-block
                 dl-satan-percept-test--attention-framing percept)))
    (should (equal (car lines) "# Recent attention"))
    (should (equal (nth 1 lines)
                   "- 3m  Alacritty  ws01  \"satan-git-visibility-issue\""))
    (should (equal (nth 2 lines)
                   (concat "- 1m  firefox  "
                           "https://docs.python.org/3/library/json.html"
                           "  \"json — JSON encoder and decoder\"")))))

(ert-deftest dl-satan-percept/attention-block-drops-browser-app-focus ()
  "A focus segment for a browser app is suppressed — the browser tab
segments cover that span at finer (per-URL) grain."
  (let* ((percept
          (list :evidence_window
                (list :focus_segments
                      (list (list :app_id "firefox" :workspace "02"
                                  :last_title "should not appear"
                                  :start_ts "2026-05-30T10:00:00+10:00"
                                  :duration_s 120))
                      :browser_segments nil)))
         (lines (dl-satan-percept-render-attention-block
                 dl-satan-percept-test--attention-framing percept)))
    (should (null lines))))

(ert-deftest dl-satan-percept/attention-block-without-framing-key-yields-nil ()
  "Mind owns the header; an absent key suppresses the block (no fallback)."
  (let ((percept (list :evidence_window
                       (list :focus_segments
                             (list (list :app_id "Emacs" :start_ts "x"
                                         :duration_s 10))))))
    (should (null (dl-satan-percept-render-attention-block
                   '(("now" . "# Now")) percept)))))

(ert-deftest dl-satan-percept/attention-block-caps-at-limit ()
  "Only the most-recent `dl-satan-percept-attention-limit' segments render."
  (let* ((dl-satan-percept-attention-limit 2)
         (mk (lambda (n)
               (list :app_id "Emacs"
                     :last_title (format "f%d" n)
                     :start_ts (format "2026-05-30T10:0%d:00+10:00" n)
                     :duration_s 10)))
         (percept (list :evidence_window
                        (list :focus_segments
                              (list (funcall mk 1) (funcall mk 2) (funcall mk 3)))))
         (lines (dl-satan-percept-render-attention-block
                 dl-satan-percept-test--attention-framing percept)))
    (should (= (length lines) 3))
    (should (equal (nth 1 lines) "- 10s  Emacs  \"f2\""))
    (should (equal (nth 2 lines) "- 10s  Emacs  \"f3\""))))

(ert-deftest dl-satan-percept/attention-block-drops-subsecond-segments ()
  "Sub-second focus + browser segments are capture noise; filtered out."
  (let* ((percept
          (list :evidence_window
                (list :focus_segments
                      (list (list :app_id "Emacs" :last_title "blip"
                                  :start_ts "2026-05-30T10:00:00+10:00"
                                  :duration_s 0.4)
                            (list :app_id "Emacs" :last_title "real"
                                  :start_ts "2026-05-30T10:01:00+10:00"
                                  :duration_s 30))
                      :browser_segments
                      (list (list :source "firefox" :url "https://x.test/"
                                  :title_end "flash"
                                  :start_ts "2026-05-30T10:00:30+10:00"
                                  :duration_s 0)))))
         (lines (dl-satan-percept-render-attention-block
                 dl-satan-percept-test--attention-framing percept)))
    (should (equal lines (list "# Recent attention" "- 30s  Emacs  \"real\"")))))

;; ---------------------------------------------------------------------
;; Determinism rig (A3) — richer fixture, drives focus + browser + ctx
;; ---------------------------------------------------------------------

(defun dl-satan-percept-test--seed-fixture (behaviour day)
  "Write a frozen panopticon fixture under BEHAVIOUR keyed by DAY (YYYY-MM-DD).
A repeated build over the same fixture is the bone of acceptance A3.
Includes current/sway + focus segments + browser segments — same
shape `dl-satan-memory-evidence' uses in its own assemble tests, so
this rig stays parallel."
  (let ((current-dir (expand-file-name "current" behaviour))
        (segments-dir (expand-file-name "segments" behaviour)))
    (make-directory current-dir t)
    (make-directory segments-dir t)
    (with-temp-file (expand-file-name "sway.json" current-dir)
      (insert "{\"app_id\":\"firefox\",\"workspace\":\"main\"}"))
    (with-temp-file (expand-file-name (format "focus-%s.jsonl" day)
                                      segments-dir)
      (insert "{\"app_id\":\"Alacritty\",\"start_ts\":\"2026-05-19T09:55:00+10:00\",\"end_ts\":\"2026-05-19T09:58:00+10:00\",\"duration_s\":180}\n")
      (insert "{\"app_id\":\"firefox\",\"start_ts\":\"2026-05-19T09:58:00+10:00\",\"end_ts\":\"2026-05-19T10:00:00+10:00\",\"duration_s\":120}\n"))
    (with-temp-file (expand-file-name (format "browser-%s.jsonl" day)
                                      segments-dir)
      (insert "{\"domain\":\"docs.python.org\",\"start_ts\":\"2026-05-19T09:58:30+10:00\",\"end_ts\":\"2026-05-19T09:59:30+10:00\"}\n"))))

(ert-deftest dl-satan-percept/determinism-on-rich-fixture ()
  "A3 — two builds over a frozen focus + browser + current fixture
produce byte-identical persisted JSON.  Beyond the minimal sway-only
case: ensures focus/browser readers don't smuggle in timestamps or
random ordering."
  (dl-satan-percept-test--with-fixture (:tmp tmp :behaviour beh :run-dir rd)
    (ignore tmp)
    (dl-satan-percept-test--seed-fixture beh "2026-05-19")
    (let* ((prepare (dl-satan-percept-test--prepare
                     "20260519T100000-motd-deadbe"
                     "2026-05-19T10:00:00+10:00"))
           (opts (list :behaviour_dir beh :cwd rd))
           (path-a (expand-file-name "a/percept.json" rd))
           (path-b (expand-file-name "b/percept.json" rd)))
      (make-directory (file-name-directory path-a) t)
      (make-directory (file-name-directory path-b) t)
      (dl-satan-percept-persist
       (file-name-directory path-a)
       (dl-satan-percept-build prepare '(:name "motd") opts))
      (dl-satan-percept-persist
       (file-name-directory path-b)
       (dl-satan-percept-build prepare '(:name "motd") opts))
      (let ((bytes-a (with-temp-buffer
                       (set-buffer-multibyte nil)
                       (insert-file-contents-literally path-a)
                       (buffer-string)))
            (bytes-b (with-temp-buffer
                       (set-buffer-multibyte nil)
                       (insert-file-contents-literally path-b)
                       (buffer-string))))
        (should (equal bytes-a bytes-b))
        ;; Surface_transition + domain_kind must show up on the rich
        ;; fixture — the determinism check is hollow if the build
        ;; produced an empty handle list.
        (let ((handles (plist-get
                        (json-parse-string bytes-a
                                           :object-type 'plist
                                           :array-type 'list
                                           :null-object :null
                                           :false-object :false)
                        :handles)))
          (should (member "surface_transition:terminal->browser" handles))
          (should (member "domain_kind:docs" handles)))))))

;; ---------------------------------------------------------------------
;; A2 identity — bundle.json + percept.json carry the same run_id + time_now
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-percept/bundle-and-percept-share-identity ()
  "A2 — writes both bundle.json (via a context-fn round-trip and
`dl-satan-audit--write-json') and percept.json from the same prepare
plist; asserts run_id + time_now match byte-for-byte across artifacts.

This drives the same prepare allocator the broker uses, so any future
drift between bundle and percept identity surfaces here before it
ships."
  (dl-satan-percept-test--with-fixture (:tmp tmp :behaviour beh :run-dir rd)
    (dl-satan-percept-test--write-sway beh "firefox")
    (let* ((dl-satan-system-scaffold-file
            (expand-file-name "system/scaffold.txt" tmp))
           (dl-satan-system-framing-file
            (expand-file-name "system/framing.txt" tmp)))
      (make-directory (expand-file-name "prompts" tmp))
      (make-directory (expand-file-name "system" tmp))
      (with-temp-file dl-satan-system-scaffold-file (insert "SCAFFOLD"))
      (with-temp-file dl-satan-system-framing-file
        (insert "now=# Now\n"
                "today=# Today (raw)\n"
                "sources=# Source files\n"
                "percept_block_header=# Percept\n"))
      (with-temp-file (expand-file-name "prompts/motd.txt" tmp)
        (insert "PROMPT"))
      (let* ((mode (list :name "motd"
                         :prompt-file
                         (expand-file-name "prompts/motd.txt" tmp)))
             (prepare (dl-satan-percept-test--prepare
                       "20260519T100000-motd-cafef0"
                       "2026-05-19T10:00:00+10:00"))
             (percept (dl-satan-percept-build
                       prepare mode
                       (list :behaviour_dir beh :cwd rd)))
             (prepare-with-percept
              (plist-put (plist-put prepare :evidence
                                    (plist-get percept :evidence_window))
                         :percept percept))
             (bundle (dl-satan-context-motd mode prepare-with-percept))
             (bundle-path (expand-file-name "bundle.json" rd))
             (percept-path (dl-satan-percept-persist rd percept)))
        (dl-satan-audit--write-json bundle-path bundle)
        (let ((bundle-on-disk
               (with-temp-buffer
                 (insert-file-contents bundle-path)
                 (goto-char (point-min))
                 (json-parse-buffer :object-type 'plist
                                    :array-type 'list
                                    :null-object :null
                                    :false-object :false)))
              (percept-on-disk
               (with-temp-buffer
                 (insert-file-contents percept-path)
                 (goto-char (point-min))
                 (json-parse-buffer :object-type 'plist
                                    :array-type 'list
                                    :null-object :null
                                    :false-object :false))))
          (should (equal (plist-get bundle-on-disk :run_id)
                         (plist-get percept-on-disk :run_id)))
          (should (equal (plist-get bundle-on-disk :time_now)
                         (plist-get percept-on-disk :time_now)))
          (should (equal (plist-get bundle-on-disk :run_id)
                         (plist-get prepare :run_id)))
          (should (equal (plist-get bundle-on-disk :time_now)
                         (plist-get prepare :time_now))))))))

;; ---------------------------------------------------------------------
;; Capsule render through dl-satan-context (1.3)
;; ---------------------------------------------------------------------

(require 'dl-satan-context)

(ert-deftest dl-satan-percept/capsule-renders-percept-block-from-prepare ()
  "A4 — when PREPARE carries a `:percept' with handles, the rendered
prompt includes a `# Percept' header followed by handle lines.
The header text is supplied by framing.txt, not hardcoded."
  (let* ((tmp (make-temp-file "satan-percept-cap-" t))
         (dl-satan-system-scaffold-file
          (expand-file-name "system/scaffold.txt" tmp))
         (dl-satan-system-framing-file
          (expand-file-name "system/framing.txt" tmp)))
    (unwind-protect
        (progn
          (make-directory (expand-file-name "prompts" tmp))
          (make-directory (expand-file-name "system" tmp))
          (with-temp-file dl-satan-system-scaffold-file (insert "SCAFFOLD"))
          (with-temp-file dl-satan-system-framing-file
            (insert "now=# Now\n"
                    "today=# Today (raw)\n"
                    "sources=# Source files\n"
                    "percept_block_header=# Percept\n"))
          (with-temp-file (expand-file-name "prompts/motd.txt" tmp)
            (insert "PROMPT"))
          (let* ((spec (list :name "motd"
                             :prompt-file
                             (expand-file-name "prompts/motd.txt" tmp)))
                 (prepare (list :run_id "rid-x"
                                :time_now "2026-05-19T10:00:00+10:00"
                                :percept '(:handles ("app:firefox"
                                                     "surface:browser"))))
                 (bundle (dl-satan-context-motd spec prepare))
                 (prompt (plist-get bundle :prompt)))
            (should (string-match-p "^# Percept$" prompt))
            (should (string-match-p "^- app:firefox$" prompt))
            (should (string-match-p "^- surface:browser$" prompt))
            (should (equal (plist-get bundle :run_id) "rid-x"))
            (should (equal (plist-get bundle :time_now)
                           "2026-05-19T10:00:00+10:00"))))
      (delete-directory tmp t))))

(ert-deftest dl-satan-percept/capsule-omits-percept-block-when-no-prepare ()
  "Without a PREPARE plist (legacy callers, or budget-denied paths),
the capsule renders cleanly with no `# Percept' artefact."
  (let* ((tmp (make-temp-file "satan-percept-cap-empty-" t))
         (dl-satan-system-scaffold-file
          (expand-file-name "system/scaffold.txt" tmp))
         (dl-satan-system-framing-file
          (expand-file-name "system/framing.txt" tmp)))
    (unwind-protect
        (progn
          (make-directory (expand-file-name "prompts" tmp))
          (make-directory (expand-file-name "system" tmp))
          (with-temp-file dl-satan-system-scaffold-file (insert "SCAFFOLD"))
          (with-temp-file dl-satan-system-framing-file
            (insert "now=# Now\n"
                    "today=# Today (raw)\n"
                    "sources=# Source files\n"
                    "percept_block_header=# Percept\n"))
          (with-temp-file (expand-file-name "prompts/motd.txt" tmp)
            (insert "PROMPT"))
          (let* ((spec (list :name "motd"
                             :prompt-file
                             (expand-file-name "prompts/motd.txt" tmp)))
                 (bundle (dl-satan-context-motd spec nil))
                 (prompt (plist-get bundle :prompt)))
            (should-not (string-match-p "^# Percept$" prompt))))
      (delete-directory tmp t))))

(provide 'dl-satan-percept-test)
;;; dl-satan-percept-test.el ends here
