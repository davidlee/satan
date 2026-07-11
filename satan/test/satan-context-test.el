;;; satan-context-test.el --- ert tests for satan-context recent-runs -*- lexical-binding: t; -*-

;; Run from CLI:
;;   emacs --batch \
;;     -L ~/.emacs.d/core -L ~/.emacs.d/lisp -L ~/.emacs.d/org \
;;     -L ~/.emacs.d/satan -L ~/.emacs.d/satan/test \
;;     -l satan-context-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'subr-x)                        ; thread-first (byte-stable VT)
(require 'satan-broker)               ; defines `satan-runs-dir' defcustom
(require 'satan-context)
(require 'satan-mode)                 ; self-edit-mech / self-edit-mind specs
(require 'satan-output)                ; self-edit output handler

(defun satan-context-test--corpus-p (&rest files)
  "Non-nil when every model-facing FILE is readable.
The `~/notes/satan/' corpus is host-only (SL-012 D4/POL, not shipped in
the package); corpus-integration tests `skip-unless' it is present, so
the suite is green in CI/sandbox without it and exercised on the host."
  (cl-every #'file-readable-p files))

(defun satan-context-test--mkrun (root run-id &optional final-summary tools failed)
  "Create a fake run directory under ROOT for RUN-ID.
TOOLS is an alist (NAME . COUNT) of tool-call lines to fabricate.
When FAILED is non-nil the directory name carries the `.FAILED' suffix."
  (let* ((bucket (concat (substring run-id 0 4) "-"
                         (substring run-id 4 6) "-"
                         (substring run-id 6 8)))
         (leaf (if failed (concat run-id ".FAILED") run-id))
         (dir (expand-file-name (concat bucket "/" leaf) root)))
    (make-directory dir t)
    ;; final.json — successful runs include a summary; failed runs may not.
    (when final-summary
      (with-temp-file (expand-file-name "final.json" dir)
        (insert (json-serialize
                 (list :type "final" :summary final-summary :actions (make-hash-table))))))
    ;; transcript.jsonl — one line per tool call (plus a non-tool line for noise).
    (with-temp-file (expand-file-name "transcript.jsonl" dir)
      (insert (json-serialize
               (list :ts "2026-05-21T00:00:00+1000"
                     :dir "in" :event "ready"
                     :payload (list :type "ready" :run_id run-id))))
      (insert "\n")
      (dolist (entry tools)
        (let ((name (car entry))
              (count (cdr entry)))
          (dotimes (_ count)
            (insert (json-serialize
                     (list :ts "2026-05-21T00:00:01+1000"
                           :dir "in" :event "tool-call"
                           :payload (list :type "tool_call"
                                          :id "call_x"
                                          :name name
                                          :args (make-hash-table)))))
            (insert "\n")))))
    dir))

(defmacro satan-context-test--with-runs-root (var &rest body)
  "Bind VAR to a fresh temp runs root, evaluate BODY, then delete the tree."
  (declare (indent 1))
  `(let ((,var (make-temp-file "satan-context-test-runs-" t)))
     (unwind-protect (progn ,@body)
       (delete-directory ,var t))))

;; ---------- --list-recent-runs ----------

(ert-deftest satan-context/list-recent-runs/returns-newest-first ()
  (satan-context-test--with-runs-root root
    (satan-context-test--mkrun root "20260520T100000-tick-pulse-aaaaaa" "old")
    (satan-context-test--mkrun root "20260521T080000-morning-bbbbbb" "mid")
    (satan-context-test--mkrun root "20260521T130000-tick-pulse-cccccc" "new")
    (let ((satan-runs-dir root))
      (let ((dirs (satan-context--list-recent-runs 3)))
        (should (equal (length dirs) 3))
        (should (string-match-p "tick-pulse-cccccc" (nth 0 dirs)))
        (should (string-match-p "morning-bbbbbb" (nth 1 dirs)))
        (should (string-match-p "tick-pulse-aaaaaa" (nth 2 dirs)))))))

(ert-deftest satan-context/list-recent-runs/honours-n ()
  (satan-context-test--with-runs-root root
    (dotimes (i 6)
      (satan-context-test--mkrun
       root
       (format "20260521T%02d0000-tick-pulse-%06d" (1+ i) i)
       (format "run %d" i)))
    (let ((satan-runs-dir root))
      (should (equal (length (satan-context--list-recent-runs 3)) 3))
      (should (equal (length (satan-context--list-recent-runs 100)) 6)))))

(ert-deftest satan-context/list-recent-runs/empty-or-missing-yields-nil ()
  (let ((satan-runs-dir "/nonexistent/path/that/should/not/exist"))
    (should (null (satan-context--list-recent-runs 5))))
  (satan-context-test--with-runs-root root
    (let ((satan-runs-dir root))
      (should (null (satan-context--list-recent-runs 5))))))

(ert-deftest satan-context/list-recent-runs/skips-non-bucket-entries ()
  "`most-recent' symlinks and stray files at the runs root must be ignored."
  (satan-context-test--with-runs-root root
    (satan-context-test--mkrun root "20260521T100000-tick-pulse-aaaaaa" "ok")
    (write-region "" nil (expand-file-name "stray.txt" root))
    (make-symbolic-link "2026-05-21/20260521T100000-tick-pulse-aaaaaa"
                        (expand-file-name "most-recent" root) t)
    (let ((satan-runs-dir root))
      (let ((dirs (satan-context--list-recent-runs 5)))
        (should (equal (length dirs) 1))
        (should (string-match-p "tick-pulse-aaaaaa" (car dirs)))))))

;; ---------- --summarize-run ----------

(ert-deftest satan-context/summarize-run/extracts-time-mode-summary-tools ()
  (satan-context-test--with-runs-root root
    (let* ((dir (satan-context-test--mkrun
                 root "20260521T125543-tick-pulse-80e9e6"
                 "User in Slack. Nothing to mark."
                 '(("activity_read" . 1) ("memory_resonate" . 2)))))
      (let ((entry (satan-context--summarize-run dir)))
        (should (equal (plist-get entry :when) "2026-05-21 12:55"))
        (should (equal (plist-get entry :mode) "tick-pulse"))
        (should (equal (plist-get entry :status) "ok"))
        (should (equal (plist-get entry :summary) "User in Slack. Nothing to mark."))
        (should (equal (plist-get entry :tools)
                       '(("activity_read" . 1) ("memory_resonate" . 2))))))))

(ert-deftest satan-context/summarize-run/handles-failed-with-no-final ()
  (satan-context-test--with-runs-root root
    (let* ((dir (satan-context-test--mkrun
                 root "20260521T090000-morning-cccccc"
                 nil nil t)))
      (let ((entry (satan-context--summarize-run dir)))
        (should (equal (plist-get entry :status) "FAILED"))
        (should (equal (plist-get entry :mode) "morning"))
        (should (null (plist-get entry :summary)))))))

(ert-deftest satan-context/summarize-run/excludes-satan-final-from-tools ()
  (satan-context-test--with-runs-root root
    (let* ((dir (satan-context-test--mkrun
                 root "20260521T100000-tick-pulse-aaaaaa"
                 "summary"
                 '(("activity_read" . 1) ("satan_final" . 1)))))
      (let ((entry (satan-context--summarize-run dir)))
        (should (equal (plist-get entry :tools)
                       '(("activity_read" . 1))))))))

(ert-deftest satan-context/summarize-run/clips-long-summary ()
  (satan-context-test--with-runs-root root
    (let* ((long (make-string 600 ?x))
           (dir (satan-context-test--mkrun
                 root "20260521T100000-tick-pulse-aaaaaa" long)))
      (let* ((entry (satan-context--summarize-run dir))
             (s (plist-get entry :summary)))
        (should (<= (length s) 280))
        (should (string-suffix-p "…" s))))))

;; ---------- --render-recent-runs ----------

(ert-deftest satan-context/render-recent-runs/nil-when-no-entries ()
  (let ((framing '(("recent_runs" . "# Recent SATAN runs"))))
    (should (null (satan-context--render-recent-runs framing nil)))))

(ert-deftest satan-context/render-recent-runs/renders-block ()
  (let* ((framing '(("recent_runs" . "# Recent SATAN runs")))
         (entries (list
                   (list :when "2026-05-21 12:55" :mode "tick-pulse"
                         :status "ok" :summary "User in Slack."
                         :tools '(("activity_read" . 1)))
                   (list :when "2026-05-21 09:00" :mode "morning"
                         :status "FAILED" :summary nil :tools nil)))
         (lines (satan-context--render-recent-runs framing entries))
         (text  (mapconcat #'identity lines "\n")))
    (should (equal (car lines) "# Recent SATAN runs"))
    (should (string-match-p "\\[2026-05-21 12:55\\] tick-pulse: User in Slack\\." text))
    (should (string-match-p "tools: activity_read×1" text))
    (should (string-match-p "\\[2026-05-21 09:00\\] morning (FAILED)" text))))

;; ---------- End-to-end via context-fn ----------

(ert-deftest satan-context/tick-emits-block-when-recent-runs-set ()
  (skip-unless (satan-context-test--corpus-p
                satan-system-scaffold-file satan-system-framing-file
                (expand-file-name "tick/pulse.txt"
                                  (expand-file-name "satan/prompts" satan-notes-root))))
  (satan-context-test--with-runs-root root
    (satan-context-test--mkrun
     root "20260521T125543-tick-pulse-80e9e6"
     "Earlier tick observation."
     '(("activity_read" . 1)))
    (let* ((satan-runs-dir root)
           ;; The mode-prompt and scaffold come from disk; let the context
           ;; function fail loudly if framing.txt lacks the recent_runs key
           ;; so the test catches that drift.
           (spec (list :name "tick-pulse"
                       :recent-runs 5
                       :prompt-file (or (locate-file "tick/pulse.txt"
                                                    (list (expand-file-name
                                                           "satan/prompts"
                                                           satan-notes-root)))
                                        (error "tick/pulse.txt prompt missing from notes"))))
           (bundle (satan-context-tick spec))
           (prompt (plist-get bundle :prompt)))
      (should (string-match-p "# Recent SATAN runs" prompt))
      (should (string-match-p "tick-pulse: Earlier tick observation\\." prompt)))))

(ert-deftest satan-context/tick-omits-block-when-recent-runs-unset ()
  (skip-unless (satan-context-test--corpus-p
                satan-system-scaffold-file satan-system-framing-file
                (expand-file-name "tick/pulse.txt"
                                  (expand-file-name "satan/prompts" satan-notes-root))))
  (satan-context-test--with-runs-root root
    (satan-context-test--mkrun
     root "20260521T125543-tick-pulse-80e9e6"
     "Earlier tick observation."
     '(("activity_read" . 1)))
    (let* ((satan-runs-dir root)
           (spec (list :name "tick-pulse"
                       :prompt-file (or (locate-file "tick/pulse.txt"
                                                    (list (expand-file-name
                                                           "satan/prompts"
                                                           satan-notes-root)))
                                        (error "tick/pulse.txt prompt missing from notes"))))
           (bundle (satan-context-tick spec))
           (prompt (plist-get bundle :prompt)))
      (should-not (string-match-p "# Recent SATAN runs" prompt)))))

;; ---------------------------------------------------------------------
;; Tick budget — enrich.resonance is optional (Phase 5)
;; ---------------------------------------------------------------------

(ert-deftest satan-context/enrich-resonance-budget-skip-and-passthrough ()
  "Phase 5 — `satan-run-enrich' sheds the OPTIONAL resonance stage
under an exhausted tick budget, substituting the honest
`budget-skipped' fallback the renderer self-suppresses.  Both the
no-accumulator and the bound-but-unbudgeted paths run the real
derive (`gate-skip' here), proving the passthrough is intact."
  (cl-letf (((symbol-function 'satan-motive-read)
             (lambda (&rest _) '(:motive nil))))
    ;; percept with no handles/sources → real derive yields `gate-skip'
    (let ((prepare (list :percept (list :handles nil :handle_sources nil))))
      ;; (a) exhausted budget → optional stage skips → honest fallback
      (let* ((satan-trace--current
              (list :t0 (- (float-time) 100) :budget-ms 1
                    :stages nil :skipped nil))
             (res (plist-get (satan-run-enrich (copy-sequence prepare))
                             :resonance)))
        (should (eq (plist-get res :status) 'budget-skipped))
        (should (null (plist-get res :cue)))
        (should (null (plist-get res :matches)))
        (should (member "enrich.resonance"
                        (plist-get satan-trace--current :skipped)))
        ;; renderer self-suppresses: nil block, no signal
        (should (null (satan-resonance-render-block
                       '(("resonance_block_header" . "# Resonance")) res))))
      ;; (b) no accumulator bound → real derive runs (passthrough)
      (let* ((satan-trace--current nil)
             (res (plist-get (satan-run-enrich (copy-sequence prepare))
                             :resonance)))
        (should (eq (plist-get res :status) 'gate-skip)))
      ;; (c) bound but unbudgeted (:budget-ms nil) → real derive runs
      (let* ((satan-trace--current
              (list :t0 (float-time) :budget-ms nil :stages nil :skipped nil))
             (res (plist-get (satan-run-enrich (copy-sequence prepare))
                             :resonance)))
        (should (eq (plist-get res :status) 'gate-skip))))))

;; ---------------------------------------------------------------------
;; Self-edit context-fn (relocated from satan-test.el monolith)
;; ---------------------------------------------------------------------

(defun satan-context-test--path-suffix-p (suffix sources)
  (cl-some (lambda (s) (string-suffix-p suffix (plist-get s :path)))
           sources))

(defun satan-context-test--write-framing (path)
  "Write the canonical framing keys to PATH for context-fn tests.
Context-fns under test render bundle sections via this file."
  (with-temp-file path
    (insert "now=# Now\n"
            "today=# Today (raw)\n"
            "sources=# Source files\n")))

(ert-deftest satan-self-edit/context-bundles-sources ()
  "context-fn assembles scaffold + mode prompt and includes matching sources
from every root in MODE-SPEC's :source-roots."
  (let* ((tmp (make-temp-file "satan-se-" t))
         (root-a (expand-file-name "root-a" tmp))
         (root-b (expand-file-name "root-b" tmp))
         (satan-prompts-dir (expand-file-name "prompts/" tmp))
         (satan-system-scaffold-file
          (expand-file-name "system/scaffold.txt" tmp))
         (satan-system-framing-file
          (expand-file-name "system/framing.txt" tmp)))
    (unwind-protect
        (progn
          (make-directory root-a t)
          (make-directory root-b t)
          (make-directory (expand-file-name "prompts" tmp))
          (make-directory (expand-file-name "system" tmp))
          (with-temp-file satan-system-scaffold-file (insert "SCAFFOLD\n"))
          (satan-context-test--write-framing satan-system-framing-file)
          (with-temp-file (expand-file-name "prompts/se.txt" tmp)
            (insert "PROMPT\n"))
          (with-temp-file (expand-file-name "a.el" root-a) (insert "(provide 'a)"))
          (with-temp-file (expand-file-name "b.py" root-b) (insert "x = 1"))
          (with-temp-file (expand-file-name "a.elc" root-a) (insert "skip"))
          (let* ((spec (list :name "self-edit-mech"
                             :prompt-file (expand-file-name "prompts/se.txt" tmp)
                             :source-roots (list root-a root-b)))
                 (bundle (satan-context-self-edit spec))
                 (prompt (plist-get bundle :prompt))
                 (sources (plist-get bundle :sources)))
            (should (string-prefix-p "SCAFFOLD\n\nPROMPT" prompt))
            (should (string-match-p "^# Now$" prompt))
            (should (string-match-p "^# Source files$" prompt))
            (should (satan-context-test--path-suffix-p "/a.el" sources))
            (should (satan-context-test--path-suffix-p "/b.py" sources))
            (should-not (satan-context-test--path-suffix-p "/a.elc" sources))
            (let ((a (cl-find "/a.el" sources
                              :key (lambda (s) (plist-get s :path))
                              :test (lambda (suf p) (string-suffix-p suf p)))))
              (should (equal (plist-get a :content) "(provide 'a)")))))
      (delete-directory tmp t))))

(ert-deftest satan-self-edit/bundle-budget-drops-overflow ()
  "When sources exceed `satan-self-edit-bundle-char-budget' the
bundle keeps as much as fits in alphabetical order and reports the
rest under :dropped-files."
  (let* ((tmp (make-temp-file "satan-se-budget-" t))
         (root (expand-file-name "r" tmp))
         (satan-prompts-dir (expand-file-name "prompts/" tmp))
         (satan-system-scaffold-file
          (expand-file-name "system/scaffold.txt" tmp))
         (satan-system-framing-file
          (expand-file-name "system/framing.txt" tmp))
         (satan-self-edit-bundle-char-budget 100))
    (unwind-protect
        (progn
          (make-directory root t)
          (make-directory (expand-file-name "prompts" tmp))
          (make-directory (expand-file-name "system" tmp))
          (with-temp-file satan-system-scaffold-file (insert "S"))
          (satan-context-test--write-framing satan-system-framing-file)
          (with-temp-file (expand-file-name "prompts/se.txt" tmp) (insert "P"))
          ;; Three 60-char files, alphabetical: a, b, c.  Budget = 100.
          ;; a (60) packed.  a+b (120) would overflow → b dropped.
          ;; a+c (120) likewise → c dropped.  Only a fits.
          (with-temp-file (expand-file-name "a.el" root) (insert (make-string 60 ?a)))
          (with-temp-file (expand-file-name "b.el" root) (insert (make-string 60 ?b)))
          (with-temp-file (expand-file-name "c.el" root) (insert (make-string 60 ?c)))
          (let* ((spec (list :name "self-edit-mech"
                             :prompt-file (expand-file-name "prompts/se.txt" tmp)
                             :source-roots (list root)))
                 (bundle (satan-context-self-edit spec))
                 (sources (plist-get bundle :sources))
                 (dropped (plist-get bundle :dropped-files)))
            (should (= 1 (length sources)))
            (should (satan-context-test--path-suffix-p "/a.el" sources))
            (should (= 2 (length dropped)))
            (should (cl-some (lambda (p) (string-suffix-p "/b.el" p)) dropped))
            (should (cl-some (lambda (p) (string-suffix-p "/c.el" p)) dropped))))
      (delete-directory tmp t))))

(ert-deftest satan-self-edit/bundle-budget-nil-packs-everything ()
  "With the budget set to nil every file is included; :dropped-files is empty."
  (let* ((tmp (make-temp-file "satan-se-nobudget-" t))
         (root (expand-file-name "r" tmp))
         (satan-prompts-dir (expand-file-name "prompts/" tmp))
         (satan-system-scaffold-file
          (expand-file-name "system/scaffold.txt" tmp))
         (satan-system-framing-file
          (expand-file-name "system/framing.txt" tmp))
         (satan-self-edit-bundle-char-budget nil))
    (unwind-protect
        (progn
          (make-directory root t)
          (make-directory (expand-file-name "prompts" tmp))
          (make-directory (expand-file-name "system" tmp))
          (with-temp-file satan-system-scaffold-file (insert "S"))
          (satan-context-test--write-framing satan-system-framing-file)
          (with-temp-file (expand-file-name "prompts/se.txt" tmp) (insert "P"))
          (with-temp-file (expand-file-name "a.el" root) (insert (make-string 5000 ?a)))
          (with-temp-file (expand-file-name "b.el" root) (insert (make-string 5000 ?b)))
          (let* ((spec (list :name "self-edit-mech"
                             :prompt-file (expand-file-name "prompts/se.txt" tmp)
                             :source-roots (list root)))
                 (bundle (satan-context-self-edit spec))
                 (sources (plist-get bundle :sources))
                 (dropped (plist-get bundle :dropped-files)))
            (should (= 2 (length sources)))
            (should (null dropped))))
      (delete-directory tmp t))))

(ert-deftest satan-self-edit/source-roots-var-indirection ()
  "When :source-roots is absent, context-fn dereferences :source-roots-var."
  (let* ((tmp (make-temp-file "satan-se-" t))
         (root (expand-file-name "rrr" tmp))
         (satan-prompts-dir (expand-file-name "prompts/" tmp))
         (satan-system-scaffold-file
          (expand-file-name "system/scaffold.txt" tmp))
         (satan-system-framing-file
          (expand-file-name "system/framing.txt" tmp)))
    (unwind-protect
        (progn
          (make-directory root t)
          (make-directory (expand-file-name "prompts" tmp))
          (make-directory (expand-file-name "system" tmp))
          (with-temp-file satan-system-scaffold-file (insert "S"))
          (satan-context-test--write-framing satan-system-framing-file)
          (with-temp-file (expand-file-name "prompts/se.txt" tmp) (insert "P"))
          (with-temp-file (expand-file-name "only.el" root) (insert "x"))
          (defvar satan-context-test--roots nil)
          (let ((satan-context-test--roots (list root))
                (spec (list :name "self-edit-mech"
                            :prompt-file (expand-file-name "prompts/se.txt" tmp)
                            :source-roots-var 'satan-context-test--roots)))
            (should (satan-context-test--path-suffix-p
                     "/only.el"
                     (plist-get (satan-context-self-edit spec) :sources)))))
      (delete-directory tmp t))))

(ert-deftest satan-self-edit/mech-and-mind-modes-registered-distinctly ()
  "Both lanes resolve, share governance defaults, point at distinct roots."
  (let ((mech (satan-mode-resolve "self-edit-mech"))
        (mind (satan-mode-resolve "self-edit-mind")))
    (should (eq (plist-get mech :auto-apply) 'none))
    (should (eq (plist-get mind :auto-apply) 'none))
    (dolist (tool '("proposal_stage" "sway_border_set" "sway_border_reset"))
      (should (member tool (plist-get mech :tools)))
      (should (member tool (plist-get mind :tools))))
    (should (eq (plist-get mech :source-roots-var) 'satan-self-edit-mech-roots))
    (should (eq (plist-get mind :source-roots-var) 'satan-self-edit-mind-roots))
    (should-not (equal (plist-get mech :prompt-file)
                       (plist-get mind :prompt-file)))))

(ert-deftest satan-context/missing-prompt-errors ()
  "Mode prompt missing → context-fn signals; run cannot start."
  (let* ((tmp (make-temp-file "satan-ctx-" t))
         (satan-prompts-dir (expand-file-name "prompts/" tmp))
         (satan-system-scaffold-file
          (expand-file-name "system/scaffold.txt" tmp)))
    (unwind-protect
        (progn
          (make-directory (expand-file-name "system" tmp))
          (with-temp-file satan-system-scaffold-file (insert "S"))
          (let ((spec (list :name "self-edit-mech"
                            :prompt-file
                            (expand-file-name "prompts/never.txt" tmp)
                            :source-roots (list tmp))))
            (should-error (satan-context-self-edit spec)
                          :type 'error)))
      (delete-directory tmp t))))

(ert-deftest satan-context/missing-scaffold-errors ()
  "System scaffold missing → context-fn signals."
  (let* ((tmp (make-temp-file "satan-ctx-" t))
         (satan-prompts-dir (expand-file-name "prompts/" tmp))
         (satan-system-scaffold-file
          (expand-file-name "system/missing.txt" tmp)))
    (unwind-protect
        (progn
          (make-directory (expand-file-name "prompts" tmp))
          (with-temp-file (expand-file-name "prompts/se.txt" tmp) (insert "P"))
          (let ((spec (list :name "self-edit-mech"
                            :prompt-file
                            (expand-file-name "prompts/se.txt" tmp)
                            :source-roots (list tmp))))
            (should-error (satan-context-self-edit spec)
                          :type 'error)))
      (delete-directory tmp t))))

;; ---------- self-edit output (relocated from monolith) ----------

(ert-deftest satan-self-edit/output-only-applies-proposal-stage ()
  "Output handler auto-applies proposal.stage; everything else gets staged."
  (let* ((tmp (make-temp-file "satan-se-out-" t))
         (satan-proposals-dir tmp)
         (final '(:summary "x"
                  :actions ((:type "proposal_stage"
                             :args (:title "fix" :body "do the thing"))
                            (:type "org_update_owned_block"
                             :args (:target "today" :block "satan" :content "x")))))
         (ctx (list :id "r1" :mode-name "self-edit-mech"
                    :time-now "2026-05-23T12:00:00+1000"
                    :run-started-at "2026-05-23T12:00:00+1000"
                    :audit 'satan-context-test--stub-audit
                    :capabilities '(stage-proposal))))
    (unwind-protect
        (cl-letf (((symbol-function 'satan-intervention-create)
                   (lambda (&rest _args) "iv-ctx-stub-01")))
          (let ((p (satan-output/self-edit final ctx)))
            (should (equal (length (plist-get p :applied)) 1))
            (should (equal (length (plist-get p :staged)) 1))
            (should (equal (plist-get (car (plist-get p :applied)) :type)
                           "proposal_stage"))))
      (delete-directory tmp t))))

;; ---------- :now ----------

(ert-deftest satan-context/now-plist-shape ()
  "`:now' carries every key the harness renders into `# Now'."
  (let* ((time (encode-time 0 30 14 19 5 2026 nil nil 36000)) ; +1000
         (now (satan-context-now time)))
    (should (stringp (plist-get now :iso_date)))
    (should (string-match-p "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\'"
                            (plist-get now :iso_date)))
    (should (stringp (plist-get now :weekday)))
    (should (string-match-p "\\`[0-9]\\{4\\}-W[0-9]\\{2\\}\\'"
                            (plist-get now :iso_week)))
    (should (string-match-p "\\`[0-9]\\{2\\}:[0-9]\\{2\\}\\'"
                            (plist-get now :time)))
    (should (stringp (plist-get now :tz_offset)))
    (should (stringp (plist-get now :tz_name)))))

(ert-deftest satan-context/motd-bundle-carries-now ()
  (let* ((tmp (make-temp-file "satan-now-" t))
         (satan-system-scaffold-file
          (expand-file-name "system/scaffold.txt" tmp))
         (satan-system-framing-file
          (expand-file-name "system/framing.txt" tmp)))
    (unwind-protect
        (progn
          (make-directory (expand-file-name "system" tmp))
          (make-directory (expand-file-name "prompts" tmp))
          (with-temp-file satan-system-scaffold-file (insert "S"))
          (satan-context-test--write-framing satan-system-framing-file)
          (with-temp-file (expand-file-name "prompts/p.txt" tmp) (insert "P"))
          (let* ((spec (list :name "motd"
                             :prompt-file (expand-file-name "prompts/p.txt" tmp)))
                 (bundle (satan-context-motd spec))
                 (now (plist-get bundle :now)))
            (should (plistp now))
            (should (stringp (plist-get now :iso_date)))))
      (delete-directory tmp t))))

(ert-deftest satan-context/tick-bundle-carries-now ()
  (let* ((tmp (make-temp-file "satan-now-" t))
         (satan-system-scaffold-file
          (expand-file-name "system/scaffold.txt" tmp))
         (satan-system-framing-file
          (expand-file-name "system/framing.txt" tmp)))
    (unwind-protect
        (progn
          (make-directory (expand-file-name "system" tmp))
          (make-directory (expand-file-name "prompts" tmp))
          (with-temp-file satan-system-scaffold-file (insert "S"))
          (satan-context-test--write-framing satan-system-framing-file)
          (with-temp-file (expand-file-name "prompts/p.txt" tmp) (insert "P"))
          (let* ((spec (list :name "tick-pulse"
                             :prompt-file (expand-file-name "prompts/p.txt" tmp)))
                 (bundle (satan-context-tick spec))
                 (now (plist-get bundle :now)))
            (should (plistp now))
            (should (stringp (plist-get now :time)))))
      (delete-directory tmp t))))

(ert-deftest satan-context/self-edit-bundle-carries-now ()
  (let* ((tmp (make-temp-file "satan-now-" t))
         (root (expand-file-name "rrr" tmp))
         (satan-system-scaffold-file
          (expand-file-name "system/scaffold.txt" tmp))
         (satan-system-framing-file
          (expand-file-name "system/framing.txt" tmp)))
    (unwind-protect
        (progn
          (make-directory root t)
          (make-directory (expand-file-name "system" tmp))
          (make-directory (expand-file-name "prompts" tmp))
          (with-temp-file satan-system-scaffold-file (insert "S"))
          (satan-context-test--write-framing satan-system-framing-file)
          (with-temp-file (expand-file-name "prompts/se.txt" tmp) (insert "P"))
          (with-temp-file (expand-file-name "only.el" root) (insert "x"))
          (let* ((spec (list :name "self-edit-mech"
                             :prompt-file (expand-file-name "prompts/se.txt" tmp)
                             :source-roots (list root)))
                 (bundle (satan-context-self-edit spec))
                 (now (plist-get bundle :now)))
            (should (plistp now))
            (should (stringp (plist-get now :iso_date)))))
      (delete-directory tmp t))))

;; ---------- framing rendering ----------

(defun satan-context-test--with-framing (body-fn)
  "Run BODY-FN with `satan-system-framing-file' bound to a temp file."
  (let* ((tmp (make-temp-file "satan-framing-" t))
         (path (expand-file-name "framing.txt" tmp)))
    (unwind-protect
        (let ((satan-system-framing-file path))
          (satan-context-test--write-framing path)
          (funcall body-fn))
      (delete-directory tmp t))))

(ert-deftest satan-context/framing-parses-key-value ()
  (let ((alist (satan-context--parse-framing
                "# comment\nnow=# Now\n\ntoday=# Today (raw)\nsources=# Source files\n")))
    (should (equal (cdr (assoc "now" alist)) "# Now"))
    (should (equal (cdr (assoc "today" alist)) "# Today (raw)"))
    (should (equal (cdr (assoc "sources" alist)) "# Source files"))))

(ert-deftest satan-context/framing-missing-key-errors ()
  (let* ((tmp (make-temp-file "satan-framing-" t))
         (path (expand-file-name "framing.txt" tmp))
         (satan-system-framing-file path))
    (unwind-protect
        (progn
          (with-temp-file path (insert "now=# Now\n"))
          (should-error (satan-context--framing) :type 'error))
      (delete-directory tmp t))))

(ert-deftest satan-context/framing-missing-file-errors ()
  (let ((satan-system-framing-file "/tmp/satan-framing-does-not-exist-XYZ.txt"))
    (should-error (satan-context--framing) :type 'error)))

(ert-deftest satan-context/render-prompt-now-block ()
  "Rendered prompt prepends scaffold+mode and emits a `# Now' block."
  (satan-context-test--with-framing
   (lambda ()
     (let* ((bundle (list :now (list :iso_date "2026-05-19"
                                     :weekday "Tuesday"
                                     :iso_week "2026-W21"
                                     :time "09:00"
                                     :tz_offset "+1000"
                                     :tz_name "AEST")))
            (out (satan-context--render-prompt "ASSEMBLED" bundle)))
       (should (string-prefix-p "ASSEMBLED\n\n# Now\n" out))
       (should (string-match-p "^date: 2026-05-19 (Tuesday, ISO 2026-W21)$" out))
       (should (string-match-p "^time: 09:00 \\+1000 AEST$" out))))))

(ert-deftest satan-context/render-prompt-skips-empty-now ()
  "Missing or empty `:now' produces no `# Now' header."
  (satan-context-test--with-framing
   (lambda ()
     (let ((out (satan-context--render-prompt "ASSEMBLED" '())))
       (should (equal out "ASSEMBLED"))
       (should-not (string-match-p "^# Now$" out))))))

(ert-deftest satan-context/render-prompt-today-block ()
  "Non-empty `:today_text' produces a `# Today (raw)' block; empty skips."
  (satan-context-test--with-framing
   (lambda ()
     (let ((with-today (satan-context--render-prompt
                       "ASSEMBLED" (list :today_text "body text"))))
       (should (string-match-p "# Today (raw)\nbody text" with-today)))
     (let ((sans-today (satan-context--render-prompt
                       "ASSEMBLED" (list :today_text ""))))
       (should-not (string-match-p "# Today (raw)" sans-today))))))

(ert-deftest satan-context/render-prompt-sources-block ()
  "Each source emits a fenced `## PATH' subsection under `# Source files'."
  (satan-context-test--with-framing
   (lambda ()
     (let* ((sources (list (list :path "satan/x.el" :content "(provide 'x)")
                           (list :path "satan/y.py" :content "x = 1")))
            (out (satan-context--render-prompt
                  "ASSEMBLED" (list :sources sources))))
       (should (string-match-p "^# Source files$" out))
       (should (string-match-p "^## satan/x.el$" out))
       (should (string-match-p "(provide 'x)" out))
       (should (string-match-p "^## satan/y.py$" out))
       (should (string-match-p "^x = 1$" out))))))

(ert-deftest satan-context/render-prompt-section-ordering ()
  "Sections render in canonical order: Now, then Today, then Source files."
  (satan-context-test--with-framing
   (lambda ()
     (let* ((bundle (list :now (list :iso_date "2026-05-19" :time "09:00")
                          :today_text "BODY"
                          :sources (list (list :path "p" :content "c"))))
            (out (satan-context--render-prompt "A" bundle))
            (i-now    (string-match "^# Now$"          out))
            (i-today  (string-match "^# Today (raw)$"  out))
            (i-source (string-match "^# Source files$" out)))
       (should i-now)
       (should i-today)
       (should i-source)
       (should (< i-now i-today))
       (should (< i-today i-source))))))

;; ── interactive boot capsule (DEC-13, AUD-008 F-003/F-004/F-005) ───────────

(ert-deftest satan-context/interactive-does-not-mutate-run-ctx ()
  "AUD-008 F-004: `satan-context-interactive' must not clobber the
caller's session-frozen `:time_now' (or inject assembly keys into it)."
  (skip-unless (satan-context-test--corpus-p
                satan-system-scaffold-file satan-system-framing-file))
  (let ((run-ctx (list :run_id "rid" :time_now "FROZEN-SESSION-TIME")))
    (cl-letf (((symbol-function 'satan-run-dir-for-id) (lambda (_) "/tmp"))
              ((symbol-function 'satan-run-assemble-context)
               (lambda (prepare &rest _) prepare))
              ((symbol-function 'satan-attribute-snapshot) (lambda (&rest _) nil)))
      (satan-context-interactive '(:name "interactive") run-ctx)
      (should (equal (plist-get run-ctx :time_now) "FROZEN-SESSION-TIME"))
      ;; assembly keys must not have leaked onto the caller's plist
      (should-not (plist-member run-ctx :percept))
      (should-not (plist-member run-ctx :resonance)))))

(ert-deftest satan-context/interactive-degrades-on-assembly-failure ()
  "AUD-008 F-003/F-005: an assembly backend failure yields a partial capsule
string rather than erroring the session."
  (skip-unless (satan-context-test--corpus-p
                satan-system-scaffold-file satan-system-framing-file))
  (let ((run-ctx (list :run_id "rid" :time_now "FROZEN")))
    (cl-letf (((symbol-function 'satan-run-dir-for-id) (lambda (_) "/tmp"))
              ((symbol-function 'satan-run-assemble-context)
               (lambda (&rest _) (error "backend unreachable")))
              ((symbol-function 'satan-attribute-snapshot) (lambda (&rest _) nil)))
      (let ((bundle (satan-context-interactive '(:name "interactive") run-ctx)))
        ;; Did not error; produced a rendered prompt string.
        (should (stringp (plist-get bundle :prompt)))
        ;; Degraded resonance recorded.
        (should (eq 'memory-unreachable
                    (plist-get (plist-get bundle :resonance) :status)))
        ;; Session-frozen time preserved (F-004 holds on the degraded path too).
        (should (equal (plist-get run-ctx :time_now) "FROZEN"))))))

(ert-deftest satan-context/interactive-bundle-byte-stable-on-frozen-inputs ()
  "VT-mcp-bundle (DR-010 §5, Task 1.5): the interactive-boot bundle is
byte-stable across two builds on frozen inputs.  ISSUE-001's perceive-
first change adds harmless pure probe reads on boot; this pins that the
interactive capsule the MCP server emits is unchanged build-to-build.

`current-time' is frozen (the only otherwise-fresh input — F3 stamps
`:now'/`:time_now' from it), assembly is stubbed to a deterministic
prepare, and the attribute snapshot is pinned.  Both builds must produce
`equal' bundles and byte-identical `:prompt' strings."
  (skip-unless (satan-context-test--corpus-p
                satan-system-scaffold-file satan-system-framing-file))
  (let ((run-ctx (list :run_id "20260609T100000-interactive-aaaaaa"
                       :time_now "FROZEN-SESSION-TIME"))
        (frozen (encode-time '(0 0 10 9 6 2026 nil nil 36000))))
    (cl-letf (((symbol-function 'current-time) (lambda () frozen))
              ((symbol-function 'satan-run-dir-for-id) (lambda (_) "/tmp"))
              ((symbol-function 'satan-attribute-snapshot) (lambda (&rest _) nil))
              ;; Deterministic assembly — a fixed percept/resonance/motive.
              ((symbol-function 'satan-run-assemble-context)
               (lambda (prepare &rest _)
                 (thread-first prepare
                               (plist-put :percept (list :handles '("app:firefox")))
                               (plist-put :resonance (list :status 'ok :matches nil))
                               (plist-put :motive nil)
                               (plist-put :sensor_status nil)))))
      (let ((one (satan-context-interactive '(:name "interactive") run-ctx))
            (two (satan-context-interactive '(:name "interactive") run-ctx)))
        ;; Whole-bundle identity …
        (should (equal one two))
        ;; … and the harness-consumed prompt is byte-for-byte identical.
        (should (stringp (plist-get one :prompt)))
        (should (string= (plist-get one :prompt) (plist-get two :prompt)))))))

(provide 'satan-context-test)
;;; satan-context-test.el ends here
