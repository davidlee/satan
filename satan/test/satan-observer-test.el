;;; satan-observer-test.el --- outcome observer ert -*- lexical-binding: t; -*-

;; T7 PR 5 swapped the read path from `transcript.jsonl' walks +
;; observer.json dedup to the projection (`satan-intervention-
;; pending') and the write path from a dedup state file to
;; `satan-intervention-classify' (audit event + projection
;; UPSERT).  Tests that need real interventions mirror
;; `satan-intervention-test--with-db' (skip-unless reachable +
;; reset-and-migrate).
;;
;; The classifier (§S5 P1–P4) lives in `satan-observer-classify'
;; (T1 split) so its ert (baseline read, window-end, predicate
;; primitives, single-motive glue, multi-motive rank) is unchanged
;; by PR 5.

(require 'ert)
(require 'cl-lib)
(require 'json)
(require 'satan-audit)
(require 'satan-intervention)
(require 'satan-jsonl)
(require 'satan-memory-migrate)
(require 'satan-observer)
(require 'satan-observer-classify)
(require 'satan-motive)
(require 'satan-motive-test)

;; Declare `satan-runs-dir' dynamic up-front so the `let*' bindings
;; below don't clash when `satan-broker' loads later and tries to
;; `defvar' the same name.
(defvar satan-runs-dir)

;; ---------------------------------------------------------------------
;; DB fixture (mirrors satan-intervention-test--with-db)
;; ---------------------------------------------------------------------

(defconst satan-observer-test--db "satan_memory_test")

(defun satan-observer-test--reachable-p ()
  (pcase (let ((satan-memory-migrate-database
                satan-observer-test--db))
           (satan-db-psql
            satan-observer-test--db satan-memory-migrate-host satan-memory-migrate-psql-program
            (list "-A" "-t" "-c" "SELECT 1")))
    (`(ok . ,_) t)
    (_ nil)))

