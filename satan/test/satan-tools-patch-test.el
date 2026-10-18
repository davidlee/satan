;;; satan-tools-patch-test.el --- the patch_job_* tools -*- lexical-binding: t; -*-

;; The tools against the fake runner in satan-patch-fixture.el (SL-023
;; VT-1): no database, no live socket.  `satan-intervention-create' is
;; stubbed; its own suite covers it.

(require 'ert)
(require 'cl-lib)
(require 'satan-tools)
(require 'satan-tools-patch)
(require 'satan-patch-fixture)

(defconst satan-tools-patch-test--create-args
  (list :directive "fix the flaky walk" :mode "fix" :repo "goad-walk"
        :allowed_paths '("src/" "test/"))
  "A valid `patch_job_create' call.")

(defconst satan-tools-patch-test--summary
  (list :jobId "pj-1" :state "needs_review" :submissionId "sat-1"
        :mode "fix" :repo "goad-walk" :baseRef "main"
        :createdAt "2026-10-19T00:00:00.000Z" :updatedAt "2026-10-19T00:05:00.000Z"
        :endReason "completed" :class "partial" :reviewedOid "abc123")
  "A wire summary of a job awaiting review, flagged partial.")

(defvar satan-tools-patch-test--interventions nil
  "Keyword plists `satan-intervention-create' was called with, newest first.")

(defun satan-tools-patch-test--intervention-stub (result)
  "A `satan-intervention-create' recording its args and returning RESULT.
RESULT is the id to return, or `:signal' to signal a `user-error'."
  (lambda (&rest args)
    (push args satan-tools-patch-test--interventions)
    (if (stringp result)
        result
      (user-error "intervention projection failed"))))

(defmacro satan-tools-patch-test--with-interventions (result &rest body)
  "Run BODY with `satan-intervention-create' stubbed to RESULT.
RESULT is the id to return, or `:signal' to signal a `user-error'."
  (declare (indent 1))
  `(let ((satan-tools-patch-test--interventions nil))
     (cl-letf (((symbol-function 'satan-intervention-create)
                (satan-tools-patch-test--intervention-stub ,result)))
       ,@body)))

(defun satan-tools-patch-test--create (&rest overrides)
  "Call `patch_job_create' with the valid args, OVERRIDES first."
  (satan-tool/patch-job-create
   (append overrides satan-tools-patch-test--create-args) '(:id "run-1")))

(defun satan-tools-patch-test--submitting (job-id)
  "A fake runner accepting a submit as JOB-ID, queued."
  (satan-patch-fixture-answering
   `(("submit" . (:jobId ,job-id :state "queued")))))

;; ---------------------------------------------------------------------
;; patch_job_create
;; ---------------------------------------------------------------------

(ert-deftest satan-tools-patch/create-returns-intervention_id-and-sends-one-submissionId ()
  (satan-patch-fixture-with-runner (satan-tools-patch-test--submitting "pj-7")
    (satan-tools-patch-test--with-interventions "run-1.iv001"
      (should (equal (satan-tools-patch-test--create)
                     '(ok :job_id "pj-7" :state "queued"
                          :intervention_id "run-1.iv001")))
      (let ((requests (satan-patch-fixture-requests)))
        (should (= 1 (length requests)))
        (let ((submit (car requests)))
          (should (equal (plist-get submit :op) "submit"))
          (should (string-prefix-p "sat-" (plist-get submit :submissionId)))
          (should (equal (plist-get submit :directive) "fix the flaky walk"))
          (should (equal (plist-get submit :mode) "fix"))
          (should (equal (plist-get submit :repo) "goad-walk"))
          (should (equal (plist-get submit :allowedPaths) '("src/" "test/")))
          (should-not (plist-member submit :baseRef))
          (should-not (plist-member submit :tags))))
      (let ((iv (car satan-tools-patch-test--interventions)))
        (should (equal (plist-get iv :kind) "patch_job"))
        (should (equal (plist-get iv :target-surface) "pj-7"))
        (should (equal (plist-get iv :message) "fix the flaky walk"))))))

(ert-deftest satan-tools-patch/create-sends-the-optional-fields-it-is-given ()
  (satan-patch-fixture-with-runner (satan-tools-patch-test--submitting "pj-7")
    (satan-tools-patch-test--with-interventions "iv"
      (satan-tools-patch-test--create
       :base_ref "dev" :tags '("walk") :source '(:slug "flaky")
       :context '(:issue 4))
      (let ((submit (car (satan-patch-fixture-requests))))
        (should (equal (plist-get submit :baseRef) "dev"))
        (should (equal (plist-get submit :tags) '("walk")))
        (should (equal (plist-get submit :source) '(:slug "flaky")))
        (should (equal (plist-get submit :context) '(:issue 4)))))))

(ert-deftest satan-tools-patch/create-returns-intervention_error-when-the-intervention-fails ()
  "The job exists either way: the model must see its id, not a bare error."
  (satan-patch-fixture-with-runner (satan-tools-patch-test--submitting "pj-7")
    (satan-tools-patch-test--with-interventions :signal
      (should (equal (satan-tools-patch-test--create)
                     '(ok :job_id "pj-7" :state "queued"
                          :intervention_error "intervention projection failed"))))))

(ert-deftest satan-tools-patch/create-fails-closed-when-the-runner-is-unreachable ()
  (let ((satan-patch-rpc-socket
         (expand-file-name "absent.sock" (make-temp-file "satan-tools-patch-" t))))
    (satan-tools-patch-test--with-interventions "iv"
      (pcase (satan-tools-patch-test--create)
        (`(error . ,msg) (should (string-prefix-p "patch runner unreachable" msg)))
        (other (ert-fail (format "expected error, got %S" other))))
      (should-not satan-tools-patch-test--interventions))))

