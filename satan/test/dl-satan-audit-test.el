;;; dl-satan-audit-test.el --- ert tests for dl-satan-audit -*- lexical-binding: t; -*-

;; Run from CLI:
;;   emacs --batch \
;;     -L ~/.emacs.d/core -L ~/.emacs.d/satan -L ~/.emacs.d/satan/test \
;;     -l dl-satan-audit-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'json)
(require 'dl-satan-audit)
(require 'dl-satan-protocol)             ; fixtures shared with protocol-test

(defun dl-satan-audit-test--write-run (dir final actions status &optional transcript)
  "Open a run under DIR, optionally record TRANSCRIPT entries, close with
FINAL/ACTIONS/STATUS.  TRANSCRIPT is a list of (DIRECTION EVENT PAYLOAD)
triples passed verbatim to `dl-satan-audit-record'."
  (make-directory dir t)
  (let ((audit (dl-satan-audit-open dir
                                    '(:run_id "r" :mode (:name "test"))
                                    '(:bundle t))))
    (dolist (rec (or transcript '()))
      (dl-satan-audit-record audit (nth 0 rec) (nth 1 rec) (nth 2 rec)))
    (dl-satan-audit-close audit final actions status)))

(ert-deftest dl-satan-audit/verifier-ok ()
  (let ((dir (make-temp-file "satan-run-" t)))
    (unwind-protect
        (progn
          (dl-satan-audit-test--write-run
           dir
           '(:summary "s" :actions ())
           '(:applied () :staged () :rejected () :failed ())
           'done
           '((in tool-call (:id "a"))
             (broker tool-result (:id "a" :ok t))))
          (should (eq (dl-satan-audit-verify-run dir) t)))
      (delete-directory dir t))))

;; ---------- pre_spawn (Phase 0.3) ----------

(ert-deftest dl-satan-audit/pre-spawn-key-written-when-present ()
  "`dl-satan-audit-close' writes `:pre_spawn' into actions.json when the
caller supplies it; the four model-action partitions stay untouched."
  (let ((dir (make-temp-file "satan-prespawn-write-" t)))
    (unwind-protect
        (progn
          (dl-satan-audit-test--write-run
           dir
           '(:summary "s" :actions ())
           (list :applied () :staged () :rejected () :failed ()
                 :pre_spawn (list (list :kind "sensor_alert"
                                        :cause "panopticon_current_stale"
                                        :severity "warning"
                                        :message "stale 28m"
                                        :dispatched_at "2026-05-22T11:13Z")))
           'done)
          (let* ((actions-path (expand-file-name "actions.json" dir))
                 (parsed (with-temp-buffer
                           (insert-file-contents actions-path)
                           (goto-char (point-min))
                           (json-parse-buffer :object-type 'plist
                                              :array-type 'list
                                              :null-object :null
                                              :false-object :false))))
            (should (equal (plist-get parsed :applied) '()))
            (should (equal (plist-get parsed :staged) '()))
            (should (equal (plist-get parsed :rejected) '()))
            (should (equal (plist-get parsed :failed) '()))
            (let ((ps (plist-get parsed :pre_spawn)))
              (should (listp ps))
              (should (= 1 (length ps)))
              (should (equal (plist-get (car ps) :kind) "sensor_alert"))
              (should (equal (plist-get (car ps) :cause)
                             "panopticon_current_stale")))))
      (delete-directory dir t))))

(ert-deftest dl-satan-audit/pre-spawn-omitted-when-absent ()
  "Runs without `:pre_spawn' omit the key entirely from actions.json."
  (let ((dir (make-temp-file "satan-prespawn-absent-" t)))
    (unwind-protect
        (progn
          (dl-satan-audit-test--write-run
           dir
           '(:summary "s" :actions ())
           '(:applied () :staged () :rejected () :failed ())
           'done)
          (let* ((actions-path (expand-file-name "actions.json" dir))
                 (parsed (with-temp-buffer
                           (insert-file-contents actions-path)
                           (goto-char (point-min))
                           (json-parse-buffer :object-type 'plist
                                              :array-type 'list
                                              :null-object :null
                                              :false-object :false))))
            (should-not (plist-member parsed :pre_spawn))))
      (delete-directory dir t))))

(ert-deftest dl-satan-audit/verifier-accepts-pre-spawn-run ()
  "A run carrying a single `pre_spawn' sensor_alert and zero model
actions still verifies clean — `pre_spawn' must NOT pollute the
{applied,staged,rejected,failed} partition count invariant against
`final.actions'."
  (let ((dir (make-temp-file "satan-prespawn-verify-" t)))
    (unwind-protect
        (progn
          (dl-satan-audit-test--write-run
           dir
           '(:summary "no model actions, sensor alert pre-spawn"
             :actions ())
           (list :applied () :staged () :rejected () :failed ()
                 :pre_spawn (list (list :kind "sensor_alert"
                                        :cause "panopticon_current_stale"
                                        :severity "warning"
                                        :message "stale 28m"
                                        :remediation "systemctl --user status panopticon-sway"
                                        :suppressed :false
                                        :dispatched_at "2026-05-22T11:13Z")))
           'done)
          (should (eq (dl-satan-audit-verify-run dir) t)))
      (delete-directory dir t))))

(ert-deftest dl-satan-audit/verifier-rejects-malformed-pre-spawn ()
  "An entry missing the `kind' discriminator is malformed structure
(distinct from an unknown discriminant value).  Verifier flags it."
  (let ((dir (make-temp-file "satan-prespawn-bad-" t)))
    (unwind-protect
        (progn
          (dl-satan-audit-test--write-run
           dir
           '(:summary "" :actions ())
           (list :applied () :staged () :rejected () :failed ()
                 :pre_spawn (list (list :cause "no_kind_here")))
           'done)
          (let ((res (dl-satan-audit-verify-run dir)))
            (should (consp res))
            (should (assq 'pre-spawn-shape res))))
      (delete-directory dir t))))

(ert-deftest dl-satan-audit/verifier-accepts-unknown-pre-spawn-kind ()
  "Unknown `kind' discriminants are accepted gracefully (forward-compat);
only malformed STRUCTURE is rejected."
  (let ((dir (make-temp-file "satan-prespawn-unknown-" t)))
    (unwind-protect
        (progn
          (dl-satan-audit-test--write-run
           dir
           '(:summary "" :actions ())
           (list :applied () :staged () :rejected () :failed ()
                 :pre_spawn (list (list :kind "future_thing_v2"
                                        :payload "whatever")))
           'done)
          (should (eq (dl-satan-audit-verify-run dir) t)))
      (delete-directory dir t))))

(ert-deftest dl-satan-audit/validate-actions-pure ()
  "`dl-satan-audit-validate-actions' is a pure (in-memory) validator over
the actions.json shape — usable from fixtures without touching disk."
  (should (null (dl-satan-audit-validate-actions
                 '(:applied () :staged () :rejected () :failed ()))))
  (should (null (dl-satan-audit-validate-actions
                 (list :applied () :staged () :rejected () :failed ()
                       :pre_spawn (list (list :kind "sensor_alert"
                                              :cause "x" :message "y"))))))
  (should (stringp (dl-satan-audit-validate-actions
                    (list :applied () :staged () :rejected () :failed ()
                          :pre_spawn (list (list :cause "no_kind")))))))

;; ---------- actions fixtures (cross-cutter: fixtures shipped with
;; dl-satan-protocol; assertion subject is dl-satan-audit-validate-actions) ----------

(ert-deftest dl-satan-audit/fixtures-actions-valid-pass ()
  "Every actions fixture marked `valid' passes `validate-actions'.
Asserts the suite is non-empty so a fixture-file regression is loud."
  (let ((seen 0))
    (dolist (entry (dl-satan-protocol-fixtures))
      (when (and (string= (plist-get entry :kind) "valid")
                 (string= (plist-get entry :direction) "actions"))
        (cl-incf seen)
        (let* ((msg (plist-get entry :message))
               (err (dl-satan-audit-validate-actions msg))
               (name (plist-get entry :name)))
          (should (null err))
          (ignore name))))
    (should (> seen 0))))

(ert-deftest dl-satan-audit/fixtures-actions-invalid-fail ()
  "Every actions fixture marked `invalid' fails with the fixture's reason."
  (let ((seen 0))
    (dolist (entry (dl-satan-protocol-fixtures))
      (when (and (string= (plist-get entry :kind) "invalid")
                 (string= (plist-get entry :direction) "actions"))
        (cl-incf seen)
        (let* ((msg (plist-get entry :message))
               (expected (plist-get entry :reason))
               (name (plist-get entry :name))
               (err (dl-satan-audit-validate-actions msg)))
          (should (stringp err))
          (should (equal expected err))
          (ignore name))))
    (should (> seen 0))))

(ert-deftest dl-satan-audit/verifier-detects-orphan-call ()
  (let ((dir (make-temp-file "satan-run-" t)))
    (unwind-protect
        (progn
          (dl-satan-audit-test--write-run
           dir
           '(:summary "s" :actions ())
           '(:applied () :staged () :rejected () :failed ())
           'done
           '((in tool-call (:id "a"))))
          (let ((res (dl-satan-audit-verify-run dir)))
            (should (consp res))
            (should (assq 'calls-match-results res))))
      (delete-directory dir t))))

;; ---------- reopen (T1.5b PR 4 — manual-mark append path) ----------

(ert-deftest dl-satan-audit/reopen-appends-without-truncating ()
  "`dl-satan-audit-reopen' returns a handle whose `audit-record' appends
to the existing transcript; prior lines are preserved."
  (let ((dir (make-temp-file "satan-reopen-" t)))
    (unwind-protect
        (progn
          (dl-satan-audit-test--write-run
           dir
           '(:summary "s" :actions ())
           '(:applied () :staged () :rejected () :failed ())
           'done
           '((broker intervention.created (:intervention_id "iv1"))))
          (let* ((tp (expand-file-name "transcript.jsonl" dir))
                 (before (with-temp-buffer (insert-file-contents tp)
                                           (buffer-string)))
                 (handle (dl-satan-audit-reopen dir)))
            (dl-satan-audit-record handle 'broker 'intervention.outcome_classified
                                   '(:intervention_id "iv1"
                                     :classification "harmful"
                                     :source "manual"))
            (let* ((after (with-temp-buffer (insert-file-contents tp)
                                            (buffer-string)))
                   (lines (split-string after "\n" t)))
              (should (string-prefix-p before after))
              (should (= 2 (length lines)))
              (should (string-match-p "intervention.outcome_classified"
                                      (nth 1 lines))))))
      (delete-directory dir t))))

(ert-deftest dl-satan-audit/reopen-rejects-missing-dir ()
  (let ((dir (make-temp-file "satan-reopen-nope-" t)))
    (delete-directory dir t)
    (should-error (dl-satan-audit-reopen dir) :type 'user-error)))

(ert-deftest dl-satan-audit/reopen-rejects-dir-without-transcript ()
  (let ((dir (make-temp-file "satan-reopen-bare-" t)))
    (unwind-protect
        (should-error (dl-satan-audit-reopen dir) :type 'user-error)
      (delete-directory dir t))))

(provide 'dl-satan-audit-test)
;;; dl-satan-audit-test.el ends here
