;;; dl-satan-memory-evidence-test.el --- evidence assembler ert -*- lexical-binding: t; -*-

;; Tests for step 6 of memory.design.md.  Pure helpers exercised
;; directly; impure assembly exercised against tmp fixtures and the
;; canonicalizer (cross-step contract).
;;
;; Bough is silenced by pointing `dl-satan-bough-program' at a
;; non-existent path so the tool handler returns an `error' which
;; `dl-satan-memory-evidence--bough-call' swallows.

(require 'ert)
(require 'cl-lib)
(require 'dl-satan-memory-evidence)
(require 'dl-satan-memory-canon)

(defun dl-satan-memory-evidence-test--with-tmp (body)
  (let ((tmp (make-temp-file "satan-ev-test-" t)))
    (unwind-protect (funcall body tmp)
      (delete-directory tmp t))))

(defmacro dl-satan-memory-evidence-test--in-tmp (var &rest body)
  (declare (indent 1))
  `(dl-satan-memory-evidence-test--with-tmp
    (lambda (,var)
      (let ((dl-satan-bough-program "/nonexistent/bough"))
        ,@body))))

;; ---------------------------------------------------------------------
;; Bounds
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-memory-evidence/bounds-no-run-started ()
  (let* ((b (dl-satan-memory-evidence--bounds
             "2026-05-19T10:00:00+10:00" nil)))
    (should (equal (cdr b) "2026-05-19T10:00:00+10:00"))
    (should (string-match-p "2026-05-19T09:50:00" (car b)))))

(ert-deftest dl-satan-memory-evidence/bounds-run-started-later-wins ()
  (let* ((b (dl-satan-memory-evidence--bounds
             "2026-05-19T10:00:00+10:00"
             "2026-05-19T09:55:00+10:00")))
    (should (equal (car b) "2026-05-19T09:55:00+10:00"))))

(ert-deftest dl-satan-memory-evidence/bounds-run-started-earlier-loses ()
  (let* ((b (dl-satan-memory-evidence--bounds
             "2026-05-19T10:00:00+10:00"
             "2026-05-19T09:00:00+10:00")))
    (should (string-match-p "2026-05-19T09:50:00" (car b)))))