(defun satan-observer-test--reset-and-migrate ()
  "Drop everything in the test DB and re-run migrations through 0006."
  (let ((satan-memory-migrate-database satan-observer-test--db))
    (satan-db-psql
     satan-observer-test--db satan-memory-migrate-host satan-memory-migrate-psql-program
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

(defmacro satan-observer-test--with-db (&rest body)
  (declare (indent 0))
  `(progn
     (skip-unless (satan-observer-test--reachable-p))
     (satan-observer-test--reset-and-migrate)
     (satan-intervention--reset-counters)
     (let ((satan-memory-migrate-database satan-observer-test--db))
       ,@body)))

;; ---------------------------------------------------------------------
;; Tmp / run-dir / bundle fixture
;; ---------------------------------------------------------------------

(defun satan-observer-test--in-tmp (body-fn)
  "Run BODY-FN with a temporary runs root path, cleaning up after."
  (let ((root (make-temp-file "satan-observer-runs-" t)))
    (unwind-protect (funcall body-fn root)
      (delete-directory root t))))

(defun satan-observer-test--date-bucket (run-id)
  "Return the YYYY-MM-DD bucket dir name for RUN-ID."
  (when (string-match "\\`\\([0-9]\\{4\\}\\)\\([0-9]\\{2\\}\\)\\([0-9]\\{2\\}\\)T"
                      run-id)
    (format "%s-%s-%s"
            (match-string 1 run-id)
            (match-string 2 run-id)
            (match-string 3 run-id))))

(defun satan-observer-test--make-run-dir (runs-root run-id)
  "Materialise an empty run dir under RUNS-ROOT for RUN-ID.  Returns path."
  (let* ((bucket (satan-observer-test--date-bucket run-id))
         (dir (expand-file-name (concat bucket "/" run-id) runs-root)))
    (make-directory dir t)
    dir))

(defun satan-observer-test--write-bundle (dir bundle)
  "Write BUNDLE (plist) as `bundle.json' under DIR."
  (make-directory dir t)
  (let ((coding-system-for-write 'utf-8))
    (with-temp-file (expand-file-name "bundle.json" dir)
      (insert (json-serialize (satan-jsonl-prepare bundle)
                              :null-object :null
                              :false-object :false)))))

(defun satan-observer-test--write-bundle-with-handles (dir handles)
  (satan-observer-test--write-bundle
   dir (list :percept
             (list :handles handles
                   :evidence_window
                   (list :git_state (list :head_short "h"
                                          :remote "r")
                         :fs_state (list :cwd "/x" :recent_files nil)
                         :focus_segments nil
                         :bough_recent nil)))))

;; ---------------------------------------------------------------------
;; Audit handle + intervention minting (DB)
;; ---------------------------------------------------------------------

(defun satan-observer-test--open-audit (root run-id)
  "Open a fresh audit handle under ROOT/<bucket>/RUN-ID/."
  (let ((run-dir (satan-observer-test--make-run-dir root run-id)))
    (satan-audit-open run-dir
                         (list :run_id run-id :mode (list :name "morning"))
                         '(:bundle t))))

(defun satan-observer-test--build-ctx (audit run-id &optional ts)
  (list :id run-id
        :mode-name "morning"
        :time-now (or ts "2026-05-23T12:00:00+1000")
        :audit audit))

(cl-defun satan-observer-test--mint
    (ctx &key (kind "notify") (target "sway-mainbar")
         (message "do thing") (window 30) (severity "low")
         (expected "user opens kanban.org")
         related-motive-id cue-handles)
  "Create an intervention through `satan-intervention-create' and
return the minted id.  All keyword args have sensible defaults so
tests only override what they care about."
  (satan-intervention-create
   :ctx ctx :kind kind :target-surface target :message message
   :expected-outcome expected :outcome-window-minutes window
   :severity severity
   :related-motive-id related-motive-id
   :cue-handles cue-handles))

;; ---------------------------------------------------------------------
;; Classifier-test fixture (shared with §S5 P1–P4 ert)
;; ---------------------------------------------------------------------

(defconst satan-observer-test--cwd "/tmp/satan-obs-proj")
(defconst satan-observer-test--emitted "2026-05-22T10:00:00+1000")

(defun satan-observer-test--motive (&rest overrides)
  "Build a motive plist with sensible defaults; OVERRIDES merge on top."
  (let ((base (list :project_cwd satan-observer-test--cwd
                    :cue (list "project:satan-obs-proj"))))
    (while overrides
      (setq base (plist-put base (pop overrides) (pop overrides))))
    base))

(cl-defun satan-observer-test--intervention
    (&key (kind "notify") (target-surface "sway-mainbar"))
  "Classifier-shaped intervention plist (the result of
`satan-observer-pending' projection-normalisation).  Used by
predicate ert that drive `satan-observer-classify' directly.

KIND defaults to a user-facing kind (`notify') so a no-fire scan
classifies as `:ignored' per T1.5b PR 2.  Tests exercising the
non-user-facing branch (`:neutral') override KIND."
  (list :intervention_id "20260522T100000-tick-aaa.iv001"
        :run_id "20260522T100000-tick-aaa"
        :applied_index 1
        :ts satan-observer-test--emitted
        :intervention_emitted_at satan-observer-test--emitted
        :outcome_window_minutes 30
        :kind kind
        :target_surface target-surface))

(defun satan-observer-test--stub-after-state (after-plist)
  "Return a function that mimics `--after-state' by returning AFTER-PLIST."
  (lambda (&rest _) after-plist))

(defmacro satan-observer-test--with-stubbed-after-state (after &rest body)
  "Run BODY with `--after-state' stubbed to return AFTER (plist)."
  (declare (indent 1))
  `(cl-letf (((symbol-function 'satan-observer--after-state)
              (satan-observer-test--stub-after-state ,after)))
     ,@body))

(defun satan-observer-test--positive-verdict (&optional predicate confidence)
  "Build a T1.5b §2-shape `:worked' verdict for persist tests.
PREDICATE defaults to `:git_commit_observed' (the §S5 P2 firer).
CONFIDENCE defaults to `:medium' (single-fire); pass `:high' to
simulate a multi-predicate firing."
  (list :classification :worked
        :confidence (or confidence :medium)
        :predicates (list (or predicate :git_commit_observed))
        :reason nil))

(defun satan-observer-test--negative-verdict (&optional reason)
  "Build a T1.5b §2-shape `:unknown' verdict for persist tests."
  (list :classification :unknown
        :confidence :low
        :predicates nil
        :reason reason))

(cl-defun satan-observer-test--ignored-verdict
    (&key (confidence :low) (target-surface "sway-mainbar")
          (acknowledgement-checked :false) (ack-events-found 0))
  "Build a T1.5b PR 2 `:ignored' verdict for persist tests."
  (list :classification :ignored
        :confidence confidence
        :predicates nil
        :reason nil
        :evidence (list :target-surface target-surface
                        :no-positive-predicates t
                        :acknowledgement-checked acknowledgement-checked
                        :ack-events-found ack-events-found)))

(defun satan-observer-test--neutral-verdict (&optional target-surface)
  "Build a T1.5b PR 2 `:neutral' verdict for persist tests."
  (list :classification :neutral
        :confidence :low
        :predicates nil
        :reason nil
        :evidence (list :target-surface (or target-surface "internal")
                        :no-positive-predicates t)))

(defun satan-observer-test--full-motive (&rest overrides)
  "Motive plist with worked_count + cue for persist tests."
  (let ((base (list :id "docs-after-error"
                    :project_cwd satan-observer-test--cwd
                    :cue (list "project:emacs.d"
                               "domain_kind:docs"
                               "surface_transition:terminal->browser")
                    :worked_count 4)))
    (while overrides
      (setq base (plist-put base (pop overrides) (pop overrides))))
    base))

(defmacro satan-observer-test--capture-mark (sym &rest body)
  "Bind SYM as a list collecting every (kind . args) call to
`satan-memory-store-mark'.  The stub returns `(ok . \"tid-stub\")'."
  (declare (indent 1))
  `(let* ((,sym nil)
          (mark-fn (lambda (&rest args)
                     (push args ,sym)
                     (cons 'ok "tid-stub"))))
     ,@body))

;; ---------------------------------------------------------------------
;; Phase 5.4a — baseline + after-state helpers (classifier)
;; ---------------------------------------------------------------------

(ert-deftest satan-observer/baseline-read-returns-evidence-window ()
  "5.4a — `--baseline-read' yields the persisted `:evidence_window'
from `bundle.json' → `:percept' → `:evidence_window'."
  (satan-observer-test--in-tmp
   (lambda (root)
     (let* ((dir (expand-file-name "20260522T100000-tick-aaa" root))
            (ev (list :git_state (list :head_short "deadbeef" :dirty :false)
                      :fs_state (list :cwd "/tmp" :recent_files nil)
                      :window_start_at "2026-05-22T10:00:00+1000"
                      :window_end_at "2026-05-22T10:10:00+1000")))
       (satan-observer-test--write-bundle
        dir (list :percept (list :evidence_window ev)))
       (let ((out (satan-observer--baseline-read dir)))
         (should (equal "deadbeef" (plist-get (plist-get out :git_state)
                                              :head_short))))))))

(ert-deftest satan-observer/baseline-read-missing-returns-nil ()
  "5.4a — runs without `bundle.json' yield nil; classifier converts that
to `:reason :no_baseline'."
  (satan-observer-test--in-tmp
   (lambda (root)
     (let ((dir (expand-file-name "20260522T100000-tick-bbb" root)))
       (make-directory dir t)
       (should (null (satan-observer--baseline-read dir)))))))

(ert-deftest satan-observer/baseline-read-malformed-returns-nil ()
  "5.4a — corrupt `bundle.json' yields nil rather than signalling."
  (satan-observer-test--in-tmp
   (lambda (root)
     (let ((dir (expand-file-name "20260522T100000-tick-ccc" root)))
       (make-directory dir t)
       (with-temp-file (expand-file-name "bundle.json" dir)
         (insert "{not valid json"))
       (should (null (satan-observer--baseline-read dir)))))))

(ert-deftest satan-observer/baseline-read-no-percept-returns-nil ()
  "5.4a — `bundle.json' missing `:percept' slot yields nil."
  (satan-observer-test--in-tmp
   (lambda (root)
     (let ((dir (expand-file-name "20260522T100000-tick-ddd" root)))
       (satan-observer-test--write-bundle
        dir (list :run_id "x" :time_now "2026-05-22T10:00:00+1000"))
       (should (null (satan-observer--baseline-read dir)))))))

(ert-deftest satan-observer/window-end-iso-adds-mature-seconds ()
  "5.4a — `--window-end-iso' adds `window-mature-seconds' to the
intervention timestamp, returning an ISO string in the same zone."
  (let* ((satan-observer-window-mature-seconds 1800)
         (iv (list :intervention_emitted_at "2026-05-22T10:00:00+1000"))
         (end (satan-observer--window-end-iso iv)))
    (should (equal (substring end 0 19) "2026-05-22T10:30:00"))))

(ert-deftest satan-observer/window-crosses-midnight-p-same-day ()
  (let ((iv (list :intervention_emitted_at "2026-05-22T10:00:00+1000")))
    (should-not (satan-observer--window-crosses-midnight-p iv))))

(ert-deftest satan-observer/window-crosses-midnight-p-rolls-over ()
  (let ((iv (list :intervention_emitted_at "2026-05-22T23:50:00+1000")))
    (should (satan-observer--window-crosses-midnight-p iv))))

;; ---------------------------------------------------------------------
;; Phase 5.4b — positive predicate primitives (§S5 P1–P4)
;; ---------------------------------------------------------------------

;; --- P1 editor edit in window -----------------------------------------

(ert-deftest satan-observer/p1-editor-edit-fires ()
  "P1 fires on an emacs segment starting after intervention with a
last_title that resolves under `:project_cwd'."
  (let* ((motive (satan-observer-test--motive))
         (iv (satan-observer-test--intervention))
         (after (list :focus_segments
                      (list (list :app_id "emacs"
                                  :start_ts "2026-05-22T10:05:00+1000"
                                  :end_ts "2026-05-22T10:08:00+1000"
                                  :last_title
                                  (concat satan-observer-test--cwd
                                          "/foo.el - GNU Emacs at Sleipnir"))))))
    (should (satan-observer--predicate-editor-edit-in-window
             nil after motive iv))))

(ert-deftest satan-observer/p1-coincidence-outside-cwd-does-not-fire ()
  "A12 — emacs segment whose title resolves to a path NOT under
`:project_cwd' must not fire P1."
  (let* ((motive (satan-observer-test--motive))
         (iv (satan-observer-test--intervention))
         (after (list :focus_segments
                      (list (list :app_id "emacs"
                                  :start_ts "2026-05-22T10:05:00+1000"
                                  :last_title
                                  "/other/repo/bar.el - GNU Emacs at Sleipnir")))))
    (should-not (satan-observer--predicate-editor-edit-in-window
                 nil after motive iv))))

(ert-deftest satan-observer/p1-segment-starting-at-or-before-emitted-does-not-fire ()
  "P1 requires `start_ts' strictly after `:intervention_emitted_at'."
  (let* ((motive (satan-observer-test--motive))
         (iv (satan-observer-test--intervention))
         (after (list :focus_segments
                      (list (list :app_id "emacs"
                                  :start_ts satan-observer-test--emitted
                                  :last_title
                                  (concat satan-observer-test--cwd
                                          "/foo.el - GNU Emacs at Sleipnir"))))))
    (should-not (satan-observer--predicate-editor-edit-in-window
                 nil after motive iv))))

(ert-deftest satan-observer/p1-non-editor-app-does-not-fire ()
  (let* ((motive (satan-observer-test--motive))
         (iv (satan-observer-test--intervention))
         (after (list :focus_segments
                      (list (list :app_id "firefox"
                                  :start_ts "2026-05-22T10:05:00+1000"
                                  :last_title
                                  (concat satan-observer-test--cwd
                                          "/foo.el - GNU Emacs at Sleipnir"))))))
    (should-not (satan-observer--predicate-editor-edit-in-window
                 nil after motive iv))))

(ert-deftest satan-observer/p1-missing-last-title-skips ()
  (let* ((motive (satan-observer-test--motive))
         (iv (satan-observer-test--intervention))
         (after (list :focus_segments
                      (list (list :app_id "emacs"
                                  :start_ts "2026-05-22T10:05:00+1000")))))
    (should-not (satan-observer--predicate-editor-edit-in-window
                 nil after motive iv))))

(ert-deftest satan-observer/p1-no-project-cwd-skips ()
  (let* ((motive (satan-observer-test--motive :project_cwd nil))
         (iv (satan-observer-test--intervention))
         (after (list :focus_segments
                      (list (list :app_id "emacs"
                                  :start_ts "2026-05-22T10:05:00+1000"
                                  :last_title
                                  "/anywhere/foo.el - GNU Emacs at Sleipnir")))))
    (should-not (satan-observer--predicate-editor-edit-in-window
                 nil after motive iv))))

;; --- P2 git commit observed ------------------------------------------

(defconst satan-observer-test--p2-emitted "2026-05-22T10:00:00+1000")
(defconst satan-observer-test--p2-window-end "2026-05-22T10:30:00+1000")

(defun satan-observer-test--p2-commit-row (&rest overrides)
  "Build a git commit row plist for P2 predicate tests."
  (let ((base (list :repo "/tmp/satan-obs-proj"
                    :slug "satan-obs-proj"
                    :sha "abcdef12"
                    :end_ts "2026-05-22T10:15:00+1000")))
    (while overrides
      (setq base (plist-put base (pop overrides) (pop overrides))))
    base))

(defun satan-observer-test--p2-after (&rest rows)
  "Build an after-state plist carrying `:git_commits' for P2 tests."
  (list :git_commits (or rows '())))

(defun satan-observer-test--p2-intervention (&rest overrides)
  "Build an intervention plist for P2 predicate tests.
Defaults: emitted at 2026-05-22T10:00, 30-min window."
  (let ((base (list :intervention_emitted_at satan-observer-test--p2-emitted
                    :outcome_window_minutes 30)))
    (while overrides
      (setq base (plist-put base (pop overrides) (pop overrides))))
    base))

(ert-deftest satan-observer/p2-commit-observed-fires-in-window ()
  "VT-commit-observed: fires for a matching commit whose :end_ts falls
in the attribution window."
  (let* ((motive (satan-observer-test--motive))
         (after (satan-observer-test--p2-after
                 (satan-observer-test--p2-commit-row)))
         (iv (satan-observer-test--p2-intervention)))
    (should (satan-observer--predicate-git-commit-observed
             nil after motive iv))))

(ert-deftest satan-observer/p2-commit-observed-no-project-cwd ()
  "No fire when motive lacks `:project_cwd'."
  (let* ((motive (list :cue (list "project:satan-obs-proj")))
         (after (satan-observer-test--p2-after
                 (satan-observer-test--p2-commit-row)))
         (iv (satan-observer-test--p2-intervention)))
    (should-not (satan-observer--predicate-git-commit-observed
                 nil after motive iv))))

(ert-deftest satan-observer/p2-commit-observed-wrong-repo ()
  "No fire when the commit row's repo doesn't match the motive's repo."
  (let* ((motive (satan-observer-test--motive))
         (after (satan-observer-test--p2-after
                 (satan-observer-test--p2-commit-row
                  :repo "/tmp/unrelated" :slug "unrelated")))
         (iv (satan-observer-test--p2-intervention)))
    (should-not (satan-observer--predicate-git-commit-observed
                 nil after motive iv))))

(ert-deftest satan-observer/p2-commit-observed-matches-by-cue-slug ()
  "Fires when `:slug' matches a `project:' token in motive's `:cue',
even when `:repo' path doesn't match."
  (let* ((motive (satan-observer-test--motive
                  :project_cwd "/tmp/unrelated"
                  :cue (list "project:satan-obs-proj")))
         (after (satan-observer-test--p2-after
                 (satan-observer-test--p2-commit-row)))
         (iv (satan-observer-test--p2-intervention)))
    (should (satan-observer--predicate-git-commit-observed
             nil after motive iv))))

(ert-deftest satan-observer/p2-commit-outside-window-does-not-fire ()
  "No fire when commit :end_ts is before the intervention emit time."
  (let* ((motive (satan-observer-test--motive))
         (after (satan-observer-test--p2-after
                 (satan-observer-test--p2-commit-row
                  :end_ts "2026-05-22T09:45:00+1000")))
         (iv (satan-observer-test--p2-intervention)))
    (should-not (satan-observer--predicate-git-commit-observed
                 nil after motive iv))))

(ert-deftest satan-observer/p2-no-commits-no-fire ()
  "No fire when `:git_commits' is empty."
  (let* ((motive (satan-observer-test--motive))
         (after (satan-observer-test--p2-after))
         (iv (satan-observer-test--p2-intervention)))
    (should-not (satan-observer--predicate-git-commit-observed
                 nil after motive iv))))

;; --- P3 recent_files delta --------------------------------------------

(ert-deftest satan-observer/p3-recent-files-delta-fires ()
  (let* ((motive (satan-observer-test--motive))
         (baseline (list :fs_state
                         (list :cwd satan-observer-test--cwd
                               :recent_files (list "old.el"))))
         (after (list :fs_state
                      (list :cwd satan-observer-test--cwd
                            :recent_files (list "old.el" "new.el")))))
    (should (satan-observer--predicate-fs-recent-delta
             baseline after motive nil))))

(ert-deftest satan-observer/p3-coincidence-outside-cwd-does-not-fire ()
  (let* ((motive (satan-observer-test--motive))
         (baseline (list :fs_state
                         (list :cwd "/other/repo" :recent_files nil)))
         (after (list :fs_state
                      (list :cwd "/other/repo"
                            :recent_files (list "noise.el")))))
    (should-not (satan-observer--predicate-fs-recent-delta
                 baseline after motive nil))))

(ert-deftest satan-observer/p3-no-project-cwd-skips ()
  (let* ((motive (satan-observer-test--motive :project_cwd nil))
         (baseline (list :fs_state (list :cwd "/x" :recent_files nil)))
         (after (list :fs_state (list :cwd "/x" :recent_files (list "a.el")))))
    (should-not (satan-observer--predicate-fs-recent-delta
                 baseline after motive nil))))

(ert-deftest satan-observer/p3-handles-different-cwds-by-absolute-path ()
  (let* ((motive (satan-observer-test--motive))
         (baseline (list :fs_state
                         (list :cwd "/other/repo"
                               :recent_files
                               (list "../../tmp/satan-obs-proj/foo.el"))))
         (after (list :fs_state
                      (list :cwd satan-observer-test--cwd
                            :recent_files (list "foo.el")))))
    (should-not (satan-observer--predicate-fs-recent-delta
                 baseline after motive nil))))

;; --- P4 bough event match ---------------------------------------------

(ert-deftest satan-observer/p4-bough-node-match-fires ()
  (let* ((motive (satan-observer-test--motive
                  :cue (list "bough_node:nano123" "project:foo")))
         (after (list :bough_recent
                      (list (list :event "status_changed"
                                  :nanoid "nano123" :from "todo" :to "done")))))
    (should (satan-observer--predicate-bough-event-match
             nil after motive nil))))

(ert-deftest satan-observer/p4-bough-project-match-fires ()
  (let* ((motive (satan-observer-test--motive
                  :cue (list "bough_project:proj456")))
         (after (list :bough_recent
                      (list (list :event "status_changed"
                                  :nanoid "proj456")))))
    (should (satan-observer--predicate-bough-event-match
             nil after motive nil))))

(ert-deftest satan-observer/p4-noise-event-does-not-fire ()
  (let* ((motive (satan-observer-test--motive
                  :cue (list "bough_node:nano123")))
         (after (list :bough_recent
                      (list (list :event "status_changed"
                                  :nanoid "different")))))
    (should-not (satan-observer--predicate-bough-event-match
                 nil after motive nil))))

(ert-deftest satan-observer/p4-no-bough-handles-skips ()
  (let* ((motive (satan-observer-test--motive
                  :cue (list "project:foo")))
         (after (list :bough_recent
                      (list (list :event "status_changed"
                                  :nanoid "anything")))))
    (should-not (satan-observer--predicate-bough-event-match
                 nil after motive nil))))

;; ---------------------------------------------------------------------
;; Phase 5.4c — single-motive classifier glue
;; ---------------------------------------------------------------------

(ert-deftest satan-observer/classify-dormant-motive-skips ()
  (let* ((motive (satan-observer-test--motive :dormant t))
         (iv (satan-observer-test--intervention))
         (out (satan-observer-classify iv motive)))
    (should (eq :unknown (plist-get out :classification)))
    (should (eq :low (plist-get out :confidence)))
    (should (null (plist-get out :predicates)))
    (should (eq :motive_dormant (plist-get out :reason)))))

(ert-deftest satan-observer/classify-midnight-crossing-skips ()
  (let* ((motive (satan-observer-test--motive))
         (iv (plist-put (satan-observer-test--intervention)
                        :intervention_emitted_at
                        "2026-05-22T23:50:00+1000"))
         (out (satan-observer-classify iv motive)))
    (should (eq :unknown (plist-get out :classification)))
    (should (eq :low (plist-get out :confidence)))
    (should (eq :crosses_midnight (plist-get out :reason)))))

(ert-deftest satan-observer/classify-no-baseline-yields-reason ()
  (satan-observer-test--in-tmp
   (lambda (root)
     (let* ((dir (expand-file-name "20260522T100000-tick-aaa" root))
            (_ (make-directory dir t))
            (motive (satan-observer-test--motive))
            (iv (plist-put (satan-observer-test--intervention)
                           :run_dir dir))
            (out (satan-observer-classify iv motive)))
       (should (eq :unknown (plist-get out :classification)))
       (should (eq :low (plist-get out :confidence)))
       (should (eq :no_baseline (plist-get out :reason)))))))

(ert-deftest satan-observer/classify-positive-via-git-head ()
  (satan-observer-test--in-tmp
   (lambda (root)
     (let* ((dir (expand-file-name "20260522T100000-tick-aaa" root))
            (baseline-ev
             (list :fs_state (list :cwd satan-observer-test--cwd
                                   :recent_files nil)
                   :focus_segments nil :bough_recent nil))
            (after-ev
             (list :git_commits
                   (list (list :repo satan-observer-test--cwd
                               :slug "satan-obs-proj"
                               :sha "bbbbbbb"
                               :end_ts "2026-05-22T10:15:00+1000"))
                   :fs_state (list :cwd satan-observer-test--cwd
                                   :recent_files nil)
                   :focus_segments nil :bough_recent nil))
            (motive (satan-observer-test--motive))
            (iv (plist-put (satan-observer-test--intervention)
                           :run_dir dir)))
       (satan-observer-test--write-bundle
        dir (list :percept (list :evidence_window baseline-ev)))
       (satan-observer-test--with-stubbed-after-state after-ev
         (let ((out (satan-observer-classify iv motive)))
           (should (eq :worked (plist-get out :classification)))
           (should (eq :medium (plist-get out :confidence)))
           (should (equal '(:git_commit_observed)
                          (plist-get out :predicates)))
           (should (null (plist-get out :reason)))))))))

(ert-deftest satan-observer/classify-multi-fire-yields-high-confidence ()
  "T1.5b PR 1 §4 — `:confidence :high' when ≥2 predicates fire.
Here P2 (git commit observed) and P3 (fs recent delta) both fire on the
same scan."
  (satan-observer-test--in-tmp
   (lambda (root)
     (let* ((dir (expand-file-name "20260522T100000-tick-aaa" root))
            (cwd satan-observer-test--cwd)
            (baseline-ev
             (list :git_state (list :head_short "aaaaaaa" :remote "r")
                   :fs_state (list :cwd cwd :recent_files (list "old.el"))
                   :focus_segments nil :bough_recent nil))
            (after-ev
             (list :git_commits
                   (list (list :repo cwd
                               :slug "satan-obs-proj"
                               :sha "bbbbbbb"
                               :end_ts "2026-05-22T10:15:00+1000"))
                   :fs_state (list :cwd cwd
                                   :recent_files (list "old.el" "new.el"))
                   :focus_segments nil :bough_recent nil))
            (motive (satan-observer-test--motive))
            (iv (plist-put (satan-observer-test--intervention)
                           :run_dir dir)))
       (satan-observer-test--write-bundle
        dir (list :percept (list :evidence_window baseline-ev)))
       (satan-observer-test--with-stubbed-after-state after-ev
         (let ((out (satan-observer-classify iv motive)))
           (should (eq :worked (plist-get out :classification)))
           (should (eq :high (plist-get out :confidence)))
           ;; predicates order mirrors `satan-observer--predicates'.
           (should (equal '(:git_commit_observed :fs_recent_delta)
                          (plist-get out :predicates)))))))))

(ert-deftest satan-observer/classify-no-fire-user-facing-yields-ignored ()
  "T1.5b PR 2 — no positive predicate + user-facing kind (default
fixture is `notify') → `:ignored'.  Stubbed AFTER carries no
`:sensor_status' so the ack probe is unverified → `:low'."
  (satan-observer-test--in-tmp
   (lambda (root)
     (let* ((dir (expand-file-name "20260522T100000-tick-aaa" root))
            (stable (list :git_state (list :head_short "aaaaaaa"
                                           :remote "github.com/u/r")
                          :fs_state (list :cwd satan-observer-test--cwd
                                          :recent_files nil)
                          :focus_segments nil :bough_recent nil))
            (motive (satan-observer-test--motive))
            (iv (plist-put (satan-observer-test--intervention)
                           :run_dir dir)))
       (satan-observer-test--write-bundle
        dir (list :percept (list :evidence_window stable)))
       (satan-observer-test--with-stubbed-after-state stable
         (let* ((out (satan-observer-classify iv motive))
                (ev (plist-get out :evidence)))
           (should (eq :ignored (plist-get out :classification)))
           (should (eq :low (plist-get out :confidence)))
           (should (null (plist-get out :predicates)))
           (should (null (plist-get out :reason)))
           (should (equal "sway-mainbar" (plist-get ev :target-surface)))
           (should (eq t (plist-get ev :no-positive-predicates)))
           (should (eq :false (plist-get ev :acknowledgement-checked)))
           (should (= 0 (plist-get ev :ack-events-found)))))))))

(ert-deftest satan-observer/classify-no-fire-non-user-facing-yields-neutral ()
  "T1.5b PR 2 — no positive predicate + non-user-facing kind →
`:neutral :low'."
  (satan-observer-test--in-tmp
   (lambda (root)
     (let* ((dir (expand-file-name "20260522T100000-tick-aaa" root))
            (stable (list :git_state (list :head_short "aaaaaaa"
                                           :remote "github.com/u/r")
                          :fs_state (list :cwd satan-observer-test--cwd
                                          :recent_files nil)
                          :focus_segments nil :bough_recent nil))
            (motive (satan-observer-test--motive))
            (iv (plist-put (satan-observer-test--intervention
                            :kind "delay" :target-surface "internal")
                           :run_dir dir)))
       (satan-observer-test--write-bundle
        dir (list :percept (list :evidence_window stable)))
       (satan-observer-test--with-stubbed-after-state stable
         (let* ((out (satan-observer-classify iv motive))
                (ev (plist-get out :evidence)))
           (should (eq :neutral (plist-get out :classification)))
           (should (eq :low (plist-get out :confidence)))
           (should (null (plist-get out :predicates)))
           (should (equal "internal" (plist-get ev :target-surface)))
           (should (eq t (plist-get ev :no-positive-predicates)))))))))

(ert-deftest satan-observer/classify-no-fire-ack-checked-zero-yields-medium ()
  "T1.5b PR 2 — when AFTER's panopticon focus probe is `ok' and
no focus segment starts after the emit, `:ignored' confidence
ratchets up to `:medium'."
  (satan-observer-test--in-tmp
   (lambda (root)
     (let* ((dir (expand-file-name "20260522T100000-tick-aaa" root))
            (baseline-ev
             (list :git_state (list :head_short "aaaaaaa" :remote "r")
                   :fs_state (list :cwd satan-observer-test--cwd
                                   :recent_files nil)
                   :focus_segments nil :bough_recent nil))
            (after-ev
             (list :git_state (list :head_short "aaaaaaa" :remote "r")
                   :fs_state (list :cwd satan-observer-test--cwd
                                   :recent_files nil)
                   :focus_segments nil
                   :bough_recent nil
                   :sensor_status (list :focus 'ok)))
            (motive (satan-observer-test--motive))
            (iv (plist-put (satan-observer-test--intervention)
                           :run_dir dir)))
       (satan-observer-test--write-bundle
        dir (list :percept (list :evidence_window baseline-ev)))
       (satan-observer-test--with-stubbed-after-state after-ev
         (let* ((out (satan-observer-classify iv motive))
                (ev (plist-get out :evidence)))
           (should (eq :ignored (plist-get out :classification)))
           (should (eq :medium (plist-get out :confidence)))
           (should (eq t (plist-get ev :acknowledgement-checked)))
           (should (= 0 (plist-get ev :ack-events-found)))))))))

(ert-deftest satan-observer/classify-no-fire-ack-checked-found-yields-unknown ()
  "T1.5b PR 2 — user-facing intervention with ≥1 focus segment
starting after the emit puts the verdict outside the `:ignored'
gate (per outcome-semantics §1).  Result: `:unknown :low' with
`:reason nil' — v1 punts rather than extending the reason
vocabulary."
  (satan-observer-test--in-tmp
   (lambda (root)
     (let* ((dir (expand-file-name "20260522T100000-tick-aaa" root))
            (baseline-ev
             (list :git_state (list :head_short "aaaaaaa" :remote "r")
                   :fs_state (list :cwd satan-observer-test--cwd
                                   :recent_files nil)
                   :focus_segments nil :bough_recent nil))
            (after-ev
             (list :git_state (list :head_short "aaaaaaa" :remote "r")
                   :fs_state (list :cwd satan-observer-test--cwd
                                   :recent_files nil)
                   :focus_segments
                   (list (list :app_id "firefox"
                               :start_ts "2026-05-22T10:05:00+1000"))
                   :bough_recent nil
                   :sensor_status (list :focus 'ok)))
            (motive (satan-observer-test--motive))
            (iv (plist-put (satan-observer-test--intervention)
                           :run_dir dir)))
       (satan-observer-test--write-bundle
        dir (list :percept (list :evidence_window baseline-ev)))
       (satan-observer-test--with-stubbed-after-state after-ev
         (let ((out (satan-observer-classify iv motive)))
           (should (eq :unknown (plist-get out :classification)))
           (should (eq :low (plist-get out :confidence)))
           (should (null (plist-get out :reason)))))))))

(ert-deftest satan-observer/classify-a12-fs-coincidence-does-not-fire ()
  "A12 — recent_files delta outside `:project_cwd' must not fire P3.
PR 2: the no-fire fallback for the default user-facing fixture
is now `:ignored', not `:unknown'."
  (satan-observer-test--in-tmp
   (lambda (root)
     (let* ((dir (expand-file-name "20260522T100000-tick-aaa" root))
            (baseline-ev
             (list :git_state (list :head_short "aaaaaaa" :remote "r")
                   :fs_state (list :cwd "/other/repo" :recent_files nil)
                   :focus_segments nil :bough_recent nil))
            (after-ev
             (list :git_state (list :head_short "aaaaaaa" :remote "r")
                   :fs_state (list :cwd "/other/repo"
                                   :recent_files (list "noise.el"))
                   :focus_segments nil :bough_recent nil))
            (motive (satan-observer-test--motive))
            (iv (plist-put (satan-observer-test--intervention)
                           :run_dir dir)))
       (satan-observer-test--write-bundle
        dir (list :percept (list :evidence_window baseline-ev)))
       (satan-observer-test--with-stubbed-after-state after-ev
         (let ((out (satan-observer-classify iv motive)))
           (should (eq :ignored (plist-get out :classification)))
           (should (null (plist-get out :predicates)))))))))

;; ---------------------------------------------------------------------
;; Phase 5.7 — multi-motive resolver (overlap + file-order tiebreak)
;; ---------------------------------------------------------------------

(ert-deftest satan-observer/rank-empty-percept-handles-no-matches ()
  (let ((motives (list (list :id "m1" :cue (list "app:firefox")))))
    (should (null (satan-observer--rank-motives-by-overlap motives nil)))))

(ert-deftest satan-observer/rank-highest-overlap-wins ()
  (let* ((motives (list (list :id "low"
                              :cue (list "app:firefox"))
                        (list :id "high"
                              :cue (list "app:firefox" "domain_kind:docs"
                                         "topic:satan"))))
         (handles (list "app:firefox" "domain_kind:docs" "topic:satan"))
         (ranked (satan-observer--rank-motives-by-overlap motives handles)))
    (should (= 2 (length ranked)))
    (should (equal "high" (plist-get (plist-get (car ranked) :motive) :id)))
    (should (= 3 (plist-get (car ranked) :overlap)))))

(ert-deftest satan-observer/rank-tie-broken-by-file-order ()
  (let* ((motives (list (list :id "first"  :cue (list "app:firefox"))
                        (list :id "second" :cue (list "app:firefox"))))
         (handles (list "app:firefox"))
         (ranked (satan-observer--rank-motives-by-overlap motives handles)))
    (should (equal "first" (plist-get (plist-get (car ranked) :motive) :id)))))

(ert-deftest satan-observer/rank-skips-dormant-motives ()
  (let* ((motives (list (list :id "dormant"
                              :cue (list "app:firefox" "domain_kind:docs")
                              :dormant t)
                        (list :id "active"
                              :cue (list "app:firefox"))))
         (handles (list "app:firefox" "domain_kind:docs"))
         (ranked (satan-observer--rank-motives-by-overlap motives handles)))
    (should (= 1 (length ranked)))
    (should (equal "active" (plist-get (plist-get (car ranked) :motive) :id)))))

(ert-deftest satan-observer/rank-drops-zero-overlap ()
  (let* ((motives (list (list :id "no-overlap"
                              :cue (list "topic:other"))))
         (handles (list "app:firefox")))
    (should (null (satan-observer--rank-motives-by-overlap
                   motives handles)))))

(ert-deftest satan-observer/classify-for-motives-no-bundle-no-correlation ()
  (satan-observer-test--in-tmp
   (lambda (root)
     (let* ((dir (expand-file-name "20260522T100000-tick-aaa" root))
            (_ (make-directory dir t))
            (iv (plist-put (satan-observer-test--intervention)
                           :run_dir dir))
            (motives (list (list :id "m" :cue (list "app:firefox"))))
            (out (satan-observer-classify-for-motives iv motives)))
       (should (null (plist-get out :motive_id)))
       (should (eq :unknown (plist-get out :classification)))
       (should (eq :low (plist-get out :confidence)))
       (should (eq :no_correlation (plist-get out :reason)))))))

(ert-deftest satan-observer/classify-for-motives-no-overlap-no-correlation ()
  (satan-observer-test--in-tmp
   (lambda (root)
     (let* ((dir (expand-file-name "20260522T100000-tick-aaa" root))
            (_ (satan-observer-test--write-bundle-with-handles
                dir (list "app:slack")))
            (iv (plist-put (satan-observer-test--intervention)
                           :run_dir dir))
            (motives (list (list :id "m" :cue (list "app:firefox"))))
            (out (satan-observer-classify-for-motives iv motives)))
       (should (eq :unknown (plist-get out :classification)))
       (should (eq :no_correlation (plist-get out :reason)))))))

(ert-deftest satan-observer/classify-for-motives-picks-best-and-classifies ()
  (satan-observer-test--in-tmp
   (lambda (root)
     (let* ((dir (expand-file-name "20260522T100000-tick-aaa" root))
            (baseline-ev
             (list :git_state (list :head_short "aaaaaaa" :remote "r")
                   :fs_state (list :cwd "/x" :recent_files nil)
                   :focus_segments nil :bough_recent nil))
            (_ (satan-observer-test--write-bundle
                dir (list :percept
                          (list :handles (list "app:firefox"
                                               "domain_kind:docs"
                                               "topic:satan")
                                :evidence_window baseline-ev))))
            (iv (plist-put (satan-observer-test--intervention)
                           :run_dir dir))
            (motives
             (list (list :id "weak" :cue (list "app:firefox"))
                   (list :id "strong"
                         :project_cwd "/x"
                         :cue (list "app:firefox"
                                    "domain_kind:docs"
                                    "topic:satan")))))
       (satan-observer-test--with-stubbed-after-state
           (list :git_commits
                 (list (list :repo "/x"
                             :slug "x"
                             :sha "bbbbbbb"
                             :end_ts "2026-05-22T10:15:00+1000"))
                 :fs_state (list :cwd "/x" :recent_files nil)
                 :focus_segments nil :bough_recent nil)
         (let ((out (satan-observer-classify-for-motives iv motives)))
           (should (equal "strong" (plist-get out :motive_id)))
           (should (eq :worked (plist-get out :classification)))
           (should (eq :medium (plist-get out :confidence)))
           (should (equal '(:git_commit_observed)
                          (plist-get out :predicates)))))))))

(ert-deftest satan-observer/classify-for-motives-tie-file-order ()
  "Tie-broken winner runs through classify; default fixture kind is
user-facing so the no-fire fallback now lands on `:ignored'
(PR 2)."
  (satan-observer-test--in-tmp
   (lambda (root)
     (let* ((dir (expand-file-name "20260522T100000-tick-aaa" root))
            (_ (satan-observer-test--write-bundle-with-handles
                dir (list "app:firefox")))
            (iv (plist-put (satan-observer-test--intervention)
                           :run_dir dir))
            (motives (list (list :id "first"  :cue (list "app:firefox"))
                           (list :id "second" :cue (list "app:firefox")))))
       (satan-observer-test--with-stubbed-after-state
           (list :git_state nil :fs_state nil
                 :focus_segments nil :bough_recent nil)
         (let ((out (satan-observer-classify-for-motives iv motives)))
           (should (equal "first" (plist-get out :motive_id)))
           (should (eq :ignored (plist-get out :classification)))))))))

;; ---------------------------------------------------------------------
;; T7 PR 5 — read path: satan-observer-pending wraps the projection
;; ---------------------------------------------------------------------

(ert-deftest satan-observer/pending-returns-classifier-shape ()
  "Projection rows come back enriched with `:run_dir' (resolved under
the runs root via `satan-broker-locate-run-dir'),
`:intervention_emitted_at' (mirrors `:ts'), and `:applied_index'
(derived from the `ivNNN' suffix)."
  (satan-observer-test--with-db
   (satan-observer-test--in-tmp
    (lambda (root)
      (let* ((satan-runs-dir root)
             (run-id "20260523T120000-morning-aaaaaa")
             (audit (satan-observer-test--open-audit root run-id))
             (ctx (satan-observer-test--build-ctx
                   audit run-id "2026-05-23T11:00:00+1000"))
             (iv-id (satan-observer-test--mint ctx)))
        (let* ((pending (satan-observer-pending
                         "2026-05-23T12:00:00+1000" root))
               (only (car pending)))
          (should (= 1 (length pending)))
          (should (equal iv-id (plist-get only :intervention_id)))
          (should (equal run-id (plist-get only :run_id)))
          ;; Postgres normalises timestamptz to UTC text on read; the
          ;; mapping mirrors :ts into :intervention_emitted_at, so the
          ;; two slots must agree even though the wire format differs
          ;; from the original input string.
          (should (stringp (plist-get only :ts)))
          (should (equal (plist-get only :ts)
                         (plist-get only :intervention_emitted_at)))
          (should (= 1 (plist-get only :applied_index)))
          (let ((run-dir (plist-get only :run_dir)))
            (should run-dir)
            (should (file-directory-p run-dir)))))))))

(ert-deftest satan-observer/pending-skips-immature-and-classified ()
  "Pending excludes interventions whose window hasn't elapsed yet AND
interventions that already carry an outcome row."
  (satan-observer-test--with-db
   (satan-observer-test--in-tmp
    (lambda (root)
      (let* ((satan-runs-dir root)
             (old-id "20260523T110000-morning-aaaaaa")
             (new-id "20260523T120000-morning-bbbbbb")
             (audit-old (satan-observer-test--open-audit root old-id))
             (audit-new (satan-observer-test--open-audit root new-id))
             (ctx-old (satan-observer-test--build-ctx
                       audit-old old-id "2026-05-23T11:00:00+1000"))
             (ctx-new (satan-observer-test--build-ctx
                       audit-new new-id "2026-05-23T12:00:00+1000"))
             (iv-old (satan-observer-test--mint ctx-old))
             (_iv-new (satan-observer-test--mint ctx-new))
             (now "2026-05-23T11:45:00+1000"))
        (let ((pending (satan-observer-pending now root)))
          (should (= 1 (length pending)))
          (should (equal iv-old (plist-get (car pending) :intervention_id))))
        ;; classify the old one → drops from pending
        (satan-intervention-classify
         :ctx ctx-old :intervention-id iv-old
         :classification "unknown" :confidence "low"
         :evidence '(:source_events ())
         :maturity "mature"
         :next-revisit-at "2026-05-23T11:30:00+1000"
         :source "auto"
         :classified-at "2026-05-23T11:30:01+1000")
        (should-not (satan-observer-pending now root)))))))

;; ---------------------------------------------------------------------
;; T7 PR 5 — persist-verdict writes through satan-intervention-classify
;; ---------------------------------------------------------------------

(ert-deftest satan-observer/persist-positive-bumps-motive-and-classifies ()
  "Positive verdict: motive bumped, trace written, outcome row UPSERTed
with classification=worked and confidence=medium (single-predicate)."
  (satan-observer-test--with-db
   (satan-observer-test--in-tmp
    (lambda (root)
      (let* ((satan-runs-dir root)
             (run-id "20260523T110000-morning-aaaaaa")
             (audit (satan-observer-test--open-audit root run-id))
             (ctx (satan-observer-test--build-ctx
                   audit run-id "2026-05-23T11:00:00+1000"))
             (iv-id (satan-observer-test--mint
                     ctx :related-motive-id "docs-after-error")))
        (satan-motive-test--with-tmp-file
         mpath satan-motive-test--well-formed
         (satan-observer-test--capture-mark captured
           (let* ((iv (car (satan-observer-pending
                            "2026-05-23T12:00:00+1000" root)))
                  (motive (satan-observer-test--full-motive
                           :worked_count 0))
                  (verdict (satan-observer-test--positive-verdict
                            :git_commit_observed))
                  (out (satan-observer-persist-verdict
                        iv motive verdict "2026-05-23T12:00:00+1000"
                        (list :ctx ctx
                              :motive-path mpath
                              :memory-mark-fn mark-fn))))
             (should (equal "intervention.outcome_classified"
                            (plist-get out :classify_event)))
             (should (plist-get out :motive_written))
             (should (= 1 (plist-get out :new_worked_count)))
             (should (equal '(ok . "tid-stub")
                            (plist-get out :trace_result)))
             ;; Trace metadata carries intervention_id + motive_id +
             ;; predicates (list, T1.5b PR 1 widening).
             (let ((args (car captured)))
               (let ((md (plist-get args :metadata-json)))
                 (should (equal iv-id (plist-get md :intervention_id)))
                 (should (equal run-id (plist-get md :run_id)))
                 (should (equal "docs-after-error"
                                (plist-get md :motive_id)))
                 (should (equal '(:git_commit_observed)
                                (plist-get md :predicates)))
                 (should (eq :worked (plist-get md :classification)))
                 (should (eq :medium (plist-get md :confidence)))))
             ;; Projection now carries the worked outcome.
             (let* ((row (satan-intervention-lookup iv-id))
                    (oc (plist-get row :outcome)))
               (should oc)
               (should (equal "worked"  (plist-get oc :classification)))
               (should (equal "medium"  (plist-get oc :confidence)))
               (should (equal "mature"  (plist-get oc :maturity)))
               (should (equal "auto"    (plist-get oc :source))))))))))))

(ert-deftest satan-observer/persist-negative-classifies-unknown ()
  "Negative verdict in PR 5 maps to classification=unknown / confidence=low.
T1.5b widens this to ignored / neutral."
  (satan-observer-test--with-db
   (satan-observer-test--in-tmp
    (lambda (root)
      (let* ((satan-runs-dir root)
             (run-id "20260523T110000-morning-bbbbbb")
             (audit (satan-observer-test--open-audit root run-id))
             (ctx (satan-observer-test--build-ctx
                   audit run-id "2026-05-23T11:00:00+1000"))
             (iv-id (satan-observer-test--mint ctx)))
        (satan-motive-test--with-tmp-file
         mpath satan-motive-test--well-formed
         (satan-observer-test--capture-mark captured
           (let* ((iv (car (satan-observer-pending
                            "2026-05-23T12:00:00+1000" root)))
                  (motive (satan-observer-test--full-motive))
                  (verdict (satan-observer-test--negative-verdict
                            :no_correlation))
                  (before (with-temp-buffer
                            (insert-file-contents mpath)
                            (buffer-string)))
                  (out (satan-observer-persist-verdict
                        iv motive verdict "2026-05-23T12:00:00+1000"
                        (list :ctx ctx
                              :motive-path mpath
                              :memory-mark-fn mark-fn))))
             (should (equal "intervention.outcome_classified"
                            (plist-get out :classify_event)))
             (should-not (plist-get out :motive_written))
             (should-not (plist-get out :trace_result))
             (should (null captured))
             (should (equal before
                            (with-temp-buffer
                              (insert-file-contents mpath)
                              (buffer-string))))
             (let* ((row (satan-intervention-lookup iv-id))
                    (oc (plist-get row :outcome)))
               (should oc)
               (should (equal "unknown" (plist-get oc :classification)))
               (should (equal "low"     (plist-get oc :confidence))))))))))))

(ert-deftest satan-observer/persist-ignored-classifies-ignored ()
  "T1.5b PR 2 — `:ignored' verdict UPSERTs classification=\"ignored\"
with evidence carrying target_surface + ack_events_found in
snake_case (per outcome-semantics §9)."
  (satan-observer-test--with-db
   (satan-observer-test--in-tmp
    (lambda (root)
      (let* ((satan-runs-dir root)
             (run-id "20260523T110000-morning-ignr01")
             (audit (satan-observer-test--open-audit root run-id))
             (ctx (satan-observer-test--build-ctx
                   audit run-id "2026-05-23T11:00:00+1000"))
             (iv-id (satan-observer-test--mint ctx)))
        (satan-motive-test--with-tmp-file
         mpath satan-motive-test--well-formed
         (satan-observer-test--capture-mark captured
           (let* ((iv (car (satan-observer-pending
                            "2026-05-23T12:00:00+1000" root)))
                  (motive (satan-observer-test--full-motive))
                  (verdict (satan-observer-test--ignored-verdict
                            :confidence :medium
                            :acknowledgement-checked t))
                  (out (satan-observer-persist-verdict
                        iv motive verdict "2026-05-23T12:00:00+1000"
                        (list :ctx ctx
                              :motive-path mpath
                              :memory-mark-fn mark-fn))))
             (should (equal "intervention.outcome_classified"
                            (plist-get out :classify_event)))
             (should-not (plist-get out :motive_written))
             (should-not (plist-get out :trace_result))
             (should (null captured))
             (let* ((row (satan-intervention-lookup iv-id))
                    (oc (plist-get row :outcome))
                    (ev (plist-get oc :evidence)))
               (should oc)
               (should (equal "ignored" (plist-get oc :classification)))
               (should (equal "medium"  (plist-get oc :confidence)))
               (should (equal "sway-mainbar"
                              (plist-get ev :target_surface)))
               (should (eq t (plist-get ev :no_positive_predicates)))
               (should (eq t (plist-get ev :acknowledgement_checked)))
               (should (= 0 (plist-get ev :ack_events_found))))))))))))

(ert-deftest satan-observer/persist-neutral-classifies-neutral ()
  "T1.5b PR 2 — `:neutral' verdict UPSERTs classification=\"neutral\"
with bare target_surface evidence."
  (satan-observer-test--with-db
   (satan-observer-test--in-tmp
    (lambda (root)
      (let* ((satan-runs-dir root)
             (run-id "20260523T110000-morning-neut01")
             (audit (satan-observer-test--open-audit root run-id))
             (ctx (satan-observer-test--build-ctx
                   audit run-id "2026-05-23T11:00:00+1000"))
             ;; Non-user-facing kind — `delay' is not in
             ;; `satan-observer-user-facing-kinds'.
             (iv-id (satan-observer-test--mint
                     ctx :kind "delay" :target "internal")))
        (satan-motive-test--with-tmp-file
         mpath satan-motive-test--well-formed
         (satan-observer-test--capture-mark captured
           (let* ((iv (car (satan-observer-pending
                            "2026-05-23T12:00:00+1000" root)))
                  (motive (satan-observer-test--full-motive))
                  (verdict (satan-observer-test--neutral-verdict
                            "internal"))
                  (out (satan-observer-persist-verdict
                        iv motive verdict "2026-05-23T12:00:00+1000"
                        (list :ctx ctx
                              :motive-path mpath
                              :memory-mark-fn mark-fn))))
             (should (equal "intervention.outcome_classified"
                            (plist-get out :classify_event)))
             (should-not (plist-get out :motive_written))
             (should-not (plist-get out :trace_result))
             (should (null captured))
             (let* ((row (satan-intervention-lookup iv-id))
                    (oc (plist-get row :outcome))
                    (ev (plist-get oc :evidence)))
               (should oc)
               (should (equal "neutral" (plist-get oc :classification)))
               (should (equal "low"     (plist-get oc :confidence)))
               (should (equal "internal"
                              (plist-get ev :target_surface)))
               (should (eq t (plist-get ev :no_positive_predicates))))))))))))

(ert-deftest satan-observer/classify-auto-rejects-harmful ()
  "T1.5b PR 2 — `:harmful' / `:contradicted' are manual-only.
The classifier API guards against accidental construction via
`cl-check-type'; constructing a verdict with `:harmful' and
running it through the assert helper signals."
  (should-error
   (satan-observer--assert-auto-classification
    (list :classification :harmful))
   :type 'wrong-type-argument)
  (should-error
   (satan-observer--assert-auto-classification
    (list :classification :contradicted))
   :type 'wrong-type-argument))

(ert-deftest satan-observer/persist-twice-emits-revised ()
  "A second persist for the same intervention surfaces as
`outcome_revised' because `satan-intervention-classify' auto-detects
the prior verdict in the projection."
  (satan-observer-test--with-db
   (satan-observer-test--in-tmp
    (lambda (root)
      (let* ((satan-runs-dir root)
             (run-id "20260523T110000-morning-cccccc")
             (audit (satan-observer-test--open-audit root run-id))
             (ctx (satan-observer-test--build-ctx
                   audit run-id "2026-05-23T11:00:00+1000"))
             (iv-id (satan-observer-test--mint ctx)))
        (satan-motive-test--with-tmp-file
         mpath satan-motive-test--well-formed
         (satan-observer-test--capture-mark _captured
           (let ((iv (car (satan-observer-pending
                           "2026-05-23T12:00:00+1000" root)))
                 (motive (satan-observer-test--full-motive)))
             (should (equal "intervention.outcome_classified"
                            (plist-get
                             (satan-observer-persist-verdict
                              iv motive
                              (satan-observer-test--negative-verdict)
                              "2026-05-23T12:00:00+1000"
                              (list :ctx ctx :motive-path mpath
                                    :memory-mark-fn mark-fn))
                             :classify_event)))
             (should (equal "intervention.outcome_revised"
                            (plist-get
                             (satan-observer-persist-verdict
                              iv motive
                              (satan-observer-test--positive-verdict)
                              "2026-05-23T12:05:00+1000"
                              (list :ctx ctx :motive-path mpath
                                    :memory-mark-fn mark-fn))
                             :classify_event)))
             (let* ((row (satan-intervention-lookup iv-id))
                    (oc (plist-get row :outcome)))
               (should (equal "worked"  (plist-get oc :classification)))
               (should (equal iv-id     (plist-get oc :revises))))))))))))

;; ---------------------------------------------------------------------
;; T7 PR 5 — observer-process end-to-end
;; ---------------------------------------------------------------------

(ert-deftest satan-observer/process-empty-pending-yields-zero ()
  (satan-observer-test--with-db
   (satan-observer-test--in-tmp
    (lambda (root)
      (satan-motive-test--with-tmp-file
       mpath satan-motive-test--well-formed
       (let ((out (satan-observer-process
                   (list :time_now "2026-05-23T12:00:00+1000"
                         :run_id "20260523T120000-morning-zzzzzz"
                         :mode_name "morning"
                         :audit (satan-observer-test--open-audit
                                 root "20260523T120000-morning-zzzzzz"))
                   (list :motive-path mpath
                         :runs-dir root))))
         (should (= 0 (plist-get out :processed)))
         (should (= 0 (plist-get out :positive)))
         (should (null (plist-get out :verdicts)))))))))

(ert-deftest satan-observer/process-no-correlation-classifies-unknown ()
  "Pending intervention exists but no motive cue overlaps; PR 5 still
commits a verdict (unknown / no_correlation) so the next tick's pending
no longer surfaces the same intervention."
  (satan-observer-test--with-db
   (satan-observer-test--in-tmp
    (lambda (root)
      (let* ((satan-runs-dir root)
             (old-id "20260523T110000-morning-aaaaaa")
             (audit-old (satan-observer-test--open-audit root old-id))
             (ctx-old (satan-observer-test--build-ctx
                       audit-old old-id "2026-05-23T11:00:00+1000")))
        (satan-observer-test--mint ctx-old)
        ;; Bundle in the prior run with handles that won't overlap any motive.
        (satan-observer-test--write-bundle-with-handles
         (satan-observer-test--make-run-dir root old-id)
         (list "topic:nothing-matches"))
        (satan-motive-test--with-tmp-file
         mpath ""
         (let ((now "2026-05-23T12:00:00+1000")
               (curr-id "20260523T120000-morning-cccccc"))
           (let ((out (satan-observer-process
                       (list :time_now now
                             :run_id curr-id
                             :mode_name "morning"
                             :audit (satan-observer-test--open-audit
                                     root curr-id))
                       (list :motive-path mpath
                             :runs-dir root))))
             (should (= 1 (plist-get out :processed)))
             (should (= 0 (plist-get out :positive)))
             (let ((v (car (plist-get out :verdicts))))
               (should (null (plist-get v :motive_id)))
               (should (eq :unknown (plist-get v :classification)))
               (should (eq :low (plist-get v :confidence)))
               (should (eq :no_correlation (plist-get v :reason)))
               (should (equal "intervention.outcome_classified"
                              (plist-get v :classify_event)))))
           ;; second pass: now matured + classified → empty pending
           (let* ((curr2-id "20260523T120500-morning-dddddd")
                  (out2 (satan-observer-process
                         (list :time_now now
                               :run_id curr2-id
                               :mode_name "morning"
                               :audit (satan-observer-test--open-audit
                                       root curr2-id))
                         (list :motive-path mpath
                               :runs-dir root))))
             (should (= 0 (plist-get out2 :processed)))))))))))

(ert-deftest satan-observer/process-classifies-hours-after-emit ()
  "End-to-end guard — a real DB-sourced intervention (whose `:ts'
arrives in `psql -A' space-form via `satan-intervention-pending')
classifies hours after emit instead of skipping as `:stale'.

Forward guard for the cold-pipeline bug: the space-form `timestamptz'
(`YYYY-MM-DD HH:MM:SS+00') is unparseable by `date-to-time' until
`--row-to-intervention' normalizes it.  The reliably-red unit for that
mis-parse is `satan-intervention/row-to-intervention-ts-parses'
(the mis-parse offset is data-dependent, so it does not always cross
the 24 h staleness boundary at the observer level); this test instead
locks the full pending → classify path on the realistic wire shape."
  (satan-observer-test--with-db
   (satan-observer-test--in-tmp
    (lambda (root)
      (let* ((satan-runs-dir root)
             (old-id "20260523T110000-morning-aaaaaa")
             (audit-old (satan-observer-test--open-audit root old-id))
             (ctx-old (satan-observer-test--build-ctx
                       audit-old old-id "2026-05-23T11:00:00+1000")))
        (satan-observer-test--mint ctx-old)
        (satan-observer-test--write-bundle-with-handles
         (satan-observer-test--make-run-dir root old-id)
         (list "topic:nothing-matches"))
        (satan-motive-test--with-tmp-file
         mpath ""
         (let* ((now "2026-05-23T17:00:00+1000") ; emit + 6 h, window open until 05-24 11:30
                (curr-id "20260523T170000-morning-cccccc")
                (out (satan-observer-process
                      (list :time_now now
                            :run_id curr-id
                            :mode_name "morning"
                            :audit (satan-observer-test--open-audit
                                    root curr-id))
                      (list :motive-path mpath :runs-dir root))))
           (should (= 1 (plist-get out :processed)))
           (let ((v (car (plist-get out :verdicts))))
             ;; classified — NOT skipped stale
             (should-not (plist-get v :skipped))
             (should (eq :unknown (plist-get v :classification)))
             (should (eq :no_correlation (plist-get v :reason)))
             (should (eq :mature (plist-get v :maturity)))))))))))

(ert-deftest satan-observer/process-positive-bumps-motive-and-projects ()
  "End-to-end positive verdict — bundle handles overlap a motive's cue
and git head changed; motive footer bumps, projection holds worked."
  (satan-observer-test--with-db
   (satan-observer-test--in-tmp
    (lambda (root)
      (let* ((satan-runs-dir root)
             (old-id "20260523T110000-morning-aaaaaa")
             (audit-old (satan-observer-test--open-audit root old-id))
             (ctx-old (satan-observer-test--build-ctx
                       audit-old old-id "2026-05-23T11:00:00+1000"))
             (iv-id (satan-observer-test--mint
                     ctx-old :related-motive-id "docs-after-error")))
        ;; Write the prior run's bundle with handles that match
        ;; docs-after-error's :cue exactly.
        (let* ((baseline-ev
                (list :git_state (list :head_short "aaaaaaa" :remote "r")
                      :fs_state (list :cwd "/x" :recent_files nil)
                      :focus_segments nil :bough_recent nil))
               (prior-run-dir (satan-observer-test--make-run-dir
                               root old-id)))
          (satan-observer-test--write-bundle
           prior-run-dir
           (list :percept
                 (list :handles
                       (list "project:emacs.d"
                             "surface_transition:terminal->browser"
                             "domain_kind:docs")
                       :evidence_window baseline-ev))))
        (satan-motive-test--with-tmp-file
         mpath satan-motive-test--well-formed-cwd
         (satan-observer-test--capture-mark captured
           (satan-observer-test--with-stubbed-after-state
               (list :git_commits
                     (list (list :repo "/x" :slug "emacs.d"
                                 :sha "deadbeef"
                                 :end_ts "2026-05-23T11:15:00+1000"))
                     :fs_state (list :cwd "/x" :recent_files nil)
                     :focus_segments nil :bough_recent nil)
             (let* ((curr-id "20260523T120000-morning-cccccc")
                    (out (satan-observer-process
                          (list :time_now "2026-05-23T12:00:00+1000"
                                :run_id curr-id
                                :mode_name "morning"
                                :audit (satan-observer-test--open-audit
                                        root curr-id))
                          (list :motive-path mpath
                                :runs-dir root
                                :memory-mark-fn mark-fn))))
               (should (= 1 (plist-get out :processed)))
               (should (= 1 (plist-get out :positive)))
               (let ((v (car (plist-get out :verdicts))))
                 (should (equal iv-id (plist-get v :intervention_id)))
                 (should (equal "docs-after-error"
                                (plist-get v :motive_id)))
                 (should (eq :worked (plist-get v :classification)))
                 (should (eq :medium (plist-get v :confidence)))
                 (should (equal '(:git_commit_observed)
                                (plist-get v :predicates))))
               ;; Trace written.
               (should (= 1 (length captured)))
               ;; Motive footer bumped 0 → 1.
               (let* ((parsed (satan-motive-parse
                               (satan-motive-test--read mpath)))
                      (target (cl-find "docs-after-error"
                                       (plist-get parsed :motives)
                                       :key (lambda (m)
                                              (plist-get m :id))
                                       :test #'equal)))
                 (should (= 1 (plist-get target :worked_count))))
               ;; Projection.
               (let* ((row (satan-intervention-lookup iv-id))
                      (oc (plist-get row :outcome)))
                 (should (equal "worked" (plist-get oc :classification)))))))))))))

(ert-deftest satan-observer/process-error-on-one-iv-does-not-abort ()
  "If one intervention's persist signals, the loop captures the error
and continues with the next."
  (satan-observer-test--with-db
   (satan-observer-test--in-tmp
    (lambda (root)
      (let* ((satan-runs-dir root)
             (id1 "20260523T110000-morning-aaaaaa")
             (id2 "20260523T110100-morning-bbbbbb")
             (audit1 (satan-observer-test--open-audit root id1))
             (audit2 (satan-observer-test--open-audit root id2))
             (ctx1 (satan-observer-test--build-ctx
                    audit1 id1 "2026-05-23T11:00:00+1000"))
             (ctx2 (satan-observer-test--build-ctx
                    audit2 id2 "2026-05-23T11:01:00+1000")))
        (satan-observer-test--mint
         ctx1 :related-motive-id "docs-after-error")
        (satan-observer-test--mint
         ctx2 :related-motive-id "docs-after-error")
        (satan-observer-test--write-bundle-with-handles
         (satan-observer-test--make-run-dir root id1)
         (list "project:emacs.d"
               "surface_transition:terminal->browser"
               "domain_kind:docs"))
        (satan-observer-test--write-bundle-with-handles
         (satan-observer-test--make-run-dir root id2)
         (list "project:emacs.d"
               "surface_transition:terminal->browser"
               "domain_kind:docs"))
        (satan-motive-test--with-tmp-file
         mpath satan-motive-test--well-formed-cwd
         (let* ((call-count 0)
                (failing-touch
                 (lambda (&rest _args)
                   (setq call-count (1+ call-count))
                   (if (= call-count 1)
                       (error "synthetic touch failure")
                     t)))
                (mark-fn (lambda (&rest _args) (cons 'ok "tid"))))
           (satan-observer-test--with-stubbed-after-state
               (list :git_commits
                     (list (list :repo "/x" :slug "emacs.d"
                                 :sha "deadbeef"
                                 :end_ts "2026-05-23T11:15:00+1000"))
                     :fs_state (list :cwd "/x" :recent_files nil)
                     :focus_segments nil :bough_recent nil)
             (let* ((curr-id "20260523T120000-morning-cccccc")
                    (out (satan-observer-process
                          (list :time_now "2026-05-23T12:00:00+1000"
                                :run_id curr-id
                                :mode_name "morning"
                                :audit (satan-observer-test--open-audit
                                        root curr-id))
                          (list :motive-path mpath
                                :runs-dir root
                                :touch-footer-fn failing-touch
                                :memory-mark-fn mark-fn))))
               (should (= 2 (plist-get out :processed)))
               (let ((errors (cl-remove-if-not
                              (lambda (v) (plist-get v :error))
                              (plist-get out :verdicts))))
                 (should (= 1 (length errors)))))))))))))

;; ---------------------------------------------------------------------
;; T1.5b PR 3 — lifecycle (maturity-state + pending/stale dispatch)
;; ---------------------------------------------------------------------

(defconst satan-observer-test--pr3-iv-ts "2026-05-23T10:00:00+1000"
  "Created-at for PR 3 maturity-state ert; default window 30 min so
mature opens at 10:30 and stale opens at 10:30 + 24 h.")

(defun satan-observer-test--pr3-iv (&rest overrides)
  "Classifier-shaped plist with PR 3 maturity slots (`:ts',
`:outcome_window_minutes', `:intervention_emitted_at') seeded."
  (let ((base (list :ts satan-observer-test--pr3-iv-ts
                    :outcome_window_minutes 30
                    :intervention_emitted_at satan-observer-test--pr3-iv-ts
                    :kind "notify"
                    :target_surface "sway-mainbar")))
    (while overrides
      (setq base (plist-put base (pop overrides) (pop overrides))))
    base))

(ert-deftest satan-observer/maturity-state-pending ()
  "PR 3 — NOW before window close → `:pending'."
  (let ((iv (satan-observer-test--pr3-iv)))
    (should (eq :pending
                (satan-observer--maturity-state
                 iv "2026-05-23T10:15:00+1000")))))

(ert-deftest satan-observer/maturity-state-mature-at-boundary ()
  "PR 3 — NOW exactly at window close → `:mature' (inclusive lower
bound, matching the pending SQL filter)."
  (let ((iv (satan-observer-test--pr3-iv)))
    (should (eq :mature
                (satan-observer--maturity-state
                 iv "2026-05-23T10:30:00+1000")))))

(ert-deftest satan-observer/maturity-state-mature-inside-24h ()
  (let ((iv (satan-observer-test--pr3-iv)))
    (should (eq :mature
                (satan-observer--maturity-state
                 iv "2026-05-24T10:00:00+1000")))))

(ert-deftest satan-observer/maturity-state-stale ()
  "PR 3 — NOW past mature + 24 h → `:stale'."
  (let ((iv (satan-observer-test--pr3-iv)))
    (should (eq :stale
                (satan-observer--maturity-state
                 iv "2026-05-24T10:30:01+1000")))))

(ert-deftest satan-observer/classify-pending-short-circuits ()
  "PR 3 — classify with NOW inside pending window emits
`:unknown :pending'; does not consult motive / baseline / predicates."
  (let* ((motive (satan-observer-test--motive))
         (iv (satan-observer-test--pr3-iv))
         (out (satan-observer-classify
               iv motive "2026-05-23T10:15:00+1000")))
    (should (eq :unknown (plist-get out :classification)))
    (should (eq :low (plist-get out :confidence)))
    (should (eq :pending (plist-get out :reason)))
    (should (eq :pending (plist-get out :maturity)))))

(ert-deftest satan-observer/classify-stale-returns-nil ()
  "PR 3 — classify with NOW past `:stale' cutoff returns nil; caller
skips persist (auto re-pass forbidden, §6.3)."
  (let* ((motive (satan-observer-test--motive))
         (iv (satan-observer-test--pr3-iv)))
    (should (null (satan-observer-classify
                   iv motive "2026-05-24T10:30:01+1000")))))

(ert-deftest satan-observer/classify-mature-injects-maturity ()
  "PR 3 — every `:mature' verdict carries `:maturity :mature'."
  (satan-observer-test--in-tmp
   (lambda (root)
     (let* ((dir (expand-file-name "20260523T100000-tick-aaa" root))
            (baseline-ev
             (list :fs_state (list :cwd satan-observer-test--cwd
                                   :recent_files nil)
                   :focus_segments nil :bough_recent nil))
            (after-ev
             (list :git_commits
                   (list (list :repo satan-observer-test--cwd
                               :slug "satan-obs-proj"
                               :sha "bbbbbbb"
                               :end_ts "2026-05-23T10:15:00+1000"))
                   :fs_state (list :cwd satan-observer-test--cwd
                                   :recent_files nil)
                   :focus_segments nil :bough_recent nil))
            (motive (satan-observer-test--motive))
            (iv (plist-put (satan-observer-test--pr3-iv)
                           :run_dir dir)))
       (satan-observer-test--write-bundle
        dir (list :percept (list :evidence_window baseline-ev)))
       (satan-observer-test--with-stubbed-after-state after-ev
         (let ((out (satan-observer-classify
                     iv motive "2026-05-23T10:30:01+1000")))
           (should (eq :worked (plist-get out :classification)))
           (should (eq :mature (plist-get out :maturity)))))))))

(ert-deftest satan-observer/classify-without-now-defaults-mature ()
  "PR 3 backward-compat — NOW omitted → maturity check skipped, verdict
carries `:maturity :mature' so existing test fixtures keep working."
  (satan-observer-test--in-tmp
   (lambda (root)
     (let* ((dir (expand-file-name "20260522T100000-tick-aaa" root))
            (_ (make-directory dir t))
            (motive (satan-observer-test--motive))
            (iv (plist-put (satan-observer-test--intervention)
                           :run_dir dir))
            (out (satan-observer-classify iv motive)))
       (should (eq :unknown (plist-get out :classification)))
       (should (eq :mature (plist-get out :maturity)))))))

(ert-deftest satan-observer/classify-for-motives-pending-skips-bundle ()
  "PR 3 — `:pending' in classify-for-motives returns the pending verdict
shape with `:motive_id nil' and does not read bundle.json (an
unreachable `:run_dir' would otherwise surface as nil handles, not
an error — but the branch must not invoke the helper at all)."
  (let* ((motives (list (list :id "m" :cue (list "app:firefox"))))
         (iv (satan-observer-test--pr3-iv :run_dir "/nonexistent"))
         (out (satan-observer-classify-for-motives
               iv motives "2026-05-23T10:15:00+1000")))
    (should (null (plist-get out :motive_id)))
    (should (eq :unknown (plist-get out :classification)))
    (should (eq :pending (plist-get out :reason)))
    (should (eq :pending (plist-get out :maturity)))))

(ert-deftest satan-observer/classify-for-motives-stale-returns-nil ()
  "PR 3 — `:stale' propagates through classify-for-motives as nil."
  (let ((motives (list (list :id "m" :cue (list "app:firefox"))))
        (iv (satan-observer-test--pr3-iv :run_dir "/nonexistent")))
    (should (null (satan-observer-classify-for-motives
                   iv motives "2026-05-24T10:30:01+1000")))))

(ert-deftest satan-observer/pending-sql-excludes-stale ()
  "PR 3 — pending SQL skips rows past `created_at + window + 24 h'.
Mint at 10:00 with the default 30-min window; NOW one minute past the
24 h cutoff ⇒ row already stale ⇒ empty pending result."
  (satan-observer-test--with-db
   (satan-observer-test--in-tmp
    (lambda (root)
      (let* ((satan-runs-dir root)
             (stale-id "20260522T100000-morning-stalee")
             (audit (satan-observer-test--open-audit root stale-id))
             (ctx (satan-observer-test--build-ctx
                   audit stale-id "2026-05-22T10:00:00+1000"))
             (_ (satan-observer-test--mint ctx))
             (now "2026-05-23T10:31:00+1000"))
        (should-not (satan-intervention-pending now)))))))

(ert-deftest satan-observer/persist-pending-writes-maturity-pending ()
  "PR 3 — verdict carrying `:maturity :pending' propagates to the
projection as `maturity = \"pending\"' (per outcome-semantics §9 +
audit validator §2 invariant 3)."
  (satan-observer-test--with-db
   (satan-observer-test--in-tmp
    (lambda (root)
      (let* ((satan-runs-dir root)
             (run-id "20260523T110000-morning-pndng1")
             (audit (satan-observer-test--open-audit root run-id))
             (ctx (satan-observer-test--build-ctx
                   audit run-id "2026-05-23T11:00:00+1000"))
             (iv-id (satan-observer-test--mint ctx)))
        (satan-motive-test--with-tmp-file
         mpath satan-motive-test--well-formed
         (satan-observer-test--capture-mark _captured
           (let* ((iv (car (satan-observer-pending
                            "2026-05-23T12:00:00+1000" root)))
                  (motive (satan-observer-test--full-motive))
                  (verdict (list :classification :unknown
                                 :confidence :low
                                 :predicates nil
                                 :reason :pending
                                 :maturity :pending))
                  (out (satan-observer-persist-verdict
                        iv motive verdict "2026-05-23T12:00:00+1000"
                        (list :ctx ctx
                              :motive-path mpath
                              :memory-mark-fn mark-fn))))
             (should (equal "intervention.outcome_classified"
                            (plist-get out :classify_event)))
             (let* ((row (satan-intervention-lookup iv-id))
                    (oc (plist-get row :outcome)))
               (should oc)
               (should (equal "unknown" (plist-get oc :classification)))
               (should (equal "pending" (plist-get oc :maturity))))))))))))

;; ---------------------------------------------------------------------
;; DE-009 P03 — VT-rebuild-guard
;; ---------------------------------------------------------------------

(ert-deftest satan-observer/rebuild-guard-swallows-rebuild-error ()
  "DR-009 §3.2 — a simulated rebuild failure is swallowed; the observer
returns a normal summary plist and classification + outcome projection
are intact."
  (satan-observer-test--with-db
   (satan-observer-test--in-tmp
    (lambda (root)
      (let* ((satan-runs-dir root)
             (old-id "20260523T110000-morning-aaaaaa")
             (audit-old (satan-observer-test--open-audit root old-id))
             (ctx-old (satan-observer-test--build-ctx
                       audit-old old-id "2026-05-23T11:00:00+1000"))
             (iv-id (satan-observer-test--mint
                     ctx-old :related-motive-id "docs-after-error")))
        ;; Bundle with handles matching the motive
        (let ((baseline-ev
               (list :git_state (list :head_short "aaaaaaa" :remote "r")
                     :fs_state (list :cwd "/x" :recent_files nil)
                     :focus_segments nil :bough_recent nil)))
          (satan-observer-test--write-bundle
           (satan-observer-test--make-run-dir root old-id)
           (list :percept
                 (list :handles
                       (list "project:emacs.d"
                             "surface_transition:terminal->browser"
                             "domain_kind:docs")
                       :evidence_window baseline-ev))))
        (satan-motive-test--with-tmp-file
         mpath satan-motive-test--well-formed-cwd
         (satan-observer-test--capture-mark _captured
           ;; Simulate rebuild failure
           (cl-letf (((symbol-function 'satan-pattern-rebuild)
                      (lambda (&rest _)
                        (error "synthetic rebuild failure"))))
             (satan-observer-test--with-stubbed-after-state
                 (list :git_commits
                       (list (list :repo "/x" :slug "emacs.d"
                                   :sha "deadbeef"
                                   :end_ts "2026-05-23T11:15:00+1000"))
                       :fs_state (list :cwd "/x" :recent_files nil)
                       :focus_segments nil :bough_recent nil)
               (let* ((curr-id "20260523T120000-morning-cccccc")
                      (out (satan-observer-process
                            (list :time_now "2026-05-23T12:00:00+1000"
                                  :run_id curr-id
                                  :mode_name "morning"
                                  :audit (satan-observer-test--open-audit
                                          root curr-id))
                            (list :motive-path mpath
                                  :runs-dir root
                                  :memory-mark-fn mark-fn))))
                 ;; Observer returns normal summary (not nil, not error)
                 (should (= 1 (plist-get out :processed)))
                 (should (= 1 (plist-get out :positive)))
                 ;; Classification intact — outcome row exists
                 (let* ((row (satan-intervention-lookup iv-id))
                        (oc (plist-get row :outcome)))
                   (should oc)
                   (should (equal "worked" (plist-get oc :classification))))
                 ;; Pattern outcomes unchanged (rebuild never ran)
                 (let ((result (satan-db-psql
                                satan-observer-test--db
                                satan-memory-migrate-host
                                satan-memory-migrate-psql-program
                                (list "-A" "-t"
                                      "-c"
                                      "SELECT count(*) FROM satan_pattern_outcomes"))))
                   (should (equal "0" (string-trim (cdr result)))))))))))))))

(ert-deftest satan-observer/rebuild-guard-swallows-require-failure ()
  "DR-009 §3.2 — a simulated require failure for satan-pattern is
swallowed; the observer returns normally and classification is intact."
  (satan-observer-test--with-db
   (satan-observer-test--in-tmp
    (lambda (root)
      (let* ((satan-runs-dir root)
             (old-id "20260523T110000-morning-bbbbbb")
             (audit-old (satan-observer-test--open-audit root old-id))
             (ctx-old (satan-observer-test--build-ctx
                       audit-old old-id "2026-05-23T11:00:00+1000"))
             (iv-id (satan-observer-test--mint
                     ctx-old :related-motive-id "docs-after-error")))
        (satan-observer-test--write-bundle-with-handles
         (satan-observer-test--make-run-dir root old-id)
         (list "project:emacs.d"
               "surface_transition:terminal->browser"
               "domain_kind:docs"))
        (satan-motive-test--with-tmp-file
         mpath satan-motive-test--well-formed-cwd
         (satan-observer-test--capture-mark _captured
           ;; Simulate satan-pattern being unloadable
           (let ((real-require (symbol-function 'require)))
             (cl-letf (((symbol-function 'require)
                        (lambda (feature &rest args)
                          (if (eq feature 'satan-pattern)
                              (error "Cannot open load file: satan-pattern")
                            (apply real-require feature args)))))
               (satan-observer-test--with-stubbed-after-state
                   (list :git_commits
                         (list (list :repo "/x" :slug "emacs.d"
                                     :sha "deadbeef"
                                     :end_ts "2026-05-23T11:15:00+1000"))
                         :fs_state (list :cwd "/x" :recent_files nil)
                         :focus_segments nil :bough_recent nil)
                 (let* ((curr-id "20260523T120000-morning-dddddd")
                        (out (satan-observer-process
                              (list :time_now "2026-05-23T12:00:00+1000"
                                    :run_id curr-id
                                    :mode_name "morning"
                                    :audit (satan-observer-test--open-audit
                                            root curr-id))
                              (list :motive-path mpath
                                    :runs-dir root
                                    :memory-mark-fn mark-fn))))
                   ;; Observer returns normally
                   (should (= 1 (plist-get out :processed)))
                   (should (= 1 (plist-get out :positive)))
                   ;; Classification intact
                   (let* ((row (satan-intervention-lookup iv-id))
                          (oc (plist-get row :outcome)))
                     (should oc)
                     (should (equal "worked" (plist-get oc :classification)))))))))))))))

(ert-deftest satan-observer/rebuild-guard-classification-intact ()
  "DR-009 §3.2 — with the rebuild guard active (and succeeding),
classification + outcome projection are intact."
  (satan-observer-test--with-db
   (satan-observer-test--in-tmp
    (lambda (root)
      (let* ((satan-runs-dir root)
             (old-id "20260523T110000-morning-eeeeee")
             (audit-old (satan-observer-test--open-audit root old-id))
             (ctx-old (satan-observer-test--build-ctx
                       audit-old old-id "2026-05-23T11:00:00+1000"))
             (iv-id (satan-observer-test--mint
                     ctx-old :related-motive-id "docs-after-error")))
        (satan-observer-test--write-bundle-with-handles
         (satan-observer-test--make-run-dir root old-id)
         (list "topic:nothing-matches"))
        (satan-motive-test--with-tmp-file
         mpath satan-motive-test--well-formed-cwd
         (satan-observer-test--capture-mark _captured
           (satan-observer-test--with-stubbed-after-state
               (list :git_commits nil :fs_state nil
                     :focus_segments nil :bough_recent nil)
             (let* ((curr-id "20260523T120000-morning-ffffff")
                    (out (satan-observer-process
                          (list :time_now "2026-05-23T12:00:00+1000"
                                :run_id curr-id
                                :mode_name "morning"
                                :audit (satan-observer-test--open-audit
                                        root curr-id))
                          (list :motive-path mpath
                                :runs-dir root
                                :memory-mark-fn mark-fn))))
               ;; Observer returns normal summary
               (should (= 1 (plist-get out :processed)))
               (should (= 0 (plist-get out :positive)))
               ;; Classification recorded correctly
               (let* ((row (satan-intervention-lookup iv-id))
                      (oc (plist-get row :outcome)))
                 (should oc)
                 (should (equal "unknown" (plist-get oc :classification)))))))))))))

;; ---------------------------------------------------------------------
;; DE-009 P03 — VT-global-attr-regression
;; ---------------------------------------------------------------------

(ert-deftest satan-observer/global-attr-regression-outcome-rows ()
  "DR-009 §3.2 — the global classification path (satan_intervention_outcomes)
is unchanged by the pattern rebuild wiring.  Classifying the same
intervention yields the same outcome row regardless of whether the
rebuild succeeds or fails."
  (satan-observer-test--with-db
   (satan-observer-test--in-tmp
    (lambda (root)
      (let* ((satan-runs-dir root)
             (old-id "20260523T110000-morning-gggggg")
             (audit-old (satan-observer-test--open-audit root old-id))
             (ctx-old (satan-observer-test--build-ctx
                       audit-old old-id "2026-05-23T11:00:00+1000"))
             (iv-id (satan-observer-test--mint
                     ctx-old :related-motive-id "docs-after-error")))
        (satan-observer-test--write-bundle-with-handles
         (satan-observer-test--make-run-dir root old-id)
         (list "project:emacs.d"
               "surface_transition:terminal->browser"
               "domain_kind:docs"))
        (satan-motive-test--with-tmp-file
         mpath satan-motive-test--well-formed-cwd
         (satan-observer-test--capture-mark _captured
           (satan-observer-test--with-stubbed-after-state
               (list :git_commits
                     (list (list :repo "/x" :slug "emacs.d"
                                 :sha "deadbeef"
                                 :end_ts "2026-05-23T11:15:00+1000"))
                     :fs_state (list :cwd "/x" :recent_files nil)
                     :focus_segments nil :bough_recent nil)
             (let* ((curr-id "20260523T120000-morning-hhhhhh")
                    (out (satan-observer-process
                          (list :time_now "2026-05-23T12:00:00+1000"
                                :run_id curr-id
                                :mode_name "morning"
                                :audit (satan-observer-test--open-audit
                                        root curr-id))
                          (list :motive-path mpath
                                :runs-dir root
                                :memory-mark-fn mark-fn))))
               (should (= 1 (plist-get out :processed)))
               (should (= 1 (plist-get out :positive)))
               ;; Global outcome projection is correct
               (let* ((row (satan-intervention-lookup iv-id))
                      (oc (plist-get row :outcome)))
                 (should oc)
                 (should (equal "worked" (plist-get oc :classification)))
                 (should (equal "medium" (plist-get oc :confidence)))
                 (should (equal "mature" (plist-get oc :maturity)))
                 ;; Evidence present — the global path wrote it
                 (let ((ev (plist-get oc :evidence)))
                   (should ev)
                   (should (equal "docs-after-error"
                                  (plist-get ev :motive_id)))
                   (should (equal '("git_commit_observed")
                                  (plist-get ev :predicates)))))
               ;; Pattern outcomes may or may not be populated — that's
               ;; the pattern path, not the global path.  Non-regression
               ;; means the global path is correct; pattern content is
               ;; orthogonal.
               )))))))))

(provide 'satan-observer-test)
;;; satan-observer-test.el ends here
