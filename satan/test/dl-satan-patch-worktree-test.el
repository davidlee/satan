;;; dl-satan-patch-worktree-test.el --- patch-worktree ert -*- lexical-binding: t; -*-

;; Tests for `dl-satan-patch-worktree'.  Pure helpers exercised
;; directly; git tests build a throwaway repo in a temp dir, create
;; a worktree off it, then exercise allowlist verify + cleanup.

(require 'ert)
(require 'cl-lib)
(require 'dl-satan-patch-worktree)

;; ---------------------------------------------------------------------
;; pure helpers
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-patch-worktree/slugify ()
  (should (equal "memory-canon-tests"
                 (dl-satan-patch-worktree--slugify "Memory canon tests!")))
  (should (equal "job"
                 (dl-satan-patch-worktree--slugify "")))
  (should (equal "abc-def"
                 (dl-satan-patch-worktree--slugify "  ---abc def---  "))))

(ert-deftest dl-satan-patch-worktree/branch-name-shape ()
  (let ((b (dl-satan-patch-worktree-branch-name
            "self-edit-mech" "Memory brief" 0)))
    (should (string-match-p
             "\\`satan/self-edit-mech/[0-9]\\{8\\}T[0-9]\\{6\\}-memory-brief\\'"
             b))))

(ert-deftest dl-satan-patch-worktree/path-allowed-prefix ()
  (let ((allowed '("satan/" "test/")))
    (should (dl-satan-patch-worktree-path-allowed-p
             "satan/dl-satan-patch.el" allowed))
    (should (dl-satan-patch-worktree-path-allowed-p
             "test/dl-satan-patch-test.el" allowed))
    (should-not (dl-satan-patch-worktree-path-allowed-p
                 "core/dl-path.el" allowed))))

(ert-deftest dl-satan-patch-worktree/path-allowed-exact ()
  (let ((allowed '("satan/dl-satan.el")))
    (should (dl-satan-patch-worktree-path-allowed-p
             "satan/dl-satan.el" allowed))
    (should-not (dl-satan-patch-worktree-path-allowed-p
                 "satan/dl-satan-broker.el" allowed))))

;; ---------------------------------------------------------------------
;; git fixtures
;; ---------------------------------------------------------------------

(defun dl-satan-patch-worktree-test--mkrepo (dir)
  "Initialise a one-commit git repo at DIR, returning DIR."
  (make-directory dir t)
  (let ((default-directory dir))
    (call-process "git" nil nil nil "init" "-q" "-b" "main")
    (call-process "git" nil nil nil "config" "user.email" "t@t")
    (call-process "git" nil nil nil "config" "user.name" "t")
    (with-temp-file (expand-file-name "README" dir) (insert "seed\n"))
    (call-process "git" nil nil nil "add" "README")
    (call-process "git" nil nil nil "commit" "-q" "-m" "init"))
  dir)

(defmacro dl-satan-patch-worktree-test--with-fixture (var-repo &rest body)
  "Bind VAR-REPO to a fresh throwaway repo, also set the worktree root
to a temp dir; run BODY; clean up."
  (declare (indent 1))
  `(let* ((,var-repo (make-temp-file "satan-patch-repo-" t))
          (wt-root (make-temp-file "satan-patch-wt-" t))
          (dl-satan-patch-worktree-root wt-root))
     (unwind-protect
         (progn
           (dl-satan-patch-worktree-test--mkrepo ,var-repo)
           ,@body)
       (when (file-directory-p ,var-repo) (delete-directory ,var-repo t))
       (when (file-directory-p wt-root) (delete-directory wt-root t)))))

(defun dl-satan-patch-worktree-test--job (repo)
  (let ((wt (dl-satan-patch-worktree-path-for "patch_test_001")))
    (list :id "patch_test_001"
          :repo repo
          :base_ref "main"
          :branch (dl-satan-patch-worktree-branch-name
                   "self-edit-mech" "fixture" 0)
          :worktree_path wt
          :allowed_paths_json '("satan/" "test/")
          :checks_json '())))

;; ---------------------------------------------------------------------
;; create + manifest
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-patch-worktree/create-success ()
  (skip-unless (executable-find "git"))
  (dl-satan-patch-worktree-test--with-fixture repo
    (let ((job (dl-satan-patch-worktree-test--job repo)))
      (pcase (dl-satan-patch-worktree-create job)
        (`(ok . ,info)
         (should (file-directory-p (plist-get info :worktree-path)))
         (should (file-exists-p
                  (expand-file-name ".satan-patch-manifest.json"
                                    (plist-get info :worktree-path))))
         (let ((manifest
                (with-temp-buffer
                  (insert-file-contents
                   (expand-file-name ".satan-patch-manifest.json"
                                     (plist-get info :worktree-path)))
                  (json-parse-buffer :object-type 'plist
                                     :array-type 'list))))
           (should (equal (plist-get manifest :job_id) "patch_test_001"))
           (should (equal (plist-get manifest :allowed_paths)
                          '("satan/" "test/")))))
        (err (ert-fail (format "create: %S" err)))))))

(ert-deftest dl-satan-patch-worktree/create-refuses-existing-path ()
  (skip-unless (executable-find "git"))
  (dl-satan-patch-worktree-test--with-fixture repo
    (let ((job (dl-satan-patch-worktree-test--job repo)))
      (dl-satan-patch-worktree-create job)
      (pcase (dl-satan-patch-worktree-create job)
        (`(error . ,_) t)
        (other (ert-fail (format "expected error, got %S" other)))))))

(ert-deftest dl-satan-patch-worktree/create-rejects-missing-repo ()
  (let ((job (list :id "x"
                   :repo "/nonexistent/path"
                   :base_ref "main" :branch "satan/x/0-y"
                   :worktree_path "/tmp/wt-x"
                   :allowed_paths_json '("/")
                   :checks_json '())))
    (pcase (dl-satan-patch-worktree-create job)
      (`(error . ,_) t)
      (other (ert-fail (format "expected error, got %S" other))))))

;; ---------------------------------------------------------------------
;; changed-files + allowlist verify
;; ---------------------------------------------------------------------

(defun dl-satan-patch-worktree-test--edit (wt path contents)
  (let* ((full (expand-file-name path wt))
         (dir (file-name-directory full)))
    (when dir (make-directory dir t))
    (with-temp-file full (insert contents))
    (let ((default-directory wt))
      (call-process "git" nil nil nil "add" path)
      (call-process "git" nil nil nil "commit" "-q" "-m"
                    (format "edit %s" path)))))

(ert-deftest dl-satan-patch-worktree/verify-allowlist-accepts ()
  (skip-unless (executable-find "git"))
  (dl-satan-patch-worktree-test--with-fixture repo
    (let* ((job (dl-satan-patch-worktree-test--job repo))
           (wt (plist-get job :worktree_path)))
      (dl-satan-patch-worktree-create job)
      (dl-satan-patch-worktree-test--edit wt "satan/foo.el" ";; ok\n")
      (dl-satan-patch-worktree-test--edit wt "test/foo-test.el" ";; ok\n")
      (pcase (dl-satan-patch-worktree-changed-files job)
        (`(ok . ,changed)
         (should (member "satan/foo.el" changed))
         (should (member "test/foo-test.el" changed))
         (pcase (dl-satan-patch-worktree-verify-allowlist job changed)
           (`(ok . ,c) (should (= 2 (length c))))
           (err (ert-fail (format "verify: %S" err)))))
        (err (ert-fail (format "changed: %S" err)))))))

(ert-deftest dl-satan-patch-worktree/verify-allowlist-rejects ()
  (skip-unless (executable-find "git"))
  (dl-satan-patch-worktree-test--with-fixture repo
    (let* ((job (dl-satan-patch-worktree-test--job repo))
           (wt (plist-get job :worktree_path)))
      (dl-satan-patch-worktree-create job)
      (dl-satan-patch-worktree-test--edit wt "satan/foo.el" ";; ok\n")
      (dl-satan-patch-worktree-test--edit wt "core/bad.el" ";; nope\n")
      (pcase (dl-satan-patch-worktree-changed-files job)
        (`(ok . ,changed)
         (pcase (dl-satan-patch-worktree-verify-allowlist job changed)
           (`(error . ,bad)
            (should (member "core/bad.el" bad))
            (should-not (member "satan/foo.el" bad)))
           (other (ert-fail (format "expected error, got %S" other)))))
        (err (ert-fail (format "changed: %S" err)))))))

;; ---------------------------------------------------------------------
;; cleanup
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-patch-worktree/cleanup-removes-worktree ()
  (skip-unless (executable-find "git"))
  (dl-satan-patch-worktree-test--with-fixture repo
    (let* ((job (dl-satan-patch-worktree-test--job repo))
           (wt (plist-get job :worktree_path)))
      (dl-satan-patch-worktree-create job)
      (should (file-directory-p wt))
      (pcase (dl-satan-patch-worktree-cleanup job)
        (`(ok . ,info)
         (should (plist-get info :removed-worktree))
         (should (not (plist-get info :deleted-branch)))
         (should-not (file-directory-p wt)))
        (err (ert-fail (format "cleanup: %S" err)))))))

(ert-deftest dl-satan-patch-worktree/cleanup-idempotent ()
  (skip-unless (executable-find "git"))
  (dl-satan-patch-worktree-test--with-fixture repo
    (let ((job (dl-satan-patch-worktree-test--job repo)))
      (dl-satan-patch-worktree-create job)
      (dl-satan-patch-worktree-cleanup job)
      (pcase (dl-satan-patch-worktree-cleanup job)
        (`(ok . ,info)
         (should-not (plist-get info :removed-worktree)))
        (err (ert-fail (format "2nd cleanup: %S" err)))))))

(ert-deftest dl-satan-patch-worktree/cleanup-deletes-branch ()
  (skip-unless (executable-find "git"))
  (dl-satan-patch-worktree-test--with-fixture repo
    (let* ((job (dl-satan-patch-worktree-test--job repo))
           (branch (plist-get job :branch)))
      (dl-satan-patch-worktree-create job)
      (pcase (dl-satan-patch-worktree-cleanup job :delete-branch t)
        (`(ok . ,info)
         (should (plist-get info :deleted-branch))
         (pcase (dl-satan-patch-worktree--git
                 repo (list "rev-parse" "--verify" branch))
           (`(ok . ,_) (ert-fail "branch should be gone"))
           (`(error . ,_) t)))
        (err (ert-fail (format "cleanup-delete-branch: %S" err)))))))

;; ---------------------------------------------------------------------
;; confinement guard (VT-1)
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-patch-worktree/assert-owned-accepts-owned-path ()
  "Guard accepts a path under the patch-worktree root."
  (let* ((root (make-temp-file "satan-patch-guard-" t))
         (dl-satan-patch-worktree-root root))
    (unwind-protect
        (let ((owned (expand-file-name "job1" root)))
          (should (progn (dl-satan-patch-worktree--assert-owned owned) t)))
      (delete-directory root t))))

(ert-deftest dl-satan-patch-worktree/assert-owned-rejects-outside-path ()
  "Guard signals when the target escapes the root (a user tree)."
  (let* ((root (make-temp-file "satan-patch-guard-" t))
         (dl-satan-patch-worktree-root root))
    (unwind-protect
        (should-error
         (dl-satan-patch-worktree--assert-owned
          (make-temp-name "/tmp/definitely-outside-")))
      (delete-directory root t))))

(ert-deftest dl-satan-patch-worktree/assert-owned-rejects-symlink-escape ()
  "Guard signals when an in-root symlink resolves outside the root.
`file-truename' follows the link, so a symlink planted under the root
that points at a user tree is still rejected."
  (let* ((root (make-temp-file "satan-patch-guard-" t))
         (outside (make-temp-file "satan-patch-outside-" t))
         (dl-satan-patch-worktree-root root))
    (unwind-protect
        (let ((link (expand-file-name "escape" root)))
          (make-symbolic-link outside link)
          (should-error (dl-satan-patch-worktree--assert-owned link)))
      (delete-directory root t)
      (delete-directory outside t))))

(provide 'dl-satan-patch-worktree-test)
;;; dl-satan-patch-worktree-test.el ends here
