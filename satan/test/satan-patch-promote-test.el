;;; satan-patch-promote-test.el --- promote/reject a reviewed patch job -*- lexical-binding: t; -*-

;; VT-3 (SL-023 PHASE-13, DEC-061): promotion fetches the quarantine ref
;; into refs/satan/incoming/<id>, requires it to equal the job's
;; reviewed_oid, creates refs/heads/satan/patch/<id> only if absent,
;; and reports the disposition.  Real git against temp repos (never the
;; user's config) and the fake runner from satan-patch-fixture.el.

(require 'ert)
(require 'cl-lib)
(require 'org)
(require 'satan-patch-promote)
(require 'satan-tools-inbox)
(require 'satan-patch-fixture)

(defconst satan-patch-promote-test--id "pj-T1")

(defconst satan-patch-promote-test--quarantine-ref
  (concat "refs/capsule/r/heads/job/" satan-patch-promote-test--id))

(defconst satan-patch-promote-test--branch
  (concat "refs/heads/satan/patch/" satan-patch-promote-test--id))

(defconst satan-patch-promote-test--incoming
  (concat "refs/satan/incoming/" satan-patch-promote-test--id))

(defun satan-patch-promote-test--git (dir &rest args)
  "Run git ARGS in DIR; its trimmed stdout.  Signals on a non-zero exit."
  (with-temp-buffer
    (let ((exit (apply #'call-process "git" nil (list t nil) nil "-C" dir args)))
      (unless (eql exit 0)
        (error "git %s in %s: exit %s" (string-join args " ") dir exit))
      (string-trim (buffer-string)))))

(defun satan-patch-promote-test--ref (dir ref)
  "REF's oid in DIR, or nil when it does not exist."
  (with-temp-buffer
    (when (eql 0 (call-process "git" nil (list t nil) nil "-C" dir
                               "rev-parse" "--verify" "--quiet" ref))
      (string-trim (buffer-string)))))

(defun satan-patch-promote-test--commit (dir message)
  "Commit an edit in DIR with MESSAGE; the new oid."
  (with-temp-file (expand-file-name "file.txt" dir) (insert message "\n"))
  (satan-patch-promote-test--git dir "add" "file.txt")
  (satan-patch-promote-test--git dir "commit" "--quiet" "-m" message)
  (satan-patch-promote-test--git dir "rev-parse" "HEAD"))

(defmacro satan-patch-promote-test--with-repos (spec &rest body)
  "Run BODY with temp git repos, isolated from the user's git config.
SPEC is (REPO QUARANTINE BASE JOB): the real repo at commit BASE, and a
bare quarantine holding commit JOB at the job's quarantine ref."
  (declare (indent 1))
  (pcase-let ((`(,repo ,quarantine ,base ,job) spec))
    `(let* ((root (make-temp-file "satan-promote-" t))
            (process-environment
             (append (list "GIT_CONFIG_GLOBAL=/dev/null" "GIT_CONFIG_NOSYSTEM=1"
                           "GIT_AUTHOR_NAME=satan-test" "GIT_AUTHOR_EMAIL=t@example.invalid"
                           "GIT_COMMITTER_NAME=satan-test"
                           "GIT_COMMITTER_EMAIL=t@example.invalid")
                     process-environment))
            (,repo (expand-file-name "repo" root))
            (,quarantine (expand-file-name "quarantine.git" root))
            (worker (expand-file-name "worker" root)))
       (unwind-protect
           (progn
             (make-directory ,repo)
             (satan-patch-promote-test--git ,repo "init" "--quiet" "-b" "main")
             (let* ((,base (satan-patch-promote-test--commit ,repo "base"))
                    (,job (progn
                            (satan-patch-promote-test--git
                             root "init" "--quiet" "--bare" ,quarantine)
                            (satan-patch-promote-test--git
                             root "clone" "--quiet" ,repo worker)
                            (prog1 (satan-patch-promote-test--commit worker "job")
                              (satan-patch-promote-test--git
                               worker "push" "--quiet" ,quarantine
                               (concat "HEAD:" satan-patch-promote-test--quarantine-ref))))))
               ,@body))
         (delete-directory root t)))))

(cl-defun satan-patch-promote-test--runner
    (repo quarantine reviewed
          &key (state "needs_review") (repo-path repo) (base :absent) disposition)
  "A fake runner whose job, in STATE, was reviewed at REVIEWED.
Its result names QUARANTINE, REPO-PATH (default REPO; :absent omits
it) and BASE (default :absent, omitted).  DISPOSITION answers
report-disposition (default ok)."
  (satan-patch-fixture-answering
   `(("result" . (:jobId ,satan-patch-promote-test--id :state ,state
                         :reviewedOid ,reviewed :quarantine ,quarantine
                         ,@(unless (eq base :absent) (list :baseOid base))
                         :quarantineRef ,satan-patch-promote-test--quarantine-ref
                         ,@(unless (eq repo-path :absent) (list :repoPath repo-path))))
     ("report-disposition" . ,(or disposition '(:state "promoted"))))))

(defun satan-patch-promote-test--promote ()
  "Promote the test job; wait for and return the callback's result."
  (let (result)
    (satan-patch-promote-job satan-patch-promote-test--id
                             (lambda (outcome) (setq result outcome)))
    (satan-patch-fixture-wait-until (lambda () result) 10)))

(defun satan-patch-promote-test--show ()
  "Show the test job; wait for and return the callback's result."
  (let (result)
    (satan-patch-show-job satan-patch-promote-test--id
                          (lambda (outcome) (setq result outcome)))
    (satan-patch-fixture-wait-until (lambda () result) 10)))

(defun satan-patch-promote-test--dispositions ()
  "The report-disposition requests the fake runner received."
  (satan-patch-fixture-requests-for "report-disposition"))

(ert-deftest satan-patch-promote/creates-satan/patch/-branch-at-reviewed_oid ()
  "Happy path, real git: the branch lands at reviewed_oid, the incoming
ref is gone, and the disposition names the branch."
  (satan-patch-promote-test--with-repos (repo quarantine _base job)
    (satan-patch-fixture-with-runner
        (satan-patch-promote-test--runner repo quarantine job)
      (should (equal (satan-patch-promote-test--promote) '(ok . "promoted")))
      (should (equal (satan-patch-promote-test--ref
                      repo satan-patch-promote-test--branch)
                     job))
      (should-not (satan-patch-promote-test--ref
                   repo satan-patch-promote-test--incoming))
      (let ((request (car (satan-patch-promote-test--dispositions))))
        (should (equal (plist-get request :jobId) satan-patch-promote-test--id))
        (should (equal (plist-get request :disposition) "promoted"))
        (should (equal (plist-get request :branch)
                       (concat "satan/patch/" satan-patch-promote-test--id)))))))

(ert-deftest satan-patch-promote/quarantine-moved-from-reviewed_oid-is-refused ()
  "The quarantine ref no longer holds reviewed_oid: nothing is created
and nothing is reported."
  (satan-patch-promote-test--with-repos (repo quarantine base _job)
    (satan-patch-fixture-with-runner
        (satan-patch-promote-test--runner repo quarantine base)
      (pcase (satan-patch-promote-test--promote)
        (`(error . ,msg) (should (string-match-p "moved" msg)))
        (other (ert-fail (format "expected refusal, got %S" other))))
      (should-not (satan-patch-promote-test--ref
                   repo satan-patch-promote-test--branch))
      (should-not (satan-patch-promote-test--ref
                   repo satan-patch-promote-test--incoming))
      (should-not (satan-patch-promote-test--dispositions)))))

(ert-deftest satan-patch-promote/existing-satan/patch/-branch-is-left-alone ()
  "The branch exists already: it keeps its oid, the incoming ref is
gone, nothing is reported."
  (satan-patch-promote-test--with-repos (repo quarantine base job)
    (satan-patch-promote-test--git
     repo "update-ref" satan-patch-promote-test--branch base)
    (satan-patch-fixture-with-runner
        (satan-patch-promote-test--runner repo quarantine job)
      (pcase (satan-patch-promote-test--promote)
        (`(error . ,msg) (should (string-match-p "exists" msg)))
        (other (ert-fail (format "expected refusal, got %S" other))))
      (should (equal (satan-patch-promote-test--ref
                      repo satan-patch-promote-test--branch)
                     base))
      (should-not (satan-patch-promote-test--ref
                   repo satan-patch-promote-test--incoming))
      (should-not (satan-patch-promote-test--dispositions)))))

(ert-deftest satan-patch-promote/failed-fetch-leaves-no-incoming-ref ()
  "The quarantine ref is missing: the fetch fails and is reported."
  (satan-patch-promote-test--with-repos (repo quarantine _base job)
    (satan-patch-promote-test--git
     quarantine "update-ref" "-d" satan-patch-promote-test--quarantine-ref)
    (satan-patch-fixture-with-runner
        (satan-patch-promote-test--runner repo quarantine job)
      (pcase (satan-patch-promote-test--promote)
        (`(error . ,msg) (should (string-match-p "fetch" msg)))
        (other (ert-fail (format "expected refusal, got %S" other))))
      (should-not (satan-patch-promote-test--ref
                   repo satan-patch-promote-test--incoming))
      (should-not (satan-patch-promote-test--dispositions)))))

(ert-deftest satan-patch-promote/receipt-mismatch-keeps-the-branch ()
  "The runner refuses the receipt: the error reaches the user and the
branch stays for them to inspect."
  (satan-patch-promote-test--with-repos (repo quarantine _base job)
    (satan-patch-fixture-with-runner
        (satan-patch-promote-test--runner
         repo quarantine job
         :disposition (satan-patch-fixture-refusal "receipt_mismatch" "no"))
      (pcase (satan-patch-promote-test--promote)
        (`(error . ,msg) (should (string-match-p "receipt_mismatch" msg)))
        (other (ert-fail (format "expected refusal, got %S" other))))
      (should (equal (satan-patch-promote-test--ref
                      repo satan-patch-promote-test--branch)
                     job)))))

(ert-deftest satan-patch-promote/refuses-before-git-unless-reviewable ()
  "A job not in needs_review, or a result without the real repo path,
is refused before any git runs."
  (satan-patch-promote-test--with-repos (repo quarantine _base job)
    (dolist (case (list (list :state "rejected") (list :repo-path :absent)
                        (list :repo-path :null)))
      (satan-patch-fixture-with-runner
          (apply #'satan-patch-promote-test--runner repo quarantine job case)
        (should (eq 'error (car (satan-patch-promote-test--promote))))
        (should-not (satan-patch-promote-test--ref
                     repo satan-patch-promote-test--incoming))
        (should (equal (mapcar (lambda (r) (plist-get r :op))
                               (satan-patch-fixture-requests))
                       '("result")))))))

(ert-deftest satan-patch-promote/reject-reports-rejected-and-touches-no-refs ()
  (satan-patch-promote-test--with-repos (repo quarantine _base job)
    (satan-patch-fixture-with-runner
        (satan-patch-promote-test--runner
         repo quarantine job :disposition '(:state "rejected"))
      (should (equal (satan-patch-reject-job satan-patch-promote-test--id)
                     '(ok . "rejected")))
      (let ((request (car (satan-patch-promote-test--dispositions))))
        (should (equal (plist-get request :disposition) "rejected"))
        (should-not (plist-member request :branch)))
      (should (equal (satan-patch-promote-test--git
                      repo "for-each-ref" "refs/satan" "refs/heads/satan")
                     "")))))

(ert-deftest satan-patch-show/fetches-the-reviewed-commit-and-leaves-no-refs ()
  "Show brings reviewed_oid's objects into the real repo and answers
the job; no incoming ref, no branch, nothing reported."
  (satan-patch-promote-test--with-repos (repo quarantine base job)
    (satan-patch-fixture-with-runner
        (satan-patch-promote-test--runner repo quarantine job :base base)
      (pcase (satan-patch-promote-test--show)
        (`(ok . ,shown)
         (should (equal (plist-get shown :base_oid) base))
         (should (equal (plist-get shown :reviewed_oid) job)))
        (other (ert-fail (format "expected the job, got %S" other))))
      (should (satan-patch-promote-test--git repo "cat-file" "-e" job))
      (should (equal (satan-patch-promote-test--git
                      repo "for-each-ref" "refs/satan" "refs/heads/satan")
                     ""))
      (should-not (satan-patch-promote-test--dispositions)))))

(ert-deftest satan-patch-show/refuses-a-moved-quarantine-or-no-base ()
  "Show verifies the fetched commit like promotion does, and needs the
base oid to diff against."
  (satan-patch-promote-test--with-repos (repo quarantine base job)
    (dolist (case (list (list base :base base) (list job)))
      (satan-patch-fixture-with-runner
          (apply #'satan-patch-promote-test--runner repo quarantine case)
        (should (eq 'error (car (satan-patch-promote-test--show))))
        (should-not (satan-patch-promote-test--ref
                     repo satan-patch-promote-test--incoming))))))

(defmacro satan-patch-promote-test--in-entry (&rest body)
  "Run BODY at an unread entry for the test job in a visited inbox file,
confirmations answered yes."
  `(let* ((satan-inbox-file (make-temp-file "satan-inbox-" nil ".org"))
          (buffer (progn
                    (with-temp-file satan-inbox-file
                      (insert "* Patch ready: fix goad-walk "
                              satan-patch-promote-test--id
                              "  :unread:satan:\n"
                              ":PROPERTIES:\n:SATAN_PATCH_JOB: "
                              satan-patch-promote-test--id
                              "\n:STATE: needs_review\n:END:\n"
                              "State: needs_review\n"))
                    (find-file-noselect satan-inbox-file))))
     (unwind-protect
         (with-current-buffer buffer
           (goto-char (point-max))
           (cl-letf (((symbol-function 'y-or-n-p) (lambda (_prompt) t)))
             ,@body))
       (with-current-buffer buffer (set-buffer-modified-p nil))
       (kill-buffer buffer)
       (delete-file satan-inbox-file))))

(defun satan-patch-promote-test--settled-p (state)
  "Whether the entry records STATE and the saved inbox counts it read."
  (and (equal (org-entry-get (point-min) "STATE") state)
       (eql (satan-inbox-unread-count) 0)))

(ert-deftest satan-patch-promote/commands-settle-the-entry ()
  "The commands read the job at point, set the entry's STATE, and mark
it read in the saved inbox."
  (satan-patch-promote-test--with-repos (repo quarantine _base job)
    (satan-patch-fixture-with-runner
        (satan-patch-promote-test--runner repo quarantine job)
      (satan-patch-promote-test--in-entry
       (should (eql (satan-inbox-unread-count) 1))
       (call-interactively #'satan-patch-promote)
       (should (satan-patch-fixture-wait-until
                (lambda () (satan-patch-promote-test--settled-p "promoted"))
                10))))
    (satan-patch-fixture-with-runner
        (satan-patch-promote-test--runner
         repo quarantine job :disposition '(:state "rejected"))
      (satan-patch-promote-test--in-entry
       (call-interactively #'satan-patch-reject)
       (should (satan-patch-promote-test--settled-p "rejected"))))))

(ert-deftest satan-patch-show/command-shows-the-diff-and-leaves-the-entry ()
  "Without magit, the command shows base..reviewed in a diff buffer;
the entry stays unread and unsettled."
  (satan-patch-promote-test--with-repos (repo quarantine base job)
    (satan-patch-fixture-with-runner
        (satan-patch-promote-test--runner repo quarantine job :base base)
      (satan-patch-promote-test--in-entry
       (cl-letf (((symbol-function 'satan-patch-promote--magit-p) #'ignore))
         (call-interactively #'satan-patch-show)
         (let ((shown (satan-patch-fixture-wait-until
                       (lambda () (get-buffer (concat "*satan-patch "
                                                      satan-patch-promote-test--id
                                                      "*")))
                       10)))
           (should shown)
           (with-current-buffer shown
             (should (derived-mode-p 'diff-mode))
             (should (string-search "+job" (buffer-string))))
           (kill-buffer shown)))
       (should (equal (org-entry-get (point-min) "STATE") "needs_review"))
       (should (eql (satan-inbox-unread-count) 1))))))

(ert-deftest satan-patch-promote/commands-need-a-job-at-point ()
  (with-temp-buffer
    (org-mode)
    (insert "* not a patch entry\n")
    (should-error (call-interactively #'satan-patch-reject) :type 'user-error)))

(provide 'satan-patch-promote-test)
;;; satan-patch-promote-test.el ends here
