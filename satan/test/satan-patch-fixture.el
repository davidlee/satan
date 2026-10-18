;;; satan-patch-fixture.el --- queued patch-job rows for tests -*- lexical-binding: t; -*-

;; `patch_job_create' is fenced (SL-023 PHASE-11), so suites that need a
;; queued job insert it through the store.  Not a suite file (no -test
;; suffix): suites `require' it.

;;; Code:

(require 'satan-patch-store)
(require 'satan-patch-worktree)

(defun satan-patch-fixture-enqueue (repo &rest overrides)
  "Insert a queued job for REPO via the store; return `(ok :job_id ID :state S)'.
OVERRIDES (:directive :mode :base_ref :allowed_paths :adapter) are merged
onto defaults.  Mirrors the row the fenced handler used to create."
  (let* ((args (append overrides
                       (list :directive "fix the thing"
                             :mode "self-edit-mech"
                             :base_ref "HEAD"
                             :allowed_paths '("satan/" "test/")
                             :adapter "pi")))
         (mode (plist-get args :mode))
         (job-id (satan-patch-store-job-id-new
                  (format-time-string "%Y-%m-%dT%H:%M:%S%z"))))
    (pcase (satan-patch-store-insert
            :job-id job-id :mode mode
            :directive (plist-get args :directive)
            :repo repo
            :base_ref (plist-get args :base_ref)
            :branch (satan-patch-worktree-branch-name mode "fixture")
            :worktree_path (satan-patch-worktree-path-for job-id)
            :adapter (plist-get args :adapter)
            :allowed_paths (plist-get args :allowed_paths))
      (`(ok . ,_)
       (satan-patch-store-event
        job-id "transition" (list :from nil :to "queued" :reason "created"))
       (cons 'ok (list :job_id job-id :state "queued")))
      (err err))))

(provide 'satan-patch-fixture)
;;; satan-patch-fixture.el ends here
