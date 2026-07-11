;;; satan-memory-canon-test.el --- canonicalizer tests -*- lexical-binding: t; -*-

;; Run from CLI:
;;   emacs --batch \
;;     -L ~/.emacs.d/core -L ~/.emacs.d/satan -L ~/.emacs.d/satan/test \
;;     -l satan-memory-canon-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'json)
(require 'satan-memory-grammar)
(require 'satan-memory-canon)

(defconst satan-memory-canon-test--fixture-dir
  (expand-file-name "canon-fixtures/"
                    (file-name-directory
                     (or load-file-name buffer-file-name
                         (locate-library "satan-memory-canon-test")))))

;; ---------- pure helpers ----------

(ert-deftest satan-memory-canon/slugify ()
  (should (equal "github-com" (satan-memory-canon--slugify "GitHub.com")))
  (should (equal "rust" (satan-memory-canon--slugify "  Rust  ")))
  (should (equal "x" (satan-memory-canon--slugify "--X--")))
  (should (null (satan-memory-canon--slugify "---")))
  (should (null (satan-memory-canon--slugify ""))))

(ert-deftest satan-memory-canon/app-surface ()
  (should (equal "browser" (satan-memory-canon--app-surface "firefox")))
  (should (equal "editor"  (satan-memory-canon--app-surface "emacs")))
  (should (equal "terminal"
                 (satan-memory-canon--app-surface "com.mitchellh.ghostty")))
  (should (equal "desktop" (satan-memory-canon--app-surface "Gimp"))))

(ert-deftest satan-memory-canon/file-kind ()
  (should (equal "source" (satan-memory-canon--file-kind "/x/y.rs")))
  (should (equal "org"    (satan-memory-canon--file-kind "/x/y.org")))
  (should (equal "data"   (satan-memory-canon--file-kind "/x/y.json")))
  (should (null (satan-memory-canon--file-kind "/no/extension"))))

(ert-deftest satan-memory-canon/domain-kind ()
  (should (equal "repo_hosting"
                 (satan-memory-canon--domain-kind "github.com")))
  (should (equal "search"
                 (satan-memory-canon--domain-kind "duckduckgo.com")))
  (should (null (satan-memory-canon--domain-kind "no.such.tld"))))

;; ---------- hint normalization ----------

(ert-deftest satan-memory-canon/normalize-kind-default ()
  (let ((r (satan-memory-canon-normalize-hints nil)))
    (should (equal "observation"
                   (plist-get (plist-get r :normalized) :kind)))
    (should (null (plist-get r :rejected)))))

(ert-deftest satan-memory-canon/normalize-kind-rejected ()
  (let* ((r (satan-memory-canon-normalize-hints (list :kind "weird")))
         (rej (plist-get r :rejected)))
    (should (= 1 (length rej)))
    (should (eq 'kind (plist-get (car rej) :field)))
    (should (member "observation"
                    (plist-get (car rej) :suggestions)))))

(ert-deftest satan-memory-canon/normalize-phase-alias ()
  ;; No phase alias exists in v1; verify a real closed value passes.
  (let* ((r (satan-memory-canon-normalize-hints
             (list :phase "execution"))))
    (should (equal "execution"
                   (plist-get (plist-get r :normalized) :phase)))))

(ert-deftest satan-memory-canon/normalize-phase-rejected-with-suggestions ()
  (let* ((r (satan-memory-canon-normalize-hints
             (list :phase "executino")))
         (rej (car (plist-get r :rejected))))
    (should (eq 'phase (plist-get rej :field)))
    (should (member "execution" (plist-get rej :suggestions)))))

(ert-deftest satan-memory-canon/normalize-valence ()
  (let ((r (satan-memory-canon-normalize-hints (list :valence "neutral"))))
    (should (equal "neutral"
                   (plist-get (plist-get r :normalized) :valence)))))

(ert-deftest satan-memory-canon/normalize-topic-slugs-and-caps ()
  (let* ((r (satan-memory-canon-normalize-hints
             (list :topic '("Rust" "rust" "Postgres!" "x" "y" "z" "w" "v"))))
         (topics (plist-get (plist-get r :normalized) :topic)))
    (should (member "rust" topics))
    (should (member "postgres" topics))
    (should (= (length topics) satan-memory-canon--max-topic-count))
    ;; dedup
    (should (= 1 (cl-count "rust" topics :test #'equal)))))

(ert-deftest satan-memory-canon/normalize-focal-bough-nanoid-rejects-bad-shape ()
  (let* ((r (satan-memory-canon-normalize-hints
             (list :focal_bough_nanoid "has space")))
         (rej (car (plist-get r :rejected))))
    (should (eq 'focal_bough_nanoid (plist-get rej :field)))))

;; ---------- individual rule tests ----------

(defun satan-memory-canon-test--rule (id ev hints ctx)
  "Invoke a single rule by ID for a single-rule test."
  (let ((fn (cdr (assq id satan-memory-canon--rules))))
    (unless fn (error "no such rule: %s" id))
    (funcall fn ev hints ctx)))

(ert-deftest satan-memory-canon/rule-current-app ()
  (let ((emits (satan-memory-canon-test--rule
                'panopticon.current.app
                (list :current_window (list :app_id "firefox"))
                nil nil)))
    (should (= 2 (length emits)))
    (should (member "app:firefox"
                    (mapcar (lambda (e) (plist-get e :handle)) emits)))
    (should (member "surface:browser"
                    (mapcar (lambda (e) (plist-get e :handle)) emits)))))

(ert-deftest satan-memory-canon/rule-surface-transition ()
  (let* ((emits (satan-memory-canon-test--rule
                 'panopticon.surface_transition
                 (list :focus_segments
                       (list (list :app_id "Alacritty")
                             (list :app_id "firefox")))
                 nil nil))
         (handles (mapcar (lambda (e) (plist-get e :handle)) emits)))
    (should (member "surface_transition:terminal->browser" handles))))

(ert-deftest satan-memory-canon/rule-surface-transition-skips-unknown ()
  ;; desktop->desktop never appears as a closed-world value: no emission.
  (let ((emits (satan-memory-canon-test--rule
                'panopticon.surface_transition
                (list :focus_segments
                      (list (list :app_id "Gimp")
                            (list :app_id "Gimp")))
                nil nil)))
    (should (null emits))))

(ert-deftest satan-memory-canon/rule-event-transition-inert ()
  (should (null (satan-memory-canon-test--rule
                 'panopticon.event_transition nil nil nil))))

(ert-deftest satan-memory-canon/rule-docs-visit ()
  (let ((emits (satan-memory-canon-test--rule
                'panopticon.docs_visit
                (list :browser_segments
                      (list (list :domain "github.com")
                            (list :domain "docs.python.org")))
                nil nil)))
    (should (equal "domain_kind:docs" (plist-get (car emits) :handle)))))

(ert-deftest satan-memory-canon/rule-bough-recent-status-change ()
  (let* ((emits (satan-memory-canon-test--rule
                 'bough.recent_status_change
                 (list :bough_recent
                       (list (list :nanoid "abc1234"
                                   :event "status_changed"
                                   :from "todo" :to "doing")))
                 nil nil))
         (handles (mapcar (lambda (e) (plist-get e :handle)) emits)))
    (should (member "bough_event:status_changed" handles))
    (should (member "artifact:bough_status_change" handles))))

(ert-deftest satan-memory-canon/rule-bough-active-focus ()
  (let* ((emits (satan-memory-canon-test--rule
                 'bough.active_focus
                 (list :bough_active
                       (list (list :nanoid "abc1234"
                                   :project_nanoid "PROJ001"
                                   :status "doing")))
                 (list :focal_bough_nanoid "abc1234")
                 nil))
         (handles (mapcar (lambda (e) (plist-get e :handle)) emits)))
    (should (member "bough_node:abc1234" handles))
    (should (member "bough_project:PROJ001" handles))))

(ert-deftest satan-memory-canon/rule-cwd-project-from-remote ()
  (let* ((emits (satan-memory-canon-test--rule
                 'cwd.project
                 (list :git_state
                       (list :remote "git@github.com:david/satan.git"))
                 nil nil)))
    (should (equal "project:satan" (plist-get (car emits) :handle)))
    (should (eq 'observed (plist-get (car emits) :origin)))))

(ert-deftest satan-memory-canon/rule-cwd-project-from-cwd ()
  (let* ((emits (satan-memory-canon-test--rule
                 'cwd.project
                 (list :fs_state (list :cwd "/home/david/dev/myproj"))
                 nil nil)))
    (should (equal "project:myproj" (plist-get (car emits) :handle)))
    (should (eq 'derived (plist-get (car emits) :origin)))))

(ert-deftest satan-memory-canon/rule-vcs-recent-commit ()
  "Each repo in :git_commits emits project:<slug>, deduped, origin observed.
Slug resolves from :slug, else :remote tail, else :repo basename."
  (let* ((emits (satan-memory-canon-test--rule
                 'vcs.recent_commit
                 (list :git_commits
                       (list (list :slug "satan" :repo "/home/david/dev/satan")
                             (list :slug "satan" :repo "/home/david/dev/satan")
                             (list :remote "git@github.com:david/bough.git")))
                 nil nil))
         (handles (mapcar (lambda (e) (plist-get e :handle)) emits)))
    ;; "satan" deduped to one despite two rows; bough derived from remote.
    (should (equal '("project:satan" "project:bough") handles))
    (should (eq 'observed (plist-get (car emits) :origin)))))

(ert-deftest satan-memory-canon/rule-vcs-recent-commit-empty ()
  (should (null (satan-memory-canon-test--rule
                 'vcs.recent_commit (list :git_commits nil) nil nil))))

(ert-deftest satan-memory-canon/rule-cwd-file-kind ()
  (let ((emits (satan-memory-canon-test--rule
                'cwd.file_kind
                (list :fs_state
                      (list :recent_files '("/x/y.rs" "/x/y.org")))
                nil nil)))
    (should (equal "file_kind:source" (plist-get (car emits) :handle)))))

(ert-deftest satan-memory-canon/rule-ctx-mode ()
  (let ((emits (satan-memory-canon-test--rule
                'ctx.mode nil nil (list :mode_name "motd"))))
    (should (equal "mode:motd" (plist-get (car emits) :handle))))
  ;; unknown mode -> no emission
  (should (null (satan-memory-canon-test--rule
                 'ctx.mode nil nil (list :mode_name "bogus")))))

(ert-deftest satan-memory-canon/rule-time-day-week ()
  (let* ((emits (satan-memory-canon-test--rule
                 'time.day_week nil nil
                 (list :time_now "2026-05-19T10:00:00+10:00")))
         (handles (mapcar (lambda (e) (plist-get e :handle)) emits)))
    (should (member "day:2026-05-19" handles))
    ;; Don't hard-code the ISO week — just check shape.
    (should (cl-find-if (lambda (h) (string-match "\\`week:[0-9]\\{4\\}-W[0-9]\\{2\\}\\'" h))
                        handles))))

(ert-deftest satan-memory-canon/rule-hint-topic ()
  (let ((emits (satan-memory-canon-test--rule
                'hint.topic nil
                (list :topic '("rust" "postgres")) nil)))
    (should (equal '("topic:rust" "topic:postgres")
                   (mapcar (lambda (e) (plist-get e :handle)) emits)))
    (should (eq 'hint (plist-get (car emits) :origin)))))

(ert-deftest satan-memory-canon/rule-hint-phase ()
  (let ((emits (satan-memory-canon-test--rule
                'hint.phase nil (list :phase "execution") nil)))
    (should (equal "phase:execution" (plist-get (car emits) :handle)))))

(ert-deftest satan-memory-canon/rule-hint-focal-app ()
  (let ((emits (satan-memory-canon-test--rule
                'hint.focal_app nil (list :focal_app "firefox") nil)))
    (should (equal "app:firefox" (plist-get (car emits) :handle)))
    (should (eq 'hint (plist-get (car emits) :origin)))))

;; ---------- merge / dedupe ----------

(ert-deftest satan-memory-canon/origin-priority-observed-wins ()
  ;; hints.focal_app and current_window.app_id both produce app:firefox.
  ;; observed should win over hint.
  (let* ((res (satan-memory-canon-canonicalize
               (list :current_window (list :app_id "firefox"))
               (list :focal_app "firefox")
               (list :time_now "2026-05-19T10:00:00+10:00"
                     :current_grammar_version 1)))
         (sources (plist-get res :handle_sources))
         (src (cdr (assoc "app:firefox" sources))))
    (should (member "app:firefox" (plist-get res :handles)))
    (should (equal "observed" (plist-get src :origin)))))

(ert-deftest satan-memory-canon/handles-sorted-stable ()
  (let* ((res (satan-memory-canon-canonicalize
               (list :current_window (list :app_id "emacs"))
               nil
               (list :mode_name "morning"
                     :time_now "2026-05-19T10:00:00+10:00"
                     :current_grammar_version 1)))
         (handles (plist-get res :handles)))
    (should (equal handles (sort (copy-sequence handles) #'string<)))))

;; ---------- end-to-end via raw entry point ----------

(ert-deftest satan-memory-canon/raw-entry-merges-rejected ()
  (let* ((res (satan-memory-canon-canonicalize-from-raw
               nil
               (list :phase "executino")
               (list :time_now "2026-05-19T10:00:00+10:00"
                     :current_grammar_version 1)))
         (rej (plist-get res :rejected)))
    (should (= 1 (length rej)))
    (should (eq 'phase (plist-get (car rej) :field)))))

(ert-deftest satan-memory-canon/raw-entry-exposes-normalized ()
  (let* ((res (satan-memory-canon-canonicalize-from-raw
               nil
               (list :kind "intervention" :valence "positive"
                     :phase "orientation"
                     :topic '("UX") :focal_app "Firefox")
               (list :time_now "2026-05-19T10:00:00+10:00"
                     :current_grammar_version 1)))
         (norm (plist-get res :normalized)))
    (should (equal "intervention" (plist-get norm :kind)))
    (should (equal "positive"     (plist-get norm :valence)))
    (should (equal "orientation"  (plist-get norm :phase)))
    (should (equal '("ux")        (plist-get norm :topic)))
    (should (equal "firefox"      (plist-get norm :focal_app)))))

;; ---------- golden fixtures ----------

(defun satan-memory-canon-test--load-fixture (name)
  (let* ((path (expand-file-name (concat name ".json")
                                 satan-memory-canon-test--fixture-dir))
         (json-object-type 'plist)
         (json-array-type 'list)
         (json-key-type 'keyword)
         (json-false :json-false)
         (json-null nil))
    (with-temp-buffer
      (insert-file-contents path)
      (goto-char (point-min))
      (json-read))))

(defun satan-memory-canon-test--run-fixture (name)
  (let* ((fx (satan-memory-canon-test--load-fixture name))
         (res (satan-memory-canon-canonicalize-from-raw
               (plist-get fx :evidence)
               (plist-get fx :hints)
               (plist-get fx :ctx))))
    (cons fx res)))

(ert-deftest satan-memory-canon/fixture-minimal-firefox ()
  (let* ((pair (satan-memory-canon-test--run-fixture "minimal_firefox"))
         (fx (car pair))
         (res (cdr pair)))
    (should (equal (sort (copy-sequence (plist-get fx :expected_handles))
                         #'string<)
                   (plist-get res :handles)))
    (should (null (plist-get res :rejected)))))

(ert-deftest satan-memory-canon/fixture-rich-window ()
  (let* ((pair (satan-memory-canon-test--run-fixture "rich_window"))
         (fx (car pair))
         (res (cdr pair)))
    (should (equal (sort (copy-sequence (plist-get fx :expected_handles))
                         #'string<)
                   (plist-get res :handles)))))

;; ---------- PURITY GREP-LINT ----------
;;
;; The canonicalizer module must remain pure.  This test reads every
;; form in `satan-memory-canon.el' and refuses if any of the
;; forbidden symbols appear in code (comments are stripped by `read').
;; See `memory.design.md' §3.5.

(defconst satan-memory-canon-test--forbidden-symbols
  '(shell-command shell-command-to-string
    call-process call-process-region call-process-shell-command
    start-process start-process-shell-command
    insert-file-contents insert-file-contents-literally
    write-region write-file
    url-retrieve url-retrieve-synchronously
    current-time current-time-string current-time-zone
    ;; bough invocations are not symbols but a coarse check anyway —
    ;; any `satan-bough-' or `satan-tool/bough' reference is
    ;; equally fatal.
    satan-bough--invoke
    satan-tool/bough-read))

(defun satan-memory-canon-test--read-forms (path)
  (with-temp-buffer
    (insert-file-contents path)
    (goto-char (point-min))
    (let (forms)
      (condition-case nil
          (while t (push (read (current-buffer)) forms))
        (end-of-file (nreverse forms))))))

(defun satan-memory-canon-test--contains-symbol-p (form sym)
  (cond
   ((eq form sym) t)
   ((consp form)
    (or (satan-memory-canon-test--contains-symbol-p (car form) sym)
        (satan-memory-canon-test--contains-symbol-p (cdr form) sym)))
   (t nil)))

(ert-deftest satan-memory-canon/purity-grep-lint ()
  "Every form in satan-memory-canon.el must be free of forbidden symbols."
  (let* ((path (locate-library "satan-memory-canon"))
         (forms (and path
                     (satan-memory-canon-test--read-forms
                      (if (string-suffix-p ".elc" path)
                          (concat (substring path 0 -1)) ; .elc -> .el
                        path)))))
    (should forms)
    (dolist (sym satan-memory-canon-test--forbidden-symbols)
      (when (satan-memory-canon-test--contains-symbol-p forms sym)
        (ert-fail (format "forbidden symbol present in canon module: %S" sym))))))

;; ---------------------------------------------------------------------
;; Acceptance §9.10: bough isolation across the substrate
;; ---------------------------------------------------------------------

(defconst satan-memory-canon-test--memory-modules
  '("satan-memory"
    "satan-memory-canon"
    "satan-memory-evidence"
    "satan-memory-grammar"
    "satan-memory-migrate"
    "satan-memory-store")
  "Substrate modules subject to the §9.10 bough-isolation lint.")

(defconst satan-memory-canon-test--forbidden-bough-substrings
  '("bough_production" "bough_agent" "satan-bough-program"
    "satan-bough--invoke")
  "Strings that, if present in any substrate module, signal a direct
bough surface (DB name, binary path, or low-level invoker).  Memory
code must reach bough only through the `bough_read' tool handler.")

(ert-deftest satan-memory/bough-isolation ()
  "§9.10: no satan-memory-* module may reference a bough DB name
or the bough binary directly; all reads go via `bough_read'."
  (dolist (module satan-memory-canon-test--memory-modules)
    (let* ((path (locate-library module))
           (src (and path
                     (if (string-suffix-p ".elc" path)
                         (concat (substring path 0 -1))
                       path))))
      (should src)
      (with-temp-buffer
        (insert-file-contents src)
        (dolist (needle satan-memory-canon-test--forbidden-bough-substrings)
          (goto-char (point-min))
          (when (search-forward needle nil t)
            (ert-fail
             (format "%s.el contains forbidden bough surface %S"
                     module needle))))))))

(provide 'satan-memory-canon-test)
;;; satan-memory-canon-test.el ends here