;; ---------------------------------------------------------------------
;; Flatten
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-memory-evidence/flatten-nil ()
  (should (equal (dl-satan-memory-evidence--flatten-tree nil) '())))

(ert-deftest dl-satan-memory-evidence/flatten-nested ()
  (let* ((tree (list
                (list :nanoid "a"
                      :children
                      (list (list :nanoid "a1")
                            (list :nanoid "a2"
                                  :children (list (list :nanoid "a21")))))
                (list :nanoid "b")))
         (flat (dl-satan-memory-evidence--flatten-tree tree)))
    (should (equal (mapcar (lambda (n) (plist-get n :nanoid)) flat)
                   '("a" "a1" "a2" "a21" "b")))
    (should (cl-every (lambda (n) (null (plist-get n :children))) flat))))

;; ---------------------------------------------------------------------
;; Filter segments
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-memory-evidence/filter-segments-overlap ()
  (let* ((segs (list
                (list :start_ts "2026-05-19T09:40:00+10:00"
                      :end_ts   "2026-05-19T09:45:00+10:00")
                (list :start_ts "2026-05-19T09:55:00+10:00"
                      :end_ts   "2026-05-19T09:58:00+10:00")
                (list :start_ts "2026-05-19T10:05:00+10:00"
                      :end_ts   "2026-05-19T10:10:00+10:00")))
         (kept (dl-satan-memory-evidence--filter-segments
                segs
                "2026-05-19T09:50:00+10:00"
                "2026-05-19T10:00:00+10:00")))
    (should (= (length kept) 1))
    (should (equal (plist-get (car kept) :start_ts)
                   "2026-05-19T09:55:00+10:00"))))

(ert-deftest dl-satan-memory-evidence/filter-segments-empty ()
  (should (equal (dl-satan-memory-evidence--filter-segments
                  nil
                  "2026-05-19T09:50:00+10:00"
                  "2026-05-19T10:00:00+10:00")
                 nil)))

;; ---------------------------------------------------------------------
;; bough-recent: synthesize :event per transition/created row (DR-116)
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-memory-evidence/bough-recent-synthesizes-events ()
  "Transitions become `:event \"status_changed\"' entries; created nodes
become `:event \"created\"' entries.  Output is one flat list with
status_changed rows first (the canon-relevant ones)."
  (cl-letf (((symbol-function 'dl-satan-memory-evidence--bough-call)
             (lambda (scope &rest _args)
               (when (equal scope "recent_changes")
                 (list :scope "recent_changes"
                       :since "X"
                       :transitions
                       (list (list :seq 7 :nanoid "abc1234"
                                   :from_status "todo"
                                   :to_status "doing"
                                   :at "2026-05-20T09:00:00Z"
                                   :actor nil))
                       :created
                       (list (list :nanoid "def5678"
                                   :kind "task"
                                   :title "x"
                                   :status "todo"
                                   :parent_nanoid "PARENT0"
                                   :at "2026-05-20T08:00:00Z"
                                   :deleted :json-false
                                   :archived :json-false)))))))
    (let* ((flat (dl-satan-memory-evidence--bough-recent
                  "2026-05-20T00:00:00Z" nil 50))
           (events (mapcar (lambda (e) (plist-get e :event)) flat)))
      (should (equal events '("status_changed" "created")))
      (let ((row (car flat)))
        (should (equal "abc1234" (plist-get row :nanoid)))
        (should (equal "todo"    (plist-get row :from)))
        (should (equal "doing"   (plist-get row :to)))
        (should (equal "2026-05-20T09:00:00Z" (plist-get row :at)))
        (should (= 7 (plist-get row :seq))))
      (let ((row (cadr flat)))
        (should (equal "def5678" (plist-get row :nanoid)))
        (should (equal "task"    (plist-get row :kind)))
        (should (equal "todo"    (plist-get row :status)))
        (should (equal "PARENT0" (plist-get row :parent_nanoid)))))))

(ert-deftest dl-satan-memory-evidence/bough-recent-honours-limit ()
  "LIMIT caps the total emitted rows."
  (cl-letf (((symbol-function 'dl-satan-memory-evidence--bough-call)
             (lambda (_scope &rest _args)
               (list :transitions
                     (cl-loop for i from 0 below 5
                              collect (list :seq i :nanoid (format "n%d" i)
                                            :from_status "todo"
                                            :to_status "doing"
                                            :at "2026-05-20T09:00:00Z"))
                     :created
                     (cl-loop for i from 0 below 5
                              collect (list :nanoid (format "c%d" i)
                                            :kind "task" :title "y"
                                            :status "todo"
                                            :at "2026-05-20T08:00:00Z"))))))
    (let ((flat (dl-satan-memory-evidence--bough-recent
                 "2026-05-20T00:00:00Z" nil 3)))
      (should (= 3 (length flat))))))

(ert-deftest dl-satan-memory-evidence/bough-recent-empty-payload ()
  (cl-letf (((symbol-function 'dl-satan-memory-evidence--bough-call)
             (lambda (&rest _) nil)))
    (should (equal '() (dl-satan-memory-evidence--bough-recent
                        "2026-05-20T00:00:00Z" nil 50)))))

;; ---------------------------------------------------------------------
;; Truncation
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-memory-evidence/truncate-noop ()
  (let* ((ev (list :current_window (list :app_id "firefox")))
         (out (dl-satan-memory-evidence--truncate ev 4096 8192)))
    (should-not (plist-get out :truncated_at))))

(ert-deftest dl-satan-memory-evidence/truncate-drops-bough-day-bodies ()
  (let* ((big (apply #'concat (make-list 4000 "x")))
         (ev (list :current_window (list :app_id "firefox")
                   :bough_day (list :linked (list (list :nanoid "n1"))
                                    :body big)))
         (out (dl-satan-memory-evidence--truncate ev 1024 65536)))
    (should (member "bough_day_bodies" (plist-get out :truncated_at)))
    (should (plist-get (plist-get out :bough_day) :body_dropped))
    (should (equal (plist-get (plist-get out :bough_day) :linked)
                   (list (list :nanoid "n1"))))))

(ert-deftest dl-satan-memory-evidence/truncate-segments-middle ()
  (let* ((segs (cl-loop for i from 0 below 10
                        collect (list :idx i
                                      :payload
                                      (apply #'concat
                                             (make-list 200 "x")))))
         (ev (list :browser_segments segs))
         (out (dl-satan-memory-evidence--truncate ev 256 65536)))
    (should (member "browser_segments_middle" (plist-get out :truncated_at)))
    (let* ((kept (plist-get out :browser_segments))
           (sentinel (cl-find-if (lambda (s) (plist-get s :truncated)) kept)))
      (should sentinel)
      (should (= (plist-get sentinel :dropped) 4))
      (should (= (length kept) 7)))))

(ert-deftest dl-satan-memory-evidence/truncate-shrinks-bough-annotations ()
  (let* ((huge-ann (apply #'concat (make-list 500 "y")))
         (ev (list :bough_active
                   (list (list :nanoid "n1" :annotation huge-ann))))
         (out (dl-satan-memory-evidence--truncate ev 256 65536))
         (n1  (car (plist-get out :bough_active))))
    (should (member "bough_active_annotation_bodies"
                    (plist-get out :truncated_at)))
    (should (<= (length (plist-get n1 :annotation)) 260))
    (should (= 500 (plist-get n1 :annotation_len_original)))))

(ert-deftest dl-satan-memory-evidence/truncate-hard-cap-drops-bough-recent ()
  (let* ((huge (apply #'concat (make-list 200000 "x")))
         (ev (list :bough_recent (list (list :nanoid "n1" :note huge))))
         (out (dl-satan-memory-evidence--truncate ev 4096 8192)))
    (should (member "bough_recent" (plist-get out :truncated_at)))
    (should (null (plist-get out :bough_recent)))))

(ert-deftest dl-satan-memory-evidence/truncate-output-json-serializes ()
  "`:truncated_at' entries must survive `json-serialize'.  Symbols
fail `json-value-p' once `dl-satan-audit--write-json' (percept.json,
bundle.json) or `dl-satan-jsonl-send' (tool results) carries the
truncated evidence."
  (require 'dl-satan-jsonl)
  (let* ((huge-ann (apply #'concat (make-list 500 "y")))
         (ev (list :bough_active
                   (list (list :nanoid "n1" :annotation huge-ann))))
         (out (dl-satan-memory-evidence--truncate ev 256 65536)))
    (should (stringp (json-serialize (dl-satan-jsonl-prepare out)
                                     :null-object :null
                                     :false-object :false)))))

;; ---------------------------------------------------------------------
;; Assemble (impure; tmp fixtures + non-existent bough binary)
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-memory-evidence/assemble-shape-and-bounds ()
  (dl-satan-memory-evidence-test--in-tmp tmp
   (let* ((ctx (list :time_now "2026-05-19T10:00:00+10:00"
                     :mode_name "motd"))
          (out (dl-satan-memory-evidence-assemble
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

(ert-deftest dl-satan-memory-evidence/assemble-with-bounds-honours-explicit-window ()
  "Phase 5.1 — `dl-satan-memory-evidence-assemble-with-bounds' lets
the caller supply START / END directly, bypassing the wrapper's
`time_now'-derived window.  Used by the Phase-5 observer to read
the panopticon slice covering a single intervention's 30-min
attribution window.  Wrapper still threads ctx-derived bounds when
called without an explicit start/end."
  (dl-satan-memory-evidence-test--in-tmp tmp
   (let* ((ctx (list :time_now "2026-05-19T10:00:00+10:00"
                     :mode_name "motd"))
          (start "2026-05-19T08:45:00+10:00")
          (end "2026-05-19T09:15:00+10:00")
          (out (dl-satan-memory-evidence-assemble-with-bounds
                start end ctx
                (list :behaviour_dir (file-name-as-directory tmp)
                      :cwd tmp))))
     (should (equal (plist-get out :window_start_at) start))
     (should (equal (plist-get out :window_end_at) end))
     ;; The wrapper still works identically for the default case.
     (let ((wrapper-out (dl-satan-memory-evidence-assemble
                         ctx (list :behaviour_dir (file-name-as-directory tmp)
                                   :cwd tmp))))
       (should (equal (plist-get wrapper-out :window_end_at)
                      "2026-05-19T10:00:00+10:00"))))))

(ert-deftest dl-satan-memory-evidence/assemble-cue-only-skips-heavy-probes ()
  "`:cue_only t' returns empty focus/browser segments and nil
bough_recent / bough_day even when those sources would otherwise
populate them.  Keeps current_window and bough_active."
  (dl-satan-memory-evidence-test--in-tmp tmp
   (let* ((current-dir (expand-file-name "current" tmp))
          (segments-dir (expand-file-name "segments" tmp)))
     (make-directory current-dir t)
     (make-directory segments-dir t)
     (with-temp-file (expand-file-name "sway.json" current-dir)
       (insert "{\"app_id\":\"firefox\",\"workspace\":\"main\"}"))
     (with-temp-file (expand-file-name "focus-2026-05-19.jsonl" segments-dir)
       (insert "{\"app_id\":\"firefox\",\"start_ts\":\"2026-05-19T09:55:00+10:00\",\"end_ts\":\"2026-05-19T09:58:00+10:00\",\"duration_s\":180}\n"))
     (cl-letf (((symbol-function 'dl-satan-memory-evidence--bough-recent)
                (lambda (&rest _) (error "should not be called"))))
       (cl-letf (((symbol-function 'dl-satan-memory-evidence--bough-day)
                  (lambda (&rest _) (error "should not be called"))))
         (let* ((ctx (list :time_now "2026-05-19T10:00:00+10:00"
                           :mode_name "motd"))
                (out (dl-satan-memory-evidence-assemble
                      ctx (list :behaviour_dir (file-name-as-directory tmp)
                                :cwd tmp
                                :cue_only t))))
           (should (equal (plist-get (plist-get out :current_window) :app_id)
                          "firefox"))
           (should (equal (plist-get out :focus_segments) '()))
           (should (equal (plist-get out :browser_segments) '()))
           (should (null (plist-get out :bough_recent)))
           (should (null (plist-get out :bough_day)))))))))

(ert-deftest dl-satan-memory-evidence/budget-exhausted-skips-optional-stages ()
  "Phase 5 — under an exhausted tick budget the OPTIONAL evidence
stages shed their work: `content_probe' / `bough_recent' / `bough_day'
skip, so their raw slots go nil, `sensor_status' `:content' degrades to
\"budget_skipped\", the skips land on the accumulator, and the percept
stays valid through `--truncate' + canon (no signal)."
  (dl-satan-memory-evidence-test--in-tmp tmp
   (let* ((dl-satan-trace--current
           (list :t0 (- (float-time) 100) :budget-ms 1
                 :stages nil :skipped nil))
          (ctx (list :time_now "2026-05-19T10:00:00+10:00"
                     :mode_name "motd"))
          (out (dl-satan-memory-evidence-assemble-with-bounds
                "2026-05-19T08:45:00+10:00"
                "2026-05-19T09:15:00+10:00"
                ctx
                (list :behaviour_dir (file-name-as-directory tmp)
                      :cwd tmp))))
     (should (null (plist-get out :bough_recent)))
     (should (null (plist-get out :bough_day)))
     (should (null (plist-get out :content_recent)))
     (should (equal (plist-get (plist-get out :sensor_status) :content)
                    "budget_skipped"))
     ;; the optional skips are recorded honestly on the accumulator
     (should (member "evidence.content_probe"
                     (plist-get dl-satan-trace--current :skipped)))
     (should (member "evidence.bough_recent"
                     (plist-get dl-satan-trace--current :skipped)))
     (should (member "evidence.bough_day"
                     (plist-get dl-satan-trace--current :skipped)))
     ;; degraded percept still canonicalizes (no signal, non-nil result)
     (should (dl-satan-memory-canon-canonicalize out nil ctx)))))

(ert-deftest dl-satan-memory-evidence/assemble-reads-panopticon ()
  (dl-satan-memory-evidence-test--in-tmp tmp
   (let* ((current-dir (expand-file-name "current" tmp))
          (segments-dir (expand-file-name "segments" tmp))
          (ctx (list :time_now "2026-05-19T10:00:00+10:00"
                     :mode_name "motd")))
     (make-directory current-dir t)
     (make-directory segments-dir t)
     (with-temp-file (expand-file-name "sway.json" current-dir)
       (insert "{\"app_id\":\"firefox\",\"workspace\":\"main\"}"))
     (with-temp-file (expand-file-name "focus-2026-05-19.jsonl" segments-dir)
       (insert "{\"app_id\":\"firefox\",\"start_ts\":\"2026-05-19T09:55:00+10:00\",\"end_ts\":\"2026-05-19T09:58:00+10:00\",\"duration_s\":180}\n")
       (insert "{\"app_id\":\"emacs\",\"start_ts\":\"2026-05-19T08:00:00+10:00\",\"end_ts\":\"2026-05-19T08:30:00+10:00\",\"duration_s\":1800}\n"))
     (let* ((out (dl-satan-memory-evidence-assemble
                  ctx (list :behaviour_dir (file-name-as-directory tmp)
                            :cwd tmp))))
       (should (equal (plist-get (plist-get out :current_window) :app_id)
                      "firefox"))
       ;; Only the in-window segment survives the filter.
       (should (= 1 (length (plist-get out :focus_segments))))
       (should (equal (plist-get (car (plist-get out :focus_segments))
                                 :app_id)
                      "firefox"))))))

(ert-deftest dl-satan-memory-evidence/assemble-git-state-on-repo ()
  ;; Initialize a tmp git repo so we don't depend on the host's layout
  ;; (the ambient ~/.emacs.d here is a bare-config worktree without a
  ;; nested .git/ directory).
  (skip-unless (executable-find "git"))
  (dl-satan-memory-evidence-test--in-tmp tmp
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
            (out (dl-satan-memory-evidence-assemble
                  ctx (list :behaviour_dir "/nonexistent/"
                            :cwd tmp))))
       (let ((git (plist-get out :git_state)))
         (should git)
         (should (stringp (plist-get git :head_short)))
         (should (= 1 (length (plist-get git :commits)))))))))

(ert-deftest dl-satan-memory-evidence/git-output-sets-optional-locks-env ()
  ;; Prove read-only git subprocesses observe GIT_OPTIONAL_LOCKS=0.
  ;; Stub `git' on `exec-path' with a shell script that echoes the env
  ;; var, so the assertion is deterministic (no real repo, no race).
  (dl-satan-memory-evidence-test--in-tmp tmp
   (let ((stub (expand-file-name "git" tmp)))
     (with-temp-file stub
       (insert "#!/bin/sh\n")
       (insert "printf '%s' \"$GIT_OPTIONAL_LOCKS\"\n"))
     (set-file-modes stub #o755)
     (let ((exec-path (cons tmp exec-path)))
       (should (equal (dl-satan-memory-evidence--git-output "status")
                      "0"))))))

;; ---------------------------------------------------------------------
;; VT-2 — routed choke deadlines: git-output/git-state timeout marker,
;; bough timeout degrades bough_status.  `dl-satan-trace-call' is
;; stubbed so the timed-out branch is forced without a real hang.
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-memory-evidence/git-output-timeout-returns-nil ()
  "A routed git call that breaches its deadline → nil (non-zero exit)."
  (cl-letf (((symbol-function 'dl-satan-trace-call)
             (lambda (&rest _)
               (list :exit 124 :stdout "" :timed-out t))))
    (should (null (dl-satan-memory-evidence--git-output "status")))))

(ert-deftest dl-satan-memory-evidence/git-state-marks-timed_out ()
  "When a routed sub-call times out, `--git-state' adds `:timed_out t' so
a partial read is never mistaken for a clean repo.  The `--git-dir'
probe succeeds; the follow-up probes time out."
  (dl-satan-memory-evidence-test--in-tmp tmp
   (cl-letf (((symbol-function 'dl-satan-trace-call)
              (lambda (_program args &rest _)
                (if (member "--git-dir" args)
                    (list :exit 0 :stdout ".git" :timed-out nil)
                  (list :exit 124 :stdout "" :timed-out t)))))
     (let ((state (dl-satan-memory-evidence--git-state tmp)))
       (should state)
       (should (eq (plist-get state :timed_out) t))))))

(ert-deftest dl-satan-memory-evidence/bough-timeout-degrades-status ()
  "A bough call that times out counts as an attempt but not ok, so the
synthesised bough_status degrades to `unreachable'."
  (let ((dl-satan-memory-evidence--bough-tracking t)
        (dl-satan-memory-evidence--bough-attempts 0)
        (dl-satan-memory-evidence--bough-ok 0)
        (dl-satan-bough-program (or (executable-find "sh") "/bin/sh")))
    (cl-letf (((symbol-function 'dl-satan-trace-call)
               (lambda (&rest _)
                 (list :exit 124 :stdout "" :timed-out t))))
      (should (null (dl-satan-memory-evidence--bough-call "active")))
      (should (equal (dl-satan-memory-evidence--bough-status)
                     "unreachable")))))

;; ---------------------------------------------------------------------
;; Git-activity feed (bursty — NEVER stale)
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-memory-evidence/git-feed-paths-same-day ()
  (let ((paths (dl-satan-memory-evidence--git-feed-paths
                "/beh/" "2026-05-19T09:50:00+10:00"
                "2026-05-19T10:00:00+10:00")))
    (should (= 1 (length paths)))
    (should (string-suffix-p "segments/git-2026-05-19.jsonl" (car paths)))))

(ert-deftest dl-satan-memory-evidence/git-feed-paths-cross-midnight ()
  (let ((paths (dl-satan-memory-evidence--git-feed-paths
                "/beh/" "2026-05-19T23:55:00+10:00"
                "2026-05-20T00:05:00+10:00")))
    (should (= 2 (length paths)))
    (should (string-suffix-p "segments/git-2026-05-19.jsonl" (nth 0 paths)))
    (should (string-suffix-p "segments/git-2026-05-20.jsonl" (nth 1 paths)))))

(ert-deftest dl-satan-memory-evidence/git-feed-paths-multiday ()
  "VT-feed-paths-multiday: 24h+ horizon enumerates every calendar day.
A window spanning three dates returns three paths, not just the
endpoints.  This was a latent bug: the old implementation returned
only start-day + end-day, missing intermediate days."
  (let ((paths (dl-satan-memory-evidence--git-feed-paths
                "/beh/" "2026-05-19T00:05:00+10:00"
                "2026-05-21T23:55:00+10:00")))
    (should (= 3 (length paths)))
    (should (string-suffix-p "segments/git-2026-05-19.jsonl" (nth 0 paths)))
    (should (string-suffix-p "segments/git-2026-05-20.jsonl" (nth 1 paths)))
    (should (string-suffix-p "segments/git-2026-05-21.jsonl" (nth 2 paths)))))

(ert-deftest dl-satan-memory-evidence/git-feed-paths-dst-fallback ()
  "Calendar-day enumeration survives DST fall-back.
Melbourne 2026-04-05: 03:00 AEDT → 02:00 AEST.  The old +86400s
step would skip a date; calendar arithmetic does not."
  (let ((paths (dl-satan-memory-evidence--git-feed-paths
                "/beh/" "2026-04-04T23:00:00+11:00"
                "2026-04-06T01:00:00+10:00")))
    (should (= 3 (length paths)))
    (should (string-suffix-p "segments/git-2026-04-04.jsonl" (nth 0 paths)))
    (should (string-suffix-p "segments/git-2026-04-05.jsonl" (nth 1 paths)))
    (should (string-suffix-p "segments/git-2026-04-06.jsonl" (nth 2 paths)))))

(ert-deftest dl-satan-memory-evidence/git-feed-paths-next-day ()
  "--next-day produces the correct next calendar date."
  (should (equal "2026-05-20"
                 (dl-satan-memory-evidence--next-day "2026-05-19")))
  (should (equal "2026-06-01"
                 (dl-satan-memory-evidence--next-day "2026-05-31")))
  (should (equal "2026-01-01"
                 (dl-satan-memory-evidence--next-day "2025-12-31")))
  ;; Leap year: 2024-02-28 → 2024-02-29
  (should (equal "2024-02-29"
                 (dl-satan-memory-evidence--next-day "2024-02-28"))))

(ert-deftest dl-satan-memory-evidence/git-commits-in-window ()
  (dl-satan-memory-evidence-test--in-tmp tmp
   (let ((path (expand-file-name "git-2026-05-19.jsonl" tmp)))
     (with-temp-file path
       (insert "{\"repo\":\"/r/satan\",\"slug\":\"satan\",\"start_ts\":\"2026-05-19T09:55:00+10:00\",\"end_ts\":\"2026-05-19T09:55:00+10:00\"}\n"))
     (let ((probe (dl-satan-memory-evidence--git-commits-status
                   (list path) "2026-05-19T09:50:00+10:00"
                   "2026-05-19T10:00:00+10:00" 10)))
       (should (equal "ok" (car probe)))
       (should (= 1 (length (cdr probe))))
       (should (equal "satan" (plist-get (car (cdr probe)) :slug)))))))

(ert-deftest dl-satan-memory-evidence/git-commits-bursty-old-still-ok ()
  "A days-old newest commit is NORMAL: status stays \"ok\" (never
\"stale-Nm\", unlike focus/browser) and only the in-window slice is
returned (here empty).  This is the divergent-freshness contract."
  (dl-satan-memory-evidence-test--in-tmp tmp
   (let ((path (expand-file-name "git-2026-05-19.jsonl" tmp)))
     (with-temp-file path
       (insert "{\"repo\":\"/r\",\"slug\":\"r\",\"start_ts\":\"2026-05-16T09:00:00+10:00\",\"end_ts\":\"2026-05-16T09:00:00+10:00\"}\n"))
     (let ((probe (dl-satan-memory-evidence--git-commits-status
                   (list path) "2026-05-19T09:50:00+10:00"
                   "2026-05-19T10:00:00+10:00" 10)))
       (should (equal "ok" (car probe)))
       (should (equal '() (cdr probe)))))))

(ert-deftest dl-satan-memory-evidence/git-commits-missing ()
  (dl-satan-memory-evidence-test--in-tmp tmp
   (let ((probe (dl-satan-memory-evidence--git-commits-status
                 (list (expand-file-name "git-nope.jsonl" tmp))
                 "2026-05-19T09:50:00+10:00"
                 "2026-05-19T10:00:00+10:00" 10)))
     (should (equal "missing" (car probe)))
     (should (equal '() (cdr probe))))))

(ert-deftest dl-satan-memory-evidence/git-commits-malformed ()
  "Single malformed file with no readable siblings → \"malformed\"."
  (dl-satan-memory-evidence-test--in-tmp tmp
   (let ((path (expand-file-name "git-2026-05-19.jsonl" tmp)))
     (with-temp-file path (insert "{not json}\n"))
     (let ((probe (dl-satan-memory-evidence--git-commits-status
                   (list path) "2026-05-19T09:50:00+10:00"
                   "2026-05-19T10:00:00+10:00" 10)))
       (should (equal "malformed" (car probe)))))))

(ert-deftest dl-satan-memory-evidence/git-commits-malformed-tolerant ()
  "VT-malformed-tolerance: one bad file among good siblings doesn't blank
all commits.  Good rows from the readable file survive."
  (dl-satan-memory-evidence-test--in-tmp tmp
   (let ((good-path (expand-file-name "git-2026-05-19.jsonl" tmp))
         (bad-path (expand-file-name "git-2026-05-18.jsonl" tmp)))
     (with-temp-file good-path
       (insert "{\"repo\":\"/r/x\",\"slug\":\"x\",\"start_ts\":\"2026-05-19T09:55:00+10:00\",\"end_ts\":\"2026-05-19T09:55:00+10:00\"}\n"))
     (with-temp-file bad-path
       (insert "{not json}\n"))
     (let ((probe (dl-satan-memory-evidence--git-commits-status
                   (list bad-path good-path)
                   "2026-05-19T09:50:00+10:00"
                   "2026-05-19T10:00:00+10:00" 10)))
       (should (equal "ok" (car probe)))
       (should (= 1 (length (cdr probe))))
       (should (equal "x" (plist-get (car (cdr probe)) :slug)))))))

(ert-deftest dl-satan-memory-evidence/git-commits-sorted-by-end-ts ()
  "VT-sort-limit: newest commit is genuinely the last after sorting by
:end_ts, regardless of append order in the files."
  (dl-satan-memory-evidence-test--in-tmp tmp
   (let ((path (expand-file-name "git-2026-05-19.jsonl" tmp)))
     ;; Write rows in non-chronological order.
     (with-temp-file path
       (insert "{\"repo\":\"/r/a\",\"slug\":\"middle\",\"start_ts\":\"2026-05-19T09:52:00+10:00\",\"end_ts\":\"2026-05-19T09:52:00+10:00\"}\n")
       (insert "{\"repo\":\"/r/b\",\"slug\":\"newest\",\"start_ts\":\"2026-05-19T09:58:00+10:00\",\"end_ts\":\"2026-05-19T09:58:00+10:00\"}\n")
       (insert "{\"repo\":\"/r/c\",\"slug\":\"oldest\",\"start_ts\":\"2026-05-19T09:51:00+10:00\",\"end_ts\":\"2026-05-19T09:51:00+10:00\"}\n"))
     (let* ((probe (dl-satan-memory-evidence--git-commits-status
                    (list path) "2026-05-19T09:50:00+10:00"
                    "2026-05-19T10:00:00+10:00" 10))
            (commits (cdr probe)))
       (should (equal "ok" (car probe)))
       (should (= 3 (length commits)))
       (should (equal "oldest" (plist-get (nth 0 commits) :slug)))
       (should (equal "middle" (plist-get (nth 1 commits) :slug)))
       (should (equal "newest" (plist-get (nth 2 commits) :slug)))))))

(ert-deftest dl-satan-memory-evidence/git-window-sees-commit-outside-10min ()
  "VT-git-window: a commit 15 min ago (outside the 10-min focus window
but inside the 24h git window) appears in :git_commits.
Focus/browser segments remain on the 10-min window."
  (dl-satan-memory-evidence-test--in-tmp tmp
   (let* ((segments-dir (expand-file-name "segments" tmp))
          (git-start-iso
           (dl-satan-memory-evidence--iso-format
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
            (out (dl-satan-memory-evidence-assemble
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

(ert-deftest dl-satan-memory-evidence/git-window-field-distinct ()
  "VT-git-window-field: :git_window_start_at is present and strictly
eaerlier than :window_start_at when git-window > window-minutes."
  (dl-satan-memory-evidence-test--in-tmp tmp
   (let* ((ctx (list :time_now "2026-05-19T10:00:00+10:00"
                     :mode_name "motd"))
          (out (dl-satan-memory-evidence-assemble
                ctx (list :behaviour_dir (file-name-as-directory tmp)
                          :cwd tmp)))
          (git-start (plist-get out :git_window_start_at))
          (win-start (plist-get out :window_start_at)))
     (should (stringp git-start))
     (should (stringp win-start))
     ;; git-start should be earlier (wider window).
     (should (time-less-p (date-to-time git-start)
                          (date-to-time win-start))))))

(ert-deftest dl-satan-memory-evidence/assemble-reads-git-feed ()
  "End-to-end: the feed surfaces as `:git_commits' + `:git' sensor_status."
  (dl-satan-memory-evidence-test--in-tmp tmp
   (let* ((segments-dir (expand-file-name "segments" tmp))
          (ctx (list :time_now "2026-05-19T10:00:00+10:00" :mode_name "motd")))
     (make-directory segments-dir t)
     (with-temp-file (expand-file-name "git-2026-05-19.jsonl" segments-dir)
       (insert "{\"repo\":\"/r/satan\",\"slug\":\"satan\",\"start_ts\":\"2026-05-19T09:55:00+10:00\",\"end_ts\":\"2026-05-19T09:55:00+10:00\"}\n"))
     (let* ((out (dl-satan-memory-evidence-assemble
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

(ert-deftest dl-satan-memory-evidence/sensor-status-all-missing ()
  "No sensor files: every probe reports \"missing\".  Bough is \"ok\"
because no calls are attempted (the binary's missing → tool errors
→ ok-payload nil with attempts=0 → reported as ok per §S6 fallback)."
  (dl-satan-memory-evidence-test--in-tmp tmp
   (let* ((ctx (list :time_now "2026-05-19T10:00:00+10:00"
                     :mode_name "motd"))
          (out (dl-satan-memory-evidence-assemble
                ctx (list :behaviour_dir (file-name-as-directory tmp)
                          :cwd tmp)))
          (ss (plist-get out :sensor_status)))
     (should (equal "missing" (plist-get ss :current_window)))
     (should (equal "missing" (plist-get ss :focus)))
     (should (equal "missing" (plist-get ss :browser))))))

(ert-deftest dl-satan-memory-evidence/sensor-status-current-stale-drops-slice ()
  "When sway.json mtime exceeds the threshold, :current_window is
dropped from the evidence (set nil) AND the status is tagged
\"stale-Nm\"."
  (dl-satan-memory-evidence-test--in-tmp tmp
   (let* ((current-dir (expand-file-name "current" tmp))
          (sway-path (expand-file-name "sway.json" current-dir))
          (ctx (list :time_now "2026-05-19T10:00:00+10:00"
                     :mode_name "motd")))
     (make-directory current-dir t)
     (with-temp-file sway-path
       (insert "{\"app_id\":\"firefox\",\"workspace\":\"main\"}"))
     (let ((old (time-subtract (date-to-time "2026-05-19T10:00:00+10:00")
                               (seconds-to-time (* 60 28)))))
       (set-file-times sway-path old))
     (let* ((out (dl-satan-memory-evidence-assemble
                  ctx (list :behaviour_dir (file-name-as-directory tmp)
                            :cwd tmp)))
            (ss (plist-get out :sensor_status)))
       (should (null (plist-get out :current_window)))
       (should (equal (plist-get ss :current_window) "stale-28m"))))))

(ert-deftest dl-satan-memory-evidence/sensor-status-current-fresh-keeps-slice ()
  (dl-satan-memory-evidence-test--in-tmp tmp
   (let* ((current-dir (expand-file-name "current" tmp))
          (sway-path (expand-file-name "sway.json" current-dir))
          (ctx (list :time_now (format-time-string "%Y-%m-%dT%T%:z")
                     :mode_name "motd")))
     (make-directory current-dir t)
     (with-temp-file sway-path
       (insert "{\"app_id\":\"firefox\",\"workspace\":\"main\"}"))
     (let* ((out (dl-satan-memory-evidence-assemble
                  ctx (list :behaviour_dir (file-name-as-directory tmp)
                            :cwd tmp)))
            (ss (plist-get out :sensor_status)))
       (should (equal (plist-get (plist-get out :current_window) :app_id)
                      "firefox"))
       (should (equal "ok" (plist-get ss :current_window)))))))

(ert-deftest dl-satan-memory-evidence/sensor-status-segments-stale ()
  "Segments file whose newest :end_ts is past the 30-min threshold
reports \"stale-Nm\" and the slice drops to '()."
  (dl-satan-memory-evidence-test--in-tmp tmp
   (let* ((segments-dir (expand-file-name "segments" tmp))
          (ctx (list :time_now "2026-05-19T10:00:00+10:00"
                     :mode_name "motd")))
     (make-directory segments-dir t)
     (with-temp-file (expand-file-name "focus-2026-05-19.jsonl" segments-dir)
       (insert "{\"app_id\":\"firefox\",\"start_ts\":\"2026-05-19T08:55:00+10:00\",\"end_ts\":\"2026-05-19T08:58:00+10:00\",\"duration_s\":180}\n"))
     (let* ((out (dl-satan-memory-evidence-assemble
                  ctx (list :behaviour_dir (file-name-as-directory tmp)
                            :cwd tmp)))
            (ss (plist-get out :sensor_status)))
       (should (equal '() (plist-get out :focus_segments)))
       (should (equal "stale-62m" (plist-get ss :focus)))))))

(ert-deftest dl-satan-memory-evidence/sensor-status-malformed-json ()
  "Malformed sway.json → status \"malformed\", slice nil."
  (dl-satan-memory-evidence-test--in-tmp tmp
   (let* ((current-dir (expand-file-name "current" tmp))
          (ctx (list :time_now (format-time-string "%Y-%m-%dT%T%:z")
                     :mode_name "motd")))
     (make-directory current-dir t)
     (with-temp-file (expand-file-name "sway.json" current-dir)
       (insert "{not-json"))
     (let* ((out (dl-satan-memory-evidence-assemble
                  ctx (list :behaviour_dir (file-name-as-directory tmp)
                            :cwd tmp)))
            (ss (plist-get out :sensor_status)))
       (should (null (plist-get out :current_window)))
       (should (equal "malformed" (plist-get ss :current_window)))))))

(ert-deftest dl-satan-memory-evidence/sensor-status-bough-unreachable ()
  "When `--bough-call' returns nil for every probe but tracking
recorded attempts, the bough status is \"unreachable\"."
  (dl-satan-memory-evidence-test--in-tmp tmp
   (cl-letf (((symbol-function 'dl-satan-memory-evidence--bough-call)
              (lambda (&rest _)
                (when dl-satan-memory-evidence--bough-tracking
                  (cl-incf dl-satan-memory-evidence--bough-attempts))
                nil)))
     (let* ((ctx (list :time_now "2026-05-19T10:00:00+10:00"
                       :mode_name "motd"))
            (out (dl-satan-memory-evidence-assemble
                  ctx (list :behaviour_dir (file-name-as-directory tmp)
                            :cwd tmp)))
            (ss (plist-get out :sensor_status)))
       (should (equal "unreachable" (plist-get ss :bough)))))))

(ert-deftest dl-satan-memory-evidence/sensor-status-bough-ok-when-any-succeeds ()
  "One successful bough call is enough to flip status to \"ok\"."
  (dl-satan-memory-evidence-test--in-tmp tmp
   (let ((call-n 0))
     (cl-letf (((symbol-function 'dl-satan-memory-evidence--bough-call)
                (lambda (&rest _)
                  (when dl-satan-memory-evidence--bough-tracking
                    (cl-incf dl-satan-memory-evidence--bough-attempts))
                  (cl-incf call-n)
                  (cond
                   ((= call-n 1)
                    (when dl-satan-memory-evidence--bough-tracking
                      (cl-incf dl-satan-memory-evidence--bough-ok))
                    (list :nodes '()))
                   (t nil)))))
       (let* ((ctx (list :time_now "2026-05-19T10:00:00+10:00"
                         :mode_name "motd"))
              (out (dl-satan-memory-evidence-assemble
                    ctx (list :behaviour_dir (file-name-as-directory tmp)
                              :cwd tmp)))
              (ss (plist-get out :sensor_status)))
         (should (equal "ok" (plist-get ss :bough))))))))

;; ---------------------------------------------------------------------
;; Cross-step contract: canon eats assembler output.
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-memory-evidence/canon-eats-output-minimal ()
  (dl-satan-memory-evidence-test--in-tmp tmp
   (let* ((current-dir (expand-file-name "current" tmp))
          (ctx (list :time_now "2026-05-19T10:00:00+10:00"
                     :mode_name "motd"
                     :current_grammar_version 1)))
     (make-directory current-dir t)
     (with-temp-file (expand-file-name "sway.json" current-dir)
       (insert "{\"app_id\":\"firefox\",\"workspace\":\"main\"}"))
     (let* ((ev (dl-satan-memory-evidence-assemble
                 ctx (list :behaviour_dir (file-name-as-directory tmp)
                           :cwd tmp)))
            (canon (dl-satan-memory-canon-canonicalize ev nil ctx))
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

(ert-deftest dl-satan-memory-evidence/newest-segment-end-single-offset ()
  "All-same-offset: returns the max instant (unchanged behaviour)."
  (should (equal "2026-05-29T19:00:00+10:00"
                 (dl-satan-memory-evidence--newest-segment-end
                  (list '(:end_ts "2026-05-29T17:00:00+10:00")
                        '(:end_ts "2026-05-29T19:00:00+10:00")
                        '(:end_ts "2026-05-29T18:00:00+10:00"))))))

(ert-deftest dl-satan-memory-evidence/newest-segment-end-mixed-offset ()
  "Mixed `Z' + `+10:00': newest by INSTANT wins even when its string
sorts lower.  `2026-05-29T08:00:00Z' (= 18:00 +10:00) is later than
`2026-05-29T17:00:00+10:00' (= 07:00Z) but `\"17\"' > `\"08\"' as a
string, so a `string>'-based selector returns the wrong (older) entry."
  (should (equal "2026-05-29T08:00:00Z"
                 (dl-satan-memory-evidence--newest-segment-end
                  (list '(:end_ts "2026-05-29T17:00:00+10:00")
                        '(:end_ts "2026-05-29T08:00:00Z"))))))

(ert-deftest dl-satan-memory-evidence/newest-segment-end-empty ()
  "No segments / no parseable `:end_ts' → nil."
  (should (null (dl-satan-memory-evidence--newest-segment-end nil)))
  (should (null (dl-satan-memory-evidence--newest-segment-end
                 '((:start_ts "2026-05-29T17:00:00+10:00"))))))

(provide 'dl-satan-memory-evidence-test)
;;; dl-satan-memory-evidence-test.el ends here
