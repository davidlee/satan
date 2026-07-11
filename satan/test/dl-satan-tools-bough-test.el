;;; dl-satan-tools-bough-test.el --- bough_read tool tests -*- lexical-binding: t; -*-

;; Run from CLI:
;;   emacs --batch \
;;     -L ~/.emacs.d/core -L ~/.emacs.d/satan -L ~/.emacs.d/satan/test \
;;     -l dl-satan-tools-bough-test.el -f ert-run-tests-batch-and-exit
;;
;; Integration tests skip when `bough' is not on PATH.

(require 'ert)
(require 'cl-lib)
(require 'dl-satan-db)
(require 'dl-satan-tools)
(require 'dl-satan-tools-bough)

;; ---------- registration ----------

(ert-deftest dl-satan-bough/registers-bough-read ()
  (should (dl-satan-tool-lookup "bough_read"))
  (let ((spec (dl-satan-tool-lookup "bough_read")))
    (should (eq 'read (plist-get spec :risk)))
    (should (eq 'dl-satan-tool/bough-read (plist-get spec :handler)))))

;; ---------- schema validation ----------

(ert-deftest dl-satan-bough/schema-rejects-unknown-scope ()
  (let* ((spec (dl-satan-tool-lookup "bough_read"))
         (err (dl-satan-tool-validate-args
               spec (list :scope "bogus"))))
    (should err)
    (should (string-match-p "must be one of" err))))

(ert-deftest dl-satan-bough/schema-requires-scope ()
  (let* ((spec (dl-satan-tool-lookup "bough_read"))
         (err (dl-satan-tool-validate-args spec nil)))
    (should err)
    (should (string-match-p "scope" err))))

(ert-deftest dl-satan-bough/schema-rejects-bad-nanoid ()
  (let* ((spec (dl-satan-tool-lookup "bough_read"))
         (err (dl-satan-tool-validate-args
               spec (list :scope "node" :nanoid "has space"))))
    (should err)))

(ert-deftest dl-satan-bough/schema-rejects-bad-date ()
  (let* ((spec (dl-satan-tool-lookup "bough_read"))
         (err (dl-satan-tool-validate-args
               spec (list :scope "day" :date "2026/05/19"))))
    (should err)))

;; ---------- per-scope arg validation ----------

(ert-deftest dl-satan-bough/scope-args-node-requires-nanoid ()
  (should (dl-satan-bough--validate-scope-args "node" nil))
  (should-not (dl-satan-bough--validate-scope-args
               "node" (list :nanoid "0uGrns4"))))

(ert-deftest dl-satan-bough/scope-args-project-subtree-requires-nanoid ()
  (should (dl-satan-bough--validate-scope-args "project_subtree" nil))
  (should-not (dl-satan-bough--validate-scope-args
               "project_subtree" (list :nanoid "0uGrns4"))))

(ert-deftest dl-satan-bough/scope-args-recent-changes-requires-since ()
  (should (dl-satan-bough--validate-scope-args "recent_changes" nil))
  (should-not (dl-satan-bough--validate-scope-args
               "recent_changes" (list :since "2026-05-19T00:00:00Z"))))

(ert-deftest dl-satan-bough/scope-args-active-day-week-need-nothing ()
  (should-not (dl-satan-bough--validate-scope-args "active" nil))
  (should-not (dl-satan-bough--validate-scope-args "day" nil))
  (should-not (dl-satan-bough--validate-scope-args "week" nil)))

;; ---------- recent_changes scope (mocked invoke) ----------

(ert-deftest dl-satan-bough/recent-changes-composes-transitions-and-created ()
  "After DR-116, `recent_changes' shells out to BOTH
