;;; satan-memory-evidence-test.el --- evidence assembler ert -*- lexical-binding: t; -*-

;; Tests for step 6 of memory.design.md.  Pure helpers exercised
;; directly; impure assembly exercised against tmp fixtures and the
;; canonicalizer (cross-step contract).

(require 'ert)
(require 'cl-lib)
(require 'satan-memory-evidence)
(require 'satan-memory-canon)
(require 'satan-goad-fixture)

(defun satan-memory-evidence-test--with-tmp (body)
  (let ((tmp (make-temp-file "satan-ev-test-" t)))
    (unwind-protect (funcall body tmp)
      (delete-directory tmp t))))

(defmacro satan-memory-evidence-test--in-tmp (var &rest body)
  (declare (indent 1))
  `(satan-memory-evidence-test--with-tmp
    (lambda (,var)
      ,@body)))

;; ---------------------------------------------------------------------
;; Bounds
;; ---------------------------------------------------------------------

(ert-deftest satan-memory-evidence/bounds-no-run-started ()
  (let* ((b (satan-memory-evidence--bounds
             "2026-05-19T10:00:00+10:00" nil)))
    (should (equal (cdr b) "2026-05-19T10:00:00+10:00"))
    (should (string-match-p "2026-05-19T09:50:00" (car b)))))

(ert-deftest satan-memory-evidence/bounds-run-started-later-wins ()
  (let* ((b (satan-memory-evidence--bounds
             "2026-05-19T10:00:00+10:00"
             "2026-05-19T09:55:00+10:00")))
    (should (equal (car b) "2026-05-19T09:55:00+10:00"))))

(ert-deftest satan-memory-evidence/bounds-run-started-earlier-loses ()
  (let* ((b (satan-memory-evidence--bounds
             "2026-05-19T10:00:00+10:00"
             "2026-05-19T09:00:00+10:00")))
    (should (string-match-p "2026-05-19T09:50:00" (car b)))))

;; ---------------------------------------------------------------------
;; Filter segments
;; ---------------------------------------------------------------------

(ert-deftest satan-memory-evidence/filter-segments-overlap ()
  (let* ((segs (list
                (list :start_ts "2026-05-19T09:40:00+10:00"
                      :end_ts   "2026-05-19T09:45:00+10:00")
                (list :start_ts "2026-05-19T09:55:00+10:00"
                      :end_ts   "2026-05-19T09:58:00+10:00")
                (list :start_ts "2026-05-19T10:05:00+10:00"
                      :end_ts   "2026-05-19T10:10:00+10:00")))
         (kept (satan-memory-evidence--filter-segments
                segs
                "2026-05-19T09:50:00+10:00"
                "2026-05-19T10:00:00+10:00")))
    (should (= (length kept) 1))
    (should (equal (plist-get (car kept) :start_ts)
                   "2026-05-19T09:55:00+10:00"))))

(ert-deftest satan-memory-evidence/filter-segments-empty ()
  (should (equal (satan-memory-evidence--filter-segments
                  nil
                  "2026-05-19T09:50:00+10:00"
                  "2026-05-19T10:00:00+10:00")
                 nil)))

;; ---------------------------------------------------------------------
;; Truncation
;; ---------------------------------------------------------------------

(ert-deftest satan-memory-evidence/truncate-noop ()
  (let* ((ev (list :current_window (list :app_id "firefox")))
         (out (satan-memory-evidence--truncate ev 4096 8192)))
    (should-not (plist-get out :truncated_at))))

(ert-deftest satan-memory-evidence/truncate-segments-middle ()
  (let* ((segs (cl-loop for i from 0 below 10
                        collect (list :idx i
                                      :payload
                                      (apply #'concat
                                             (make-list 200 "x")))))
         (ev (list :browser_segments segs))
         (out (satan-memory-evidence--truncate ev 256 65536)))
    (should (member "browser_segments_middle" (plist-get out :truncated_at)))
    (let* ((kept (plist-get out :browser_segments))
           (sentinel (cl-find-if (lambda (s) (plist-get s :truncated)) kept)))
      (should sentinel)
      (should (= (plist-get sentinel :dropped) 4))
      (should (= (length kept) 7)))))

(ert-deftest satan-memory-evidence/truncate-runs-passes-2-3-only ()
  "SL-002 PHASE-02 VT-2 — label honesty, not a byte bound.
After the removal only passes 2 (browser) and 3 (focus) survive, so an
oversized object records exactly those labels and never a bough one.
This deliberately does NOT assert the result fits the cap: the passes
are exhaustible and the cap has never been enforced (ISS-001)."
  (let* ((segs (lambda (n)
                 (cl-loop for i from 0 below n
                          collect (list :idx i
                                        :payload
                                        (apply #'concat
                                               (make-list 400 "x"))))))
         (ev (list :browser_segments (funcall segs 10)
                   :focus_segments (funcall segs 10)))
         (out (satan-memory-evidence--truncate ev 256 512))
         (labels (plist-get out :truncated_at)))
    (should (equal '("browser_segments_middle" "focus_segments_middle")
                   labels))
    (should-not (cl-find-if (lambda (l) (string-match-p "bough" l)) labels))
    ;; Exhausted passes leave it oversized — honest, and ISS-001's job.
    (should (> (satan-memory-evidence--encode-bytes out) 512))))

(ert-deftest satan-memory-evidence/truncate-output-json-serializes ()
  "`:truncated_at' entries must survive `json-serialize'.  Symbols
fail `json-value-p' once `satan-audit--write-json' (percept.json,
bundle.json) or `satan-jsonl-send' (tool results) carries the
truncated evidence."
  (require 'satan-jsonl)
  (let* ((segs (cl-loop for i from 0 below 10
                        collect (list :idx i
                                      :payload
                                      (apply #'concat (make-list 200 "x")))))
         (ev (list :browser_segments segs))
         (out (satan-memory-evidence--truncate ev 256 65536)))
    (should (stringp (json-serialize (satan-jsonl-prepare out)
                                     :null-object :null
                                     :false-object :false)))))

;; ---------------------------------------------------------------------
;; Assemble (impure; tmp fixtures)
;; ---------------------------------------------------------------------

(ert-deftest satan-memory-evidence/assemble-shape-and-bounds ()
  (satan-memory-evidence-test--in-tmp tmp
   (let* ((ctx (list :time_now "2026-05-19T10:00:00+10:00"
                     :mode_name "motd"))
          (out (satan-memory-evidence-assemble
                ctx (list :behaviour_dir (file-name-as-directory tmp)
                          :cwd tmp))))
     (should (equal (plist-get out :window_end_at)
                    "2026-05-19T10:00:00+10:00"))
     (should (stringp (plist-get out :window_start_at)))
     (should (null (plist-get out :current_window)))
     (should (equal (plist-get out :focus_segments) '()))
     (should (equal (plist-get out :browser_segments) '()))
     (should (null (plist-get out :git_state)))
     (should (equal (plist-get (plist-get out :fs_state) :recent_files)
                    '())))))

(ert-deftest satan-memory-evidence/assemble-with-bounds-honours-explicit-window ()
  "Phase 5.1 — `satan-memory-evidence-assemble-with-bounds' lets
the caller supply START / END directly, bypassing the wrapper's
`time_now'-derived window.  Used by the Phase-5 observer to read
the panopticon slice covering a single intervention's 30-min
attribution window.  Wrapper still threads ctx-derived bounds when
called without an explicit start/end."
  (satan-memory-evidence-test--in-tmp tmp
   (let* ((ctx (list :time_now "2026-05-19T10:00:00+10:00"
                     :mode_name "motd"))
          (start "2026-05-19T08:45:00+10:00")
          (end "2026-05-19T09:15:00+10:00")
          (out (satan-memory-evidence-assemble-with-bounds
                start end ctx
                (list :behaviour_dir (file-name-as-directory tmp)
                      :cwd tmp))))
     (should (equal (plist-get out :window_start_at) start))
     (should (equal (plist-get out :window_end_at) end))
     ;; The wrapper still works identically for the default case.
     (let ((wrapper-out (satan-memory-evidence-assemble
                         ctx (list :behaviour_dir (file-name-as-directory tmp)
                                   :cwd tmp))))
       (should (equal (plist-get wrapper-out :window_end_at)
                      "2026-05-19T10:00:00+10:00"))))))

(ert-deftest satan-memory-evidence/assemble-cue-only-skips-heavy-probes ()
  "`:cue_only t' returns empty focus/browser segments even when those
sources would otherwise populate them.  Keeps current_window."
  (satan-memory-evidence-test--in-tmp tmp
   (let* ((current-dir (expand-file-name "current" tmp))
          (segments-dir (expand-file-name "segments" tmp)))
     (make-directory current-dir t)
     (make-directory segments-dir t)
     (with-temp-file (expand-file-name "desktop.json" current-dir)
       (insert "{\"app_id\":\"firefox\",\"workspace\":\"main\"}"))
     (with-temp-file (expand-file-name "focus-2026-05-19.jsonl" segments-dir)
       (insert "{\"app_id\":\"firefox\",\"start_ts\":\"2026-05-19T09:55:00+10:00\",\"end_ts\":\"2026-05-19T09:58:00+10:00\",\"duration_s\":180}\n"))
     (let* ((ctx (list :time_now "2026-05-19T10:00:00+10:00"
                       :mode_name "motd"))
            (out (satan-memory-evidence-assemble
                  ctx (list :behaviour_dir (file-name-as-directory tmp)
                            :cwd tmp
                            :cue_only t))))
       (should (equal (plist-get (plist-get out :current_window) :app_id)
                      "firefox"))
       (should (equal (plist-get out :focus_segments) '()))
       (should (equal (plist-get out :browser_segments) '()))
       ;; ISS-014 — cue-only statuses keep the string vocabulary.
       (let ((ss (plist-get out :sensor_status)))
         (dolist (key '(:focus :browser :git :content))
           (should (equal "ok" (plist-get ss key)))))))))

(ert-deftest satan-memory-evidence/budget-exhausted-skips-optional-stages ()
  "Phase 5 — under an exhausted tick budget the OPTIONAL evidence
stages shed their work: `content_probe' skips, so its raw slot goes
nil, `sensor_status' `:content' degrades to
\"budget_skipped\", the skips land on the accumulator, and the percept
stays valid through `--truncate' + canon (no signal)."
  (satan-memory-evidence-test--in-tmp tmp
   (let* ((satan-trace--current
           (list :t0 (- (float-time) 100) :budget-ms 1
                 :stages nil :skipped nil))
          (ctx (list :time_now "2026-05-19T10:00:00+10:00"
                     :mode_name "motd"))
          (out (satan-memory-evidence-assemble-with-bounds
                "2026-05-19T08:45:00+10:00"
                "2026-05-19T09:15:00+10:00"
                ctx
                (list :behaviour_dir (file-name-as-directory tmp)
                      :cwd tmp))))
     (should (null (plist-get out :content_recent)))
     (should (equal (plist-get (plist-get out :sensor_status) :content)
                    "budget_skipped"))
     ;; the optional skips are recorded honestly on the accumulator
     (should (member "evidence.content_probe"
                     (plist-get satan-trace--current :skipped)))
     ;; degraded percept still canonicalizes (no signal, non-nil result)
     (should (satan-memory-canon-canonicalize out nil ctx)))))

(ert-deftest satan-memory-evidence/assemble-reads-panopticon ()
  (satan-memory-evidence-test--in-tmp tmp
   (let* ((current-dir (expand-file-name "current" tmp))
          (segments-dir (expand-file-name "segments" tmp))
          (ctx (list :time_now "2026-05-19T10:00:00+10:00"
                     :mode_name "motd")))
     (make-directory current-dir t)
     (make-directory segments-dir t)
     (with-temp-file (expand-file-name "desktop.json" current-dir)
       (insert "{\"app_id\":\"firefox\",\"workspace\":\"main\"}"))
     (with-temp-file (expand-file-name "focus-2026-05-19.jsonl" segments-dir)
       (insert "{\"app_id\":\"firefox\",\"start_ts\":\"2026-05-19T09:55:00+10:00\",\"end_ts\":\"2026-05-19T09:58:00+10:00\",\"duration_s\":180}\n")
       (insert "{\"app_id\":\"emacs\",\"start_ts\":\"2026-05-19T08:00:00+10:00\",\"end_ts\":\"2026-05-19T08:30:00+10:00\",\"duration_s\":1800}\n"))
     (let* ((out (satan-memory-evidence-assemble
                  ctx (list :behaviour_dir (file-name-as-directory tmp)
                            :cwd tmp))))
       (should (equal (plist-get (plist-get out :current_window) :app_id)
                      "firefox"))
       ;; Only the in-window segment survives the filter.
       (should (= 1 (length (plist-get out :focus_segments))))
       (should (equal (plist-get (car (plist-get out :focus_segments))
                                 :app_id)
                      "firefox"))))))

(ert-deftest satan-memory-evidence/assemble-git-state-on-repo ()
  ;; Initialize a tmp git repo so we don't depend on the host's layout
  ;; (the ambient ~/.emacs.d here is a bare-config worktree without a
  ;; nested .git/ directory).
  (skip-unless (executable-find "git"))
  (satan-memory-evidence-test--in-tmp tmp
   (let ((default-directory (file-name-as-directory tmp)))
     (should (zerop (call-process "git" nil nil nil "init" "-q"
                                  "-b" "main")))
     (should (zerop (call-process "git" nil nil nil "config"
                                  "user.email" "t@example")))
     (should (zerop (call-process "git" nil nil nil "config"
                                  "user.name" "t")))
     (with-temp-file (expand-file-name "x" tmp) (insert "y"))
     (should (zerop (call-process "git" nil nil nil "add" "x")))
     (should (zerop (call-process "git" nil nil nil "commit" "-qm" "init")))
     (let* ((ctx (list :time_now "2026-05-19T10:00:00+10:00"
                       :mode_name "motd"))
            (out (satan-memory-evidence-assemble
                  ctx (list :behaviour_dir "/nonexistent/"
                            :cwd tmp))))
       (let ((git (plist-get out :git_state)))
         (should git)
         (should (stringp (plist-get git :head_short)))
         (should (= 1 (length (plist-get git :commits)))))))))

(ert-deftest satan-memory-evidence/git-output-sets-optional-locks-env ()
  ;; Prove read-only git subprocesses observe GIT_OPTIONAL_LOCKS=0.
  ;; Stub `git' on `exec-path' with a shell script that echoes the env
  ;; var, so the assertion is deterministic (no real repo, no race).
  (satan-memory-evidence-test--in-tmp tmp
   (let ((stub (expand-file-name "git" tmp)))
     (with-temp-file stub
       (insert "#!/bin/sh\n")
       (insert "printf '%s' \"$GIT_OPTIONAL_LOCKS\"\n"))
     (set-file-modes stub #o755)
     (let ((exec-path (cons tmp exec-path)))
       (should (equal (satan-memory-evidence--git-output "status")
                      "0"))))))

;; ---------------------------------------------------------------------
;; VT-2 — routed choke deadlines: git-output/git-state timeout marker.
;; `satan-trace-call' is stubbed so the timed-out branch is forced
;; without a real hang.
;; ---------------------------------------------------------------------

(ert-deftest satan-memory-evidence/git-output-timeout-returns-nil ()
  "A routed git call that breaches its deadline → nil (non-zero exit)."
  (cl-letf (((symbol-function 'satan-trace-call)
             (lambda (&rest _)
               (list :exit 124 :stdout "" :timed-out t))))
    (should (null (satan-memory-evidence--git-output "status")))))

(ert-deftest satan-memory-evidence/git-state-marks-timed_out ()
  "When a routed sub-call times out, `--git-state' adds `:timed_out t' so
a partial read is never mistaken for a clean repo.  The `--git-dir'
probe succeeds; the follow-up probes time out."
  (satan-memory-evidence-test--in-tmp tmp
   (cl-letf (((symbol-function 'satan-trace-call)
              (lambda (_program args &rest _)
                (if (member "--git-dir" args)
                    (list :exit 0 :stdout ".git" :timed-out nil)
                  (list :exit 124 :stdout "" :timed-out t)))))
     (let ((state (satan-memory-evidence--git-state tmp)))
       (should state)
       (should (eq (plist-get state :timed_out) t))))))

;; ---------------------------------------------------------------------
;; Git-activity feed (bursty — NEVER stale)
;; ---------------------------------------------------------------------

(ert-deftest satan-memory-evidence/git-feed-paths-same-day ()
  (let ((paths (satan-memory-evidence--git-feed-paths
                "/beh/" "2026-05-19T09:50:00+10:00"
                "2026-05-19T10:00:00+10:00")))
    (should (= 1 (length paths)))
    (should (string-suffix-p "segments/git-2026-05-19.jsonl" (car paths)))))

(ert-deftest satan-memory-evidence/git-feed-paths-cross-midnight ()
  (let ((paths (satan-memory-evidence--git-feed-paths
                "/beh/" "2026-05-19T23:55:00+10:00"
                "2026-05-20T00:05:00+10:00")))
    (should (= 2 (length paths)))
    (should (string-suffix-p "segments/git-2026-05-19.jsonl" (nth 0 paths)))
    (should (string-suffix-p "segments/git-2026-05-20.jsonl" (nth 1 paths)))))

(ert-deftest satan-memory-evidence/git-feed-paths-multiday ()
  "VT-feed-paths-multiday: 24h+ horizon enumerates every calendar day.
A window spanning three dates returns three paths, not just the
endpoints.  This was a latent bug: the old implementation returned
only start-day + end-day, missing intermediate days."
  (let ((paths (satan-memory-evidence--git-feed-paths
                "/beh/" "2026-05-19T00:05:00+10:00"
                "2026-05-21T23:55:00+10:00")))
    (should (= 3 (length paths)))
    (should (string-suffix-p "segments/git-2026-05-19.jsonl" (nth 0 paths)))
    (should (string-suffix-p "segments/git-2026-05-20.jsonl" (nth 1 paths)))
    (should (string-suffix-p "segments/git-2026-05-21.jsonl" (nth 2 paths)))))

(ert-deftest satan-memory-evidence/git-feed-paths-dst-fallback ()
  "Calendar-day enumeration survives DST fall-back.
Melbourne 2026-04-05: 03:00 AEDT → 02:00 AEST.  The old +86400s
step would skip a date; calendar arithmetic does not."
  (let ((paths (satan-memory-evidence--git-feed-paths
                "/beh/" "2026-04-04T23:00:00+11:00"
                "2026-04-06T01:00:00+10:00")))
    (should (= 3 (length paths)))
    (should (string-suffix-p "segments/git-2026-04-04.jsonl" (nth 0 paths)))
    (should (string-suffix-p "segments/git-2026-04-05.jsonl" (nth 1 paths)))
    (should (string-suffix-p "segments/git-2026-04-06.jsonl" (nth 2 paths)))))

(ert-deftest satan-memory-evidence/git-feed-paths-next-day ()
  "--next-day produces the correct next calendar date."
  (should (equal "2026-05-20"
                 (satan-memory-evidence--next-day "2026-05-19")))
  (should (equal "2026-06-01"
                 (satan-memory-evidence--next-day "2026-05-31")))
  (should (equal "2026-01-01"
                 (satan-memory-evidence--next-day "2025-12-31")))
  ;; Leap year: 2024-02-28 → 2024-02-29
  (should (equal "2024-02-29"
                 (satan-memory-evidence--next-day "2024-02-28"))))

(ert-deftest satan-memory-evidence/git-commits-in-window ()
  (satan-memory-evidence-test--in-tmp tmp
   (let ((path (expand-file-name "git-2026-05-19.jsonl" tmp)))
     (with-temp-file path
       (insert "{\"repo\":\"/r/satan\",\"slug\":\"satan\",\"start_ts\":\"2026-05-19T09:55:00+10:00\",\"end_ts\":\"2026-05-19T09:55:00+10:00\"}\n"))
     (let ((probe (satan-memory-evidence--git-commits-status
                   (list path) "2026-05-19T09:50:00+10:00"
                   "2026-05-19T10:00:00+10:00" 10)))
       (should (equal "ok" (car probe)))
       (should (= 1 (length (cdr probe))))
       (should (equal "satan" (plist-get (car (cdr probe)) :slug)))))))

(ert-deftest satan-memory-evidence/git-commits-bursty-old-still-ok ()
  "A days-old newest commit is NORMAL: status stays \"ok\" (never
\"stale-Nm\", unlike focus/browser) and only the in-window slice is
returned (here empty).  This is the divergent-freshness contract."
  (satan-memory-evidence-test--in-tmp tmp
   (let ((path (expand-file-name "git-2026-05-19.jsonl" tmp)))
     (with-temp-file path
       (insert "{\"repo\":\"/r\",\"slug\":\"r\",\"start_ts\":\"2026-05-16T09:00:00+10:00\",\"end_ts\":\"2026-05-16T09:00:00+10:00\"}\n"))
     (let ((probe (satan-memory-evidence--git-commits-status
                   (list path) "2026-05-19T09:50:00+10:00"
                   "2026-05-19T10:00:00+10:00" 10)))
       (should (equal "ok" (car probe)))
       (should (equal '() (cdr probe)))))))

(ert-deftest satan-memory-evidence/git-commits-missing ()
  (satan-memory-evidence-test--in-tmp tmp
   (let ((probe (satan-memory-evidence--git-commits-status
                 (list (expand-file-name "git-nope.jsonl" tmp))
                 "2026-05-19T09:50:00+10:00"
                 "2026-05-19T10:00:00+10:00" 10)))
     (should (equal "missing" (car probe)))
     (should (equal '() (cdr probe))))))

(ert-deftest satan-memory-evidence/git-commits-malformed ()
  "Single malformed file with no readable siblings → \"malformed\"."
  (satan-memory-evidence-test--in-tmp tmp
   (let ((path (expand-file-name "git-2026-05-19.jsonl" tmp)))
     (with-temp-file path (insert "{not json}\n"))
     (let ((probe (satan-memory-evidence--git-commits-status
                   (list path) "2026-05-19T09:50:00+10:00"
                   "2026-05-19T10:00:00+10:00" 10)))
       (should (equal "malformed" (car probe)))))))

(ert-deftest satan-memory-evidence/git-commits-malformed-tolerant ()
  "VT-malformed-tolerance: one bad file among good siblings doesn't blank
all commits.  Good rows from the readable file survive."
  (satan-memory-evidence-test--in-tmp tmp
   (let ((good-path (expand-file-name "git-2026-05-19.jsonl" tmp))
         (bad-path (expand-file-name "git-2026-05-18.jsonl" tmp)))
     (with-temp-file good-path
       (insert "{\"repo\":\"/r/x\",\"slug\":\"x\",\"start_ts\":\"2026-05-19T09:55:00+10:00\",\"end_ts\":\"2026-05-19T09:55:00+10:00\"}\n"))
     (with-temp-file bad-path
       (insert "{not json}\n"))
     (let ((probe (satan-memory-evidence--git-commits-status
                   (list bad-path good-path)
                   "2026-05-19T09:50:00+10:00"
                   "2026-05-19T10:00:00+10:00" 10)))
       (should (equal "ok" (car probe)))
       (should (= 1 (length (cdr probe))))
       (should (equal "x" (plist-get (car (cdr probe)) :slug)))))))

(ert-deftest satan-memory-evidence/git-commits-sorted-by-end-ts ()
  "VT-sort-limit: newest commit is genuinely the last after sorting by
:end_ts, regardless of append order in the files."
  (satan-memory-evidence-test--in-tmp tmp
   (let ((path (expand-file-name "git-2026-05-19.jsonl" tmp)))
     ;; Write rows in non-chronological order.
     (with-temp-file path
       (insert "{\"repo\":\"/r/a\",\"slug\":\"middle\",\"start_ts\":\"2026-05-19T09:52:00+10:00\",\"end_ts\":\"2026-05-19T09:52:00+10:00\"}\n")
       (insert "{\"repo\":\"/r/b\",\"slug\":\"newest\",\"start_ts\":\"2026-05-19T09:58:00+10:00\",\"end_ts\":\"2026-05-19T09:58:00+10:00\"}\n")
       (insert "{\"repo\":\"/r/c\",\"slug\":\"oldest\",\"start_ts\":\"2026-05-19T09:51:00+10:00\",\"end_ts\":\"2026-05-19T09:51:00+10:00\"}\n"))
     (let* ((probe (satan-memory-evidence--git-commits-status
                    (list path) "2026-05-19T09:50:00+10:00"
                    "2026-05-19T10:00:00+10:00" 10))
            (commits (cdr probe)))
       (should (equal "ok" (car probe)))
       (should (= 3 (length commits)))
       (should (equal "oldest" (plist-get (nth 0 commits) :slug)))
       (should (equal "middle" (plist-get (nth 1 commits) :slug)))
       (should (equal "newest" (plist-get (nth 2 commits) :slug)))))))

(ert-deftest satan-memory-evidence/git-window-sees-commit-outside-10min ()
  "VT-git-window: a commit 15 min ago (outside the 10-min focus window
but inside the 24h git window) appears in :git_commits.
Focus/browser segments remain on the 10-min window."
  (satan-memory-evidence-test--in-tmp tmp
   (let* ((segments-dir (expand-file-name "segments" tmp))
          (git-start-iso
           (satan-memory-evidence--iso-format
            (time-subtract (date-to-time "2026-05-19T10:00:00+10:00")
                           (seconds-to-time (* 60 1440))))))
     (make-directory segments-dir t)
     ;; Git commit at T-15 minutes → outside 10-min focus window, inside 24h git window.
     (with-temp-file (expand-file-name "git-2026-05-19.jsonl" segments-dir)
       (insert "{\"repo\":\"/r/satan\",\"slug\":\"satan\",\"start_ts\":\"2026-05-19T09:45:00+10:00\",\"end_ts\":\"2026-05-19T09:45:00+10:00\"}\n"))
     ;; Focus segment at T-5 minutes → in both windows.
     (with-temp-file (expand-file-name "focus-2026-05-19.jsonl" segments-dir)
       (insert "{\"app_id\":\"emacs\",\"start_ts\":\"2026-05-19T09:55:00+10:00\",\"end_ts\":\"2026-05-19T09:58:00+10:00\",\"duration_s\":180}\n"))
     (let* ((ctx (list :time_now "2026-05-19T10:00:00+10:00"
                       :mode_name "motd"))
            (out (satan-memory-evidence-assemble
                  ctx (list :behaviour_dir (file-name-as-directory tmp)
                            :cwd tmp)))
            (ss (plist-get out :sensor_status)))
       ;; Git: the commit is inside the 24h git window.
       (should (equal "ok" (plist-get ss :git)))
       (should (= 1 (length (plist-get out :git_commits))))
       ;; Focus: the focus segment is inside the 10-min window.
       (should (= 1 (length (plist-get out :focus_segments))))
       ;; Window fields: git_start_at ≠ window_start_at.
       (should (stringp (plist-get out :git_window_start_at)))
       (should (stringp (plist-get out :window_start_at)))
       (should-not (equal (plist-get out :git_window_start_at)
                          (plist-get out :window_start_at)))))))

(ert-deftest satan-memory-evidence/git-window-field-distinct ()
  "VT-git-window-field: :git_window_start_at is present and strictly
eaerlier than :window_start_at when git-window > window-minutes."
  (satan-memory-evidence-test--in-tmp tmp
   (let* ((ctx (list :time_now "2026-05-19T10:00:00+10:00"
                     :mode_name "motd"))
          (out (satan-memory-evidence-assemble
                ctx (list :behaviour_dir (file-name-as-directory tmp)
                          :cwd tmp)))
          (git-start (plist-get out :git_window_start_at))
          (win-start (plist-get out :window_start_at)))
     (should (stringp git-start))
     (should (stringp win-start))
     ;; git-start should be earlier (wider window).
     (should (time-less-p (date-to-time git-start)
                          (date-to-time win-start))))))

(ert-deftest satan-memory-evidence/assemble-reads-git-feed ()
  "End-to-end: the feed surfaces as `:git_commits' + `:git' sensor_status."
  (satan-memory-evidence-test--in-tmp tmp
   (let* ((segments-dir (expand-file-name "segments" tmp))
          (ctx (list :time_now "2026-05-19T10:00:00+10:00" :mode_name "motd")))
     (make-directory segments-dir t)
     (with-temp-file (expand-file-name "git-2026-05-19.jsonl" segments-dir)
       (insert "{\"repo\":\"/r/satan\",\"slug\":\"satan\",\"start_ts\":\"2026-05-19T09:55:00+10:00\",\"end_ts\":\"2026-05-19T09:55:00+10:00\"}\n"))
     (let* ((out (satan-memory-evidence-assemble
                  ctx (list :behaviour_dir (file-name-as-directory tmp)
                            :cwd tmp)))
            (ss (plist-get out :sensor_status)))
       (should (equal "ok" (plist-get ss :git)))
       (should (= 1 (length (plist-get out :git_commits))))
       (should (equal "satan"
                      (plist-get (car (plist-get out :git_commits)) :slug)))))))

;; ---------------------------------------------------------------------
;; Freshness check (§S6 / Phase 4.1)
;; ---------------------------------------------------------------------

(ert-deftest satan-memory-evidence/sensor-status-all-missing ()
  "No sensor files: every probe reports \"missing\"."
  (satan-memory-evidence-test--in-tmp tmp
   (let* ((ctx (list :time_now "2026-05-19T10:00:00+10:00"
                     :mode_name "motd"))
          (out (satan-memory-evidence-assemble
                ctx (list :behaviour_dir (file-name-as-directory tmp)
                          :cwd tmp)))
          (ss (plist-get out :sensor_status)))
     (should (equal "missing" (plist-get ss :current_window)))
     (should (equal "missing" (plist-get ss :focus)))
     (should (equal "missing" (plist-get ss :browser))))))

(ert-deftest satan-memory-evidence/assemble-emits-no-bough-surface ()
  "SL-002 PHASE-02 VT-1 — the assembled window carries no `:bough_*'
field, `sensor_status' has no `:bough' key, and the removed opts are
no longer consumed (passing them changes nothing)."
  (satan-memory-evidence-test--in-tmp tmp
   (let* ((ctx (list :time_now "2026-05-19T10:00:00+10:00"
                     :mode_name "motd"))
          (base (list :behaviour_dir (file-name-as-directory tmp) :cwd tmp))
          (out (satan-memory-evidence-assemble ctx base))
          (with-dead-opts (satan-memory-evidence-assemble
                           ctx (append base (list :bough_limit 3
                                                  :bough_workspace "main")))))
     (dolist (k '(:bough_recent :bough_active :bough_day))
       (should-not (plist-member out k)))
     (should-not (plist-member (plist-get out :sensor_status) :bough))
     ;; The dead opts are inert, not merely absent from the output.
     (should (equal (plist-get out :sensor_status)
                    (plist-get with-dead-opts :sensor_status))))))

(ert-deftest satan-memory-evidence/sensor-status-current-stale-drops-slice ()
  "When desktop.json mtime exceeds the threshold, :current_window is
dropped from the evidence (set nil) AND the status is tagged
\"stale-Nm\"."
  (satan-memory-evidence-test--in-tmp tmp
   (let* ((current-dir (expand-file-name "current" tmp))
          (desktop-path (expand-file-name "desktop.json" current-dir))
          (ctx (list :time_now "2026-05-19T10:00:00+10:00"
                     :mode_name "motd")))
     (make-directory current-dir t)
     (with-temp-file desktop-path
       (insert "{\"app_id\":\"firefox\",\"workspace\":\"main\"}"))
     (let ((old (time-subtract (date-to-time "2026-05-19T10:00:00+10:00")
                               (seconds-to-time (* 60 28)))))
       (set-file-times desktop-path old))
     (let* ((out (satan-memory-evidence-assemble
                  ctx (list :behaviour_dir (file-name-as-directory tmp)
                            :cwd tmp)))
            (ss (plist-get out :sensor_status)))
       (should (null (plist-get out :current_window)))
       (should (equal (plist-get ss :current_window) "stale-28m"))))))

(ert-deftest satan-memory-evidence/sensor-status-current-fresh-keeps-slice ()
  (satan-memory-evidence-test--in-tmp tmp
   (let* ((current-dir (expand-file-name "current" tmp))
          (desktop-path (expand-file-name "desktop.json" current-dir))
          (ctx (list :time_now (format-time-string "%Y-%m-%dT%T%:z")
                     :mode_name "motd")))
     (make-directory current-dir t)
     (with-temp-file desktop-path
       (insert "{\"app_id\":\"firefox\",\"workspace\":\"main\"}"))
     (let* ((out (satan-memory-evidence-assemble
                  ctx (list :behaviour_dir (file-name-as-directory tmp)
                            :cwd tmp)))
            (ss (plist-get out :sensor_status)))
       (should (equal (plist-get (plist-get out :current_window) :app_id)
                      "firefox"))
       (should (equal "ok" (plist-get ss :current_window)))))))

(ert-deftest satan-memory-evidence/sensor-status-segments-stale ()
  "Segments file whose newest :end_ts is past the 30-min threshold
reports \"stale-Nm\" and the slice drops to '()."
  (satan-memory-evidence-test--in-tmp tmp
   (let* ((segments-dir (expand-file-name "segments" tmp))
          (ctx (list :time_now "2026-05-19T10:00:00+10:00"
                     :mode_name "motd")))
     (make-directory segments-dir t)
     (with-temp-file (expand-file-name "focus-2026-05-19.jsonl" segments-dir)
       (insert "{\"app_id\":\"firefox\",\"start_ts\":\"2026-05-19T08:55:00+10:00\",\"end_ts\":\"2026-05-19T08:58:00+10:00\",\"duration_s\":180}\n"))
     (let* ((out (satan-memory-evidence-assemble
                  ctx (list :behaviour_dir (file-name-as-directory tmp)
                            :cwd tmp)))
            (ss (plist-get out :sensor_status)))
       (should (equal '() (plist-get out :focus_segments)))
       (should (equal "stale-62m" (plist-get ss :focus)))))))

(ert-deftest satan-memory-evidence/sensor-status-malformed-json ()
  "Malformed desktop.json → status \"malformed\", slice nil."
  (satan-memory-evidence-test--in-tmp tmp
   (let* ((current-dir (expand-file-name "current" tmp))
          (ctx (list :time_now (format-time-string "%Y-%m-%dT%T%:z")
                     :mode_name "motd")))
     (make-directory current-dir t)
     (with-temp-file (expand-file-name "desktop.json" current-dir)
       (insert "{not-json"))
     (let* ((out (satan-memory-evidence-assemble
                  ctx (list :behaviour_dir (file-name-as-directory tmp)
                            :cwd tmp)))
            (ss (plist-get out :sensor_status)))
       (should (null (plist-get out :current_window)))
       (should (equal "malformed" (plist-get ss :current_window)))))))

;; ---------------------------------------------------------------------
;; Cross-step contract: canon eats assembler output.
;; ---------------------------------------------------------------------

(ert-deftest satan-memory-evidence/canon-eats-output-minimal ()
  (satan-memory-evidence-test--in-tmp tmp
   (let* ((current-dir (expand-file-name "current" tmp))
          (ctx (list :time_now "2026-05-19T10:00:00+10:00"
                     :mode_name "motd"
                     :current_grammar_version 1)))
     (make-directory current-dir t)
     (with-temp-file (expand-file-name "desktop.json" current-dir)
       (insert "{\"app_id\":\"firefox\",\"workspace\":\"main\"}"))
     (let* ((ev (satan-memory-evidence-assemble
                 ctx (list :behaviour_dir (file-name-as-directory tmp)
                           :cwd tmp)))
            (canon (satan-memory-canon-canonicalize ev nil ctx))
            (handles (plist-get canon :handles)))
       (should (member "app:firefox" handles))
       (should (member "surface:browser" handles))
       (should (member "mode:motd" handles))
       (should (member "day:2026-05-19" handles))
       (should (member "week:2026-W21" handles))))))

;; ---------------------------------------------------------------------
;; newest-segment-end must compare by parsed instant, not string.
;; Segment files can carry mixed timestamp offsets during a capture-side
;; format transition (e.g. the firefox plugin's UTC-`Z` → local-offset
;; fix): a `Z' instant 10 h ahead of local sorts LOWER as a string than
;; a stale `+10:00' one, so a naive `string>' picks the older entry and
;; reports a false `stale-Nm'.
;; ---------------------------------------------------------------------

(ert-deftest satan-memory-evidence/newest-segment-end-single-offset ()
  "All-same-offset: returns the max instant (unchanged behaviour)."
  (should (equal "2026-05-29T19:00:00+10:00"
                 (satan-memory-evidence--newest-segment-end
                  (list '(:end_ts "2026-05-29T17:00:00+10:00")
                        '(:end_ts "2026-05-29T19:00:00+10:00")
                        '(:end_ts "2026-05-29T18:00:00+10:00"))))))

(ert-deftest satan-memory-evidence/newest-segment-end-mixed-offset ()
  "Mixed `Z' + `+10:00': newest by INSTANT wins even when its string
sorts lower.  `2026-05-29T08:00:00Z' (= 18:00 +10:00) is later than
`2026-05-29T17:00:00+10:00' (= 07:00Z) but `\"17\"' > `\"08\"' as a
string, so a `string>'-based selector returns the wrong (older) entry."
  (should (equal "2026-05-29T08:00:00Z"
                 (satan-memory-evidence--newest-segment-end
                  (list '(:end_ts "2026-05-29T17:00:00+10:00")
                        '(:end_ts "2026-05-29T08:00:00Z"))))))

(ert-deftest satan-memory-evidence/newest-segment-end-empty ()
  "No segments / no parseable `:end_ts' → nil."
  (should (null (satan-memory-evidence--newest-segment-end nil)))
  (should (null (satan-memory-evidence--newest-segment-end
                 '((:start_ts "2026-05-29T17:00:00+10:00"))))))

;; ---------------------------------------------------------------------
;; SL-016 PHASE-03 — the `:goad' slice.  The queue and day records are
;; the goldens of goad's `backend.py', read in place; malformed inputs
;; use a scratch dir.
;; ---------------------------------------------------------------------

(defconst satan-memory-evidence-test--far-from-goad
  '("2026-09-25T09:50:00+10:00" . "2026-09-25T10:00:00+10:00")
  "An assembler window two days after every golden ask's emit date.")

(defun satan-memory-evidence-test--assemble-goad (tmp &optional opts)
  "Assemble over `satan-memory-evidence-test--far-from-goad', panopticon at TMP."
  (let ((w satan-memory-evidence-test--far-from-goad))
    (satan-memory-evidence-assemble-with-bounds
     (car w) (cdr w)
     (list :time_now (cdr w) :mode_name "motd")
     (append opts (list :behaviour_dir (file-name-as-directory tmp) :cwd tmp)))))

(ert-deftest satan-memory-evidence/goad-slice-ignores-the-window-bounds ()
  "Every queued ask is contributed with its record, read from its own emit
date, although the assembler's window is two days later (RV-007 F-23)."
  (satan-memory-evidence-test--in-tmp tmp
    (satan-goad-fixture-with-goldens
      (let ((goad (plist-get (satan-memory-evidence-test--assemble-goad tmp)
                             :goad)))
        (should (= 7 (length goad)))
        (should (equal (satan-goad-slice) goad))
        (should (plist-get (satan-goad-fixture-find 'answered goad) :record))))))

(ert-deftest satan-memory-evidence/goad-slice-absent-without-a-usable-queue ()
  "No queue, or a malformed one: no `:goad' key at all, and no signal."
  (satan-memory-evidence-test--in-tmp tmp
    (satan-goad-fixture-with-tmp _dir
      (should-not (plist-member (satan-memory-evidence-test--assemble-goad tmp)
                                :goad))
      (satan-goad-fixture-write satan-goad-queue-file "{\"asks\": [")
      (should-not (plist-member (satan-memory-evidence-test--assemble-goad tmp)
                                :goad)))))

(ert-deftest satan-memory-evidence/goad-slice-skipped-for-cue-only ()
  "`:cue_only' (memory_resonate's cue derivation) does not read goad."
  (satan-memory-evidence-test--in-tmp tmp
    (satan-goad-fixture-with-goldens
      (should-not (plist-member (satan-memory-evidence-test--assemble-goad
                                 tmp '(:cue_only t))
                                :goad)))))

(defconst satan-memory-evidence-test--goad-effects
  '(write-region write-file make-directory rename-file copy-file
    delete-file set-file-times
    satan-db-psql satan-attribute-enqueue satan-intervention-record
    make-process)
  "What the perceive leg may never do while reading goad (ADR-001).")

(defun satan-memory-evidence-test--forbidding (fns thunk)
  "Call THUNK with every function in FNS replaced by an `ert-fail' spy.
Refuses an unbound name, so a typo cannot make a spy vacuous."
  (if (null fns)
      (funcall thunk)
    (let ((fn (car fns)))
      (unless (fboundp fn) (ert-fail (format "spy target %s is unbound" fn)))
      (cl-letf (((symbol-function fn)
                 (lambda (&rest _) (ert-fail (format "evidence called %s" fn)))))
        (satan-memory-evidence-test--forbidding (cdr fns) thunk)))))

(ert-deftest satan-memory-evidence/goad-slice-is-pure ()
  "VT-32 — assembling the `:goad' slice writes nothing and has no effect:
`ert-fail' spies on the file writers, the DB, attribute enqueue,
intervention record and process spawn.  Read-only git probes
\(`call-process') are allowed, as in `satan-broker/perceive-is-pure'.
`satan-trace-enabled' is nil: the telemetry ledger is the tick's own
write, outside this claim."
  (require 'satan-db)
  (require 'satan-attribute)
  (require 'satan-intervention)
  (satan-memory-evidence-test--in-tmp tmp
    (satan-goad-fixture-with-goldens
      (let* ((satan-trace-enabled nil)
             (out (satan-memory-evidence-test--forbidding
                   satan-memory-evidence-test--goad-effects
                   (lambda () (satan-memory-evidence-test--assemble-goad tmp)))))
        (should (= 7 (length (plist-get out :goad))))))))

(ert-deftest satan-memory-evidence/canon-perceives-outstanding-goad-asks ()
  "Cross-step: the assembled `:goad' slice, canonicalized at a time inside
the 09:30 asks' window, yields `app:goad' and the outstanding subjects."
  (satan-memory-evidence-test--in-tmp tmp
    (satan-goad-fixture-with-goldens
      (let* ((ev (satan-memory-evidence-test--assemble-goad tmp))
             (handles (plist-get (satan-memory-canon-canonicalize
                                  ev nil
                                  (list :time_now "2026-09-23T09:35:00+10:00"))
                                 :handles)))
        (should (member "app:goad" handles))
        (should (member (satan-goad-subject-topic "surface:notes") handles))))))

(provide 'satan-memory-evidence-test)
;;; satan-memory-evidence-test.el ends here
