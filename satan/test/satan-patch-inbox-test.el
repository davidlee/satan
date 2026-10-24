;;; satan-patch-inbox-test.el --- the patch runner's watch, into the inbox -*- lexical-binding: t; -*-

;; VT-2 (SL-023 PHASE-13): the inbox follows the runner's `watch'.
;; Against the fake runner in satan-patch-fixture.el and a temp inbox
;; file; never the live socket or the real inbox.

(require 'ert)
(require 'cl-lib)
(require 'satan-patch-inbox)
(require 'satan-patch-fixture)
(require 'satan-tools-inbox)

(defun satan-patch-inbox-test--job (id state &rest fields)
  "A wire job summary for ID in STATE, with extra FIELDS."
  (append (list :jobId id :state state :submissionId (concat "sub-" id)
                :mode "fix" :repo "goad-walk" :baseRef "main"
                :createdAt "2026-10-19T00:00:00Z"
                :updatedAt "2026-10-19T00:05:00Z")
          fields))

(defun satan-patch-inbox-test--frame (job)
  "A watch frame carrying JOB."
  (list :event "job_changed" :job job))

(defconst satan-patch-inbox-test--review
  (satan-patch-inbox-test--job
   "pj-R" "needs_review" :endReason "completed" :class "partial"
   :reviewedOid "669249f7c0ffee"))

(defconst satan-patch-inbox-test--failed
  (satan-patch-inbox-test--job
   "pj-F" "failed" :endReason "collected" :class "violation"
   :failure (list :reason "path_violation" :message "outside allowed paths"
                  :offending '("secret.txt" "etc/passwd"))))

(defun satan-patch-inbox-test--runner (watches &optional acks)
  "A handler: the Nth watch is answered by the Nth of WATCHES, the Nth
ack by the Nth of ACKS (nil: ok).  The last answer of each repeats."
  (lambda (request)
    (pcase (plist-get request :op)
      ("watch" (if (cdr watches) (pop watches) (car watches)))
      ("ack" (if (cdr acks) (pop acks) (car acks)))
      (op (satan-patch-fixture-refusal "invalid_request" op)))))

(defun satan-patch-inbox-test--text ()
  "The temp inbox's contents."
  (if (file-exists-p satan-inbox-file)
      (with-temp-buffer
        (insert-file-contents satan-inbox-file)
        (buffer-string))
    ""))

(defun satan-patch-inbox-test--entries (id)
  "How many inbox entries name job ID."
  (let ((text (satan-patch-inbox-test--text))
        (key (format ":SATAN_PATCH_JOB: %s\n" id))
        (count 0) (start 0))
    (while (setq start (string-search key text start))
      (setq count (1+ count) start (1+ start)))
    count))

(defmacro satan-patch-inbox-test--watching (handler &rest body)
  "Run BODY with the inbox watching a fake runner serving HANDLER."
  (declare (indent 1))
  `(let* ((dir (make-temp-file "satan-patch-inbox-" t))
          (satan-inbox-file (expand-file-name "inbox.org" dir))
          (satan-patch-inbox-enabled t)
          (satan-patch-inbox-backoff-initial 0.05))
     (unwind-protect
         (satan-patch-fixture-with-runner ,handler
           (unwind-protect
               (progn (satan-patch-inbox-start) ,@body)
             (satan-patch-inbox-stop)))
       (delete-directory dir t))))

(ert-deftest satan-patch-inbox/needs_review-replayed-on-reconnect-lands-once ()
  "The runner replays every needs_review job on each watch; the inbox
reconnects after a drop and keeps one entry per job id."
  (let ((review (satan-patch-inbox-test--frame satan-patch-inbox-test--review))
        (marker (satan-patch-inbox-test--frame
                 (satan-patch-inbox-test--job "pj-Z" "needs_review"))))
    (satan-patch-inbox-test--watching
        (satan-patch-inbox-test--runner
         (list (list :frames (list review) :close t)
               (list :frames (list review marker))))
      ;; pj-Z follows pj-R's replay on the second connection.
      (should (satan-patch-fixture-wait-until
               (lambda () (= 1 (satan-patch-inbox-test--entries "pj-Z")))))
      (should (= 2 (length (satan-patch-fixture-requests-for "watch"))))
      (should (= 1 (satan-patch-inbox-test--entries "pj-R")))
      (should-not (satan-patch-fixture-requests-for "ack")))))

(ert-deftest satan-patch-inbox/failed-notice-then-ack ()
  "An unannounced failure becomes an urgent notice, then one ack."
  (satan-patch-inbox-test--watching
      (satan-patch-inbox-test--runner
       (list (list :frames (list (satan-patch-inbox-test--frame
                                  satan-patch-inbox-test--failed)))))
    (should (satan-patch-fixture-wait-until
             (lambda () (satan-patch-fixture-requests-for "ack"))))
    (should (equal (plist-get (car (satan-patch-fixture-requests-for "ack"))
                              :jobIds)
                   '("pj-F")))
    (should (= 1 (satan-patch-inbox-test--entries "pj-F")))
    (let ((text (satan-patch-inbox-test--text)))
      (should (string-match-p "Patch failed: fix goad-walk pj-F" text))
      (should (string-match-p ":urgent:" text)))))

(ert-deftest satan-patch-inbox/ack-refused-notice-not-duplicated-on-resend ()
  "The runner resends an unacked failure; the notice stays single and
the ack is tried again."
  (let ((failed (satan-patch-inbox-test--frame satan-patch-inbox-test--failed)))
    (satan-patch-inbox-test--watching
        (satan-patch-inbox-test--runner
         (list (list :frames (list failed) :close t)
               (list :frames (list failed)))
         (list (satan-patch-fixture-refusal "invalid_transition" "no")
               nil))
      (should (satan-patch-fixture-wait-until
               (lambda () (= 2 (length (satan-patch-fixture-requests-for "ack"))))))
      (should (= 1 (satan-patch-inbox-test--entries "pj-F"))))))

(ert-deftest satan-patch-inbox/ignores-announced-and-unsettled-jobs ()
  "Only needs_review and unannounced failed/cancelled jobs reach the inbox."
  (satan-patch-inbox-test--watching
      (satan-patch-inbox-test--runner
       (list (list :frames
                   (mapcar #'satan-patch-inbox-test--frame
                           (list (satan-patch-inbox-test--job "pj-Q" "running")
                                 (satan-patch-inbox-test--job
                                  "pj-A" "failed"
                                  :announcedAt "2026-10-19T00:06:00Z")
                                 (satan-patch-inbox-test--job "pj-P" "promoted")
                                 satan-patch-inbox-test--review)))))
    (should (satan-patch-fixture-wait-until
             (lambda () (= 1 (satan-patch-inbox-test--entries "pj-R")))))
    (dolist (id '("pj-Q" "pj-A" "pj-P"))
      (should (= 0 (satan-patch-inbox-test--entries id))))
    (should-not (satan-patch-fixture-requests-for "ack"))))

(ert-deftest satan-patch-inbox/renders-review-and-failure ()
  "A review entry shows the reviewed oid, class and partial flag; a
notice shows its failure reason, message and offending paths."
  (satan-patch-inbox-test--watching
      (satan-patch-inbox-test--runner
       (list (list :frames
                   (mapcar #'satan-patch-inbox-test--frame
                           (list satan-patch-inbox-test--review
                                 satan-patch-inbox-test--failed
                                 (satan-patch-inbox-test--job
                                  "pj-C" "cancelled" :endReason "cancelled"))))))
    (should (satan-patch-fixture-wait-until
             (lambda () (= 1 (satan-patch-inbox-test--entries "pj-C")))))
    (let ((text (satan-patch-inbox-test--text)))
      (dolist (expected '("Patch ready: fix goad-walk pj-R"
                          ":REVIEWED_OID: 669249f7c0ffee"
                          ":STATE: needs_review"
                          ":REPO: goad-walk"
                          "Reviewed oid: 669249f7c0ffee"
                          "Class: partial"
                          "Partial: yes"
                          "Base: main"
                          "Failure: path_violation outside allowed paths"
                          "- secret.txt"
                          "- etc/passwd"
                          "Patch cancelled: fix goad-walk pj-C"
                          "End reason: cancelled"))
        (should (string-search expected text))))))

(ert-deftest satan-patch-inbox/review-entry-shows-diffstat-and-commits ()
  "A review entry carries the runner's diffstat and commits, from
`result': a commit's full message when sent (indented), else its subject."
  (let ((runner (satan-patch-inbox-test--runner
                 (list (list :frames
                             (mapcar #'satan-patch-inbox-test--frame
                                     (list satan-patch-inbox-test--review)))))))
    (satan-patch-inbox-test--watching
        (lambda (request)
          (if (equal (plist-get request :op) "result")
              (list :jobId "pj-R" :state "needs_review"
                    :diffstat (list :files 2 :insertions 10 :deletions 3)
                    :commits (vector (list :oid "669249f7c0ffee" :subject "fix the walk")
                                     (list :oid "77aa00bb11cc" :subject "add a test"
                                           :message "add a test\n\n* not a heading\n")))
            (funcall runner request)))
      (should (satan-patch-fixture-wait-until
               (lambda () (= 1 (satan-patch-inbox-test--entries "pj-R")))))
      (should (equal (plist-get (car (satan-patch-fixture-requests-for "result"))
                                :jobId)
                     "pj-R"))
      (let ((text (satan-patch-inbox-test--text)))
        (dolist (expected '("Diffstat: 2 files, +10 -3"
                            "Commits:\n- 669249f fix the walk\n- 77aa00b add a test\n\n  * not a heading\n"))
          (should (string-search expected text)))))))

(ert-deftest satan-patch-inbox/unreachable-runner-is-retried ()
  "A watch that cannot connect keeps retrying until the runner answers."
  (satan-patch-inbox-test--watching
      (satan-patch-inbox-test--runner
       (list (list :frames (list (satan-patch-inbox-test--frame
                                  satan-patch-inbox-test--review)))))
    (should (satan-patch-fixture-wait-until
             (lambda () (= 1 (satan-patch-inbox-test--entries "pj-R")))))
    (satan-patch-inbox-stop)
    (delete-file satan-inbox-file)
    (let ((satan-patch-rpc-socket (expand-file-name "absent.sock" dir)))
      (satan-patch-inbox-start))
    (should (satan-patch-inbox-running-p))
    (should (satan-patch-fixture-wait-until
             (lambda () (= 1 (satan-patch-inbox-test--entries "pj-R")))))))

(ert-deftest satan-patch-inbox/stop-ends-the-watch-for-good ()
  "After stop, a dropped connection is not reopened."
  (satan-patch-inbox-test--watching
      (satan-patch-inbox-test--runner (list (list :frames nil)))
    (should (satan-patch-fixture-wait-until
             (lambda () (satan-patch-fixture-requests-for "watch"))))
    (satan-patch-inbox-stop)
    (should-not (satan-patch-inbox-running-p))
    (satan-patch-fixture-wait-until #'ignore 0.3)
    (should (= 1 (length (satan-patch-fixture-requests-for "watch"))))))

(ert-deftest satan-patch-inbox/start-is-a-no-op-when-disabled ()
  (satan-patch-inbox-test--watching
      (satan-patch-inbox-test--runner (list (list :frames nil)))
    (should (satan-patch-fixture-wait-until
             (lambda () (satan-patch-fixture-requests-for "watch"))))
    (satan-patch-inbox-stop)
    (let ((satan-patch-inbox-enabled nil))
      (should-not (satan-patch-inbox-start)))
    (should-not (satan-patch-inbox-running-p))))

(provide 'satan-patch-inbox-test)
;;; satan-patch-inbox-test.el ends here