`node status-transitions --since' and `node created --since', and
returns each as its own array under `:transitions' / `:created'."
  (let* ((calls nil)
         (since "2026-05-19T00:00:00Z")
         (transitions-payload
          '((:seq 7 :nanoid "abc1234" :from_status "todo"
                  :to_status "doing" :at "2026-05-20T09:00:00Z"
                  :actor nil)))
         (created-payload
          '((:nanoid "def5678" :kind "task" :title "x"
                     :status "todo" :parent_nanoid "PARENT0"
                     :at "2026-05-20T08:00:00Z"
                     :deleted :json-false :archived :json-false))))
    (cl-letf (((symbol-function 'dl-satan-bough--invoke)
               (lambda (_ws &rest args)
                 (push args calls)
                 (cond
                  ((member "status-transitions" args)
                   (cons 'ok transitions-payload))
                  ((member "created" args)
                   (cons 'ok created-payload))
                  (t (cons 'error "unexpected invocation"))))))
      (let* ((res (dl-satan-tool/bough-read
                   (list :scope "recent_changes" :since since)
                   nil))
             (payload (cdr res)))
        (should (eq 'ok (car res)))
        (should (equal "recent_changes" (plist-get payload :scope)))
        (should (equal since (plist-get payload :since)))
        (should (equal transitions-payload (plist-get payload :transitions)))
        (should (equal created-payload (plist-get payload :created)))
        ;; Both CLI invocations actually fired with --since.
        (should (cl-some (lambda (a)
                           (and (member "status-transitions" a)
                                (member since a)))
                         calls))
        (should (cl-some (lambda (a)
                           (and (member "created" a)
                                (member since a)))
                         calls))))))

(ert-deftest dl-satan-bough/recent-changes-propagates-transition-error ()
  (cl-letf (((symbol-function 'dl-satan-bough--invoke)
             (lambda (_ws &rest args)
               (if (member "status-transitions" args)
                   (cons 'error "bough exit 1: boom")
                 (cons 'ok nil)))))
    (let ((res (dl-satan-tool/bough-read
                (list :scope "recent_changes"
                      :since "2026-05-19T00:00:00Z")
                nil)))
      (should (eq 'error (car res)))
      (should (string-match-p "boom" (cdr res))))))

;; ---------- week-bounds (pure) ----------

(ert-deftest dl-satan-bough/week-bounds-monday ()
  (should (equal "2026-05-18"
                 (dl-satan-bough--monday-of "2026-05-18"))))

(ert-deftest dl-satan-bough/week-bounds-midweek ()
  (should (equal '("2026-05-18" . "2026-05-24")
                 (dl-satan-bough--week-bounds "2026-05-20"))))

(ert-deftest dl-satan-bough/week-bounds-sunday ()
  ;; Sunday belongs to the prior Monday's week (ISO).
  (should (equal '("2026-05-18" . "2026-05-24")
                 (dl-satan-bough--week-bounds "2026-05-24"))))

;; ---------- prune-depth (pure) ----------

(defun dl-satan-bough-test--tree (n)
  "Build a left-spine tree of N children (each with one child of its own)."
  (let ((leaf (list :nanoid "L" :title "leaf")))
    (cl-loop for i from n downto 1
             for next = leaf then prev
             for prev = (list :nanoid (format "N%d" i)
                              :title (format "n%d" i)
                              :children (list next))
             finally return prev)))

(ert-deftest dl-satan-bough/prune-depth-keeps-root-when-zero ()
  (let* ((tree (dl-satan-bough-test--tree 3))
         (out (dl-satan-bough--prune-depth tree 0 0)))
    (should-not (plist-get out :children))
    (should (= 1 (plist-get out :children_truncated_count)))))

(ert-deftest dl-satan-bough/prune-depth-keeps-within-limit ()
  (let* ((tree (dl-satan-bough-test--tree 4))
         (out  (dl-satan-bough--prune-depth tree 0 2))
         (child (car (plist-get out :children)))
         (gchild (car (plist-get child :children))))
    (should (equal "N1" (plist-get out :nanoid)))
    (should (equal "N2" (plist-get child :nanoid)))
    (should (equal "N3" (plist-get gchild :nanoid)))
    ;; depth 3 truncated
    (should-not (plist-get gchild :children))
    (should (= 1 (plist-get gchild :children_truncated_count)))))

(ert-deftest dl-satan-bough/prune-depth-passes-through-non-plist ()
  (should (equal '(1 2 3) (dl-satan-bough--prune-depth '(1 2 3) 0 5)))
  (should (equal "x"      (dl-satan-bough--prune-depth "x" 0 5))))

;; ---------- handler rejects unknown scope ----------

(ert-deftest dl-satan-bough/handler-rejects-unknown-scope ()
  (let ((res (dl-satan-tool/bough-read (list :scope "nope") nil)))
    ;; Per-scope validator returns nil for unknown scope; the dispatch
    ;; pcase then falls through to the catch-all error.
    (should (eq 'error (car res)))))

;; ---------- integration (self-provisioning, test-host only) ----------
;;
;; bough is an external binary that connects via DATABASE_URL/PG env and
;; does NOT route through dl-satan-db.el (DEC-007).  It defaults to the
;; `bough_production' DB on whatever host the PG env points at, so a bare
;; run under `just check' would hit the production socket.  These tests
;; therefore run ONLY when `dl-satan-db-host-override' names a test host
;; (never prod), and self-provision their own `bough_test' DB:
;;   1. CREATE DATABASE bough_test (idempotent, via the psql chokepoint)
;;   2. bough init   (migrations + default workspace, idempotent)
;; Every bough invocation in these tests is pinned to that DB by binding
;; DATABASE_URL.  Replaces the old `/workspace' jail proxy.

(defconst dl-satan-bough-test--db "bough_test")

(defun dl-satan-bough-test--db-url ()
  "Full DATABASE_URL for the bough test DB on the resolved test host.
Returns nil when the override carrier is unset or names the production
socket — so bough is never created on or pointed at production."
  (let ((host dl-satan-db-host-override))
    (when (and host (not (equal host "/run/postgresql")))
      (format "postgres://%s:%s@%s:%s/%s"
              (or (getenv "PGUSER") "postgres")
              (or (getenv "PGPASSWORD") "postgres")
              host
              (or (getenv "PGPORT") "5432")
              dl-satan-bough-test--db))))

(defvar dl-satan-bough-test--ready 'unset
  "Memoized provisioning result: t/nil once computed, `unset' before.")

(defun dl-satan-bough-test--ensure ()
  "Idempotently provision + migrate the bough test DB; memoized.
Non-nil when the integration tests may run: bough executable, a test
host, and `bough init' succeeds.  Never touches the production DB."
  (when (eq dl-satan-bough-test--ready 'unset)
    (setq dl-satan-bough-test--ready
          (let ((url (dl-satan-bough-test--db-url)))
            (and url
                 (file-executable-p dl-satan-bough-program)
                 (progn
                   ;; CREATE DATABASE on the maintenance DB; ignore "already exists".
                   (dl-satan-db-psql
                    "postgres" dl-satan-db-host-override dl-satan-db-default-program
                    (list "-c" (format "CREATE DATABASE %s"
                                        dl-satan-bough-test--db)))
                   (let ((process-environment
                          (cons (concat "DATABASE_URL=" url) process-environment)))
                     (eq 0 (call-process dl-satan-bough-program nil nil nil
                                         "init" "--database-url" url))))))))
  (and dl-satan-bough-test--ready t))

(defmacro dl-satan-bough-test--with-db (&rest body)
  "Skip unless the bough test DB is provisioned, then run BODY with every
bough invocation pinned to it via DATABASE_URL."
  (declare (indent 0))
  `(progn
     (skip-unless (dl-satan-bough-test--ensure))
     (let ((process-environment
            (cons (concat "DATABASE_URL=" (dl-satan-bough-test--db-url))
                  process-environment)))
       ,@body)))

(ert-deftest dl-satan-bough/active-scope-shape ()
  (dl-satan-bough-test--with-db
    (let ((res (dl-satan-tool/bough-read (list :scope "active") nil)))
      (should (eq 'ok (car res)))
      (let ((payload (cdr res)))
        (should (equal "active" (plist-get payload :scope)))
        (should (listp (plist-get payload :nodes)))))))

(ert-deftest dl-satan-bough/day-not-found-becomes-ok-nil ()
  (dl-satan-bough-test--with-db
    ;; A date far in the past with no day entry.
    (let* ((res (dl-satan-tool/bough-read
                 (list :scope "day" :date "1999-01-01") nil))
           (payload (cdr res)))
      (should (eq 'ok (car res)))
      (should (equal "1999-01-01" (plist-get payload :date)))
      (should (null (plist-get payload :day))))))

(ert-deftest dl-satan-bough/week-scope-bounds ()
  (dl-satan-bough-test--with-db
    (let* ((res (dl-satan-tool/bough-read
                 (list :scope "week" :date "2026-05-20") nil))
           (payload (cdr res)))
      (should (eq 'ok (car res)))
      (should (equal "2026-05-18" (plist-get payload :start_date)))
      (should (equal "2026-05-24" (plist-get payload :end_date)))
      (should (listp (plist-get payload :days))))))

(provide 'dl-satan-tools-bough-test)
;;; dl-satan-tools-bough-test.el ends here