(ert-deftest satan-tools-patch/create-reports-a-refusal-with-its-code ()
  (satan-patch-fixture-with-runner
      (lambda (_request)
        (satan-patch-fixture-refusal "invalid_request" "unknown repo \"x\""))
    (satan-tools-patch-test--with-interventions "iv"
      (should (equal (satan-tools-patch-test--create)
                     '(error . "invalid_request: unknown repo \"x\"")))
      (should-not satan-tools-patch-test--interventions))))

(ert-deftest satan-tools-patch/create-never-resends-a-submissionId-after-a-hang ()
  (satan-patch-fixture-with-runner (lambda (_request) :hang)
    (let ((satan-patch-rpc-timeout 0.2))
      (satan-tools-patch-test--with-interventions "iv"
        (pcase (satan-tools-patch-test--create)
          (`(error . ,msg) (should (string-match-p "no response" msg)))
          (other (ert-fail (format "expected error, got %S" other))))
        (should (= 1 (length (satan-patch-fixture-requests))))
        (should-not satan-tools-patch-test--interventions)))))

(ert-deftest satan-tools-patch/create-refuses-empty-allowed_paths-before-the-runner ()
  (satan-patch-fixture-with-runner (satan-tools-patch-test--submitting "pj-7")
    (pcase (satan-tools-patch-test--create :allowed_paths '())
      (`(error . ,msg) (should (string-match-p "allowed_paths" msg)))
      (other (ert-fail (format "expected error, got %S" other))))
    (should-not (satan-patch-fixture-requests))))

(ert-deftest satan-tools-patch/create-schema-offers-the-configured-modes ()
  (let* ((schema (plist-get (satan-tool-lookup "patch_job_create") :args-schema))
         (keys (cl-loop for (key) on schema by #'cddr collect key)))
    (should (equal (plist-get (plist-get schema 'mode) :enum) satan-tools-patch-modes))
    (should (equal keys '(directive mode repo allowed_paths base_ref tags source context)))
    (should (satan-tool-validate-args (satan-tool-lookup "patch_job_create")
                                      (list :directive "x" :mode "self-edit-mech"
                                            :repo "r" :allowed_paths '("a"))))))

;; ---------------------------------------------------------------------
;; patch_job_status / patch_job_result
;; ---------------------------------------------------------------------

(ert-deftest satan-tools-patch/status-projects-the-summary-with-its-partial-flag ()
  (satan-patch-fixture-with-runner
      (satan-patch-fixture-answering
       `(("status" . (:job ,satan-tools-patch-test--summary))))
    (should (equal (satan-tool/patch-job-status '(:job_id "pj-1") nil)
                   '(ok :job_id "pj-1" :state "needs_review" :mode "fix"
                        :repo "goad-walk" :base_ref "main" :class "partial"
                        :end_reason "completed" :reviewed_oid "abc123"
                        :created_at "2026-10-19T00:00:00.000Z"
                        :updated_at "2026-10-19T00:05:00.000Z"
                        :partial t)))
    (should (equal (plist-get (car (satan-patch-fixture-requests)) :jobId) "pj-1"))))

(ert-deftest satan-tools-patch/status-carries-a-failed-jobs-failure ()
  (let ((failure '(:reason "path_violation" :offending ("etc/passwd"))))
    (satan-patch-fixture-with-runner
        (satan-patch-fixture-answering
         `(("status" . (:job (:jobId "pj-2" :state "failed" :class "path_violation"
                              :failure ,failure)))))
      (pcase (satan-tool/patch-job-status '(:job_id "pj-2") nil)
        (`(ok . ,job)
         (should (equal (plist-get job :failure) failure))
         (should (eq (plist-get job :partial) :false)))
        (other (ert-fail (format "status: %S" other)))))))

(ert-deftest satan-tools-patch/result-projects-the-outcome ()
  (let ((commits '((:oid "abc123" :subject "fix the walk")))
        (diffstat '(:files 1 :insertions 2 :deletions 0)))
    (satan-patch-fixture-with-runner
        (satan-patch-fixture-answering
         `(("result" . (:jobId "pj-1" :state "needs_review" :usage (:modelRequests 7)
                        :class "complete" :endReason "completed" :baseOid "b0"
                        :reviewedOid "abc123" :quarantineRef "refs/q/pj-1"
                        :quarantine "/q.git" :commits ,commits :diffstat ,diffstat
                        :repoPath "/home/u/dev/goad-walk"))))
      (should (equal (satan-tool/patch-job-result '(:job_id "pj-1") nil)
                     `(ok :job_id "pj-1" :state "needs_review" :class "complete"
                          :end_reason "completed" :reviewed_oid "abc123"
                          :base_oid "b0" :quarantine "/q.git"
                          :quarantine_ref "refs/q/pj-1" :commits ,commits
                          :diffstat ,diffstat :partial :false
                          :model_requests 7))))))

(ert-deftest satan-tools-patch/unknown-job-reports-the-runners-code ()
  (satan-patch-fixture-with-runner
      (lambda (_request) (satan-patch-fixture-refusal "unknown_job" "no job pj-9"))
    (dolist (tool '(satan-tool/patch-job-status satan-tool/patch-job-result
                    satan-tool/patch-job-cancel))
      (should (equal (funcall tool '(:job_id "pj-9") nil)
                     '(error . "unknown_job: no job pj-9"))))))

;; ---------------------------------------------------------------------
;; patch_job_cancel
;; ---------------------------------------------------------------------

(ert-deftest satan-tools-patch/cancel-sends-its-reason ()
  (satan-patch-fixture-with-runner
      (satan-patch-fixture-answering '(("cancel" . (:state "cancelled"))))
    (should (equal (satan-tool/patch-job-cancel
                    '(:job_id "pj-1" :reason "superseded") nil)
                   '(ok :job_id "pj-1" :state "cancelled")))
    (satan-tool/patch-job-cancel '(:job_id "pj-1") nil)
    (let ((requests (satan-patch-fixture-requests)))
      (should (equal (plist-get (car requests) :reason) "superseded"))
      (should (equal (plist-get (cadr requests) :reason)
                     "cancelled via patch_job_cancel")))))

;; ---------------------------------------------------------------------
;; registry
;; ---------------------------------------------------------------------

(ert-deftest satan-tools-patch/registers-the-four-runner-tools ()
  (dolist (name '("patch_job_create" "patch_job_status"
                  "patch_job_result" "patch_job_cancel"))
    (should (satan-tool-lookup name)))
  (should-not (satan-tool-lookup "patch_job_cleanup")))

(ert-deftest satan-tools-patch/descriptions-resolvable ()
  ;; Model-facing descriptions live in the host-only corpus
  ;; (`satan-corpus-root'; SL-012 D4/POL), not shipped in the package.
  (skip-unless (file-readable-p
                (expand-file-name "patch_job_create.md" satan-tools-descriptions-dir)))
  (dolist (name '("patch_job_create" "patch_job_status"
                  "patch_job_result" "patch_job_cancel"))
    (should (file-readable-p
             (expand-file-name (concat name ".md") satan-tools-descriptions-dir)))))

(provide 'satan-tools-patch-test)
;;; satan-tools-patch-test.el ends here
