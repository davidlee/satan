;;; dl-satan-patch-listener-test.el --- ert for LISTEN subprocess -*- lexical-binding: t; -*-

;; Tests for the postgres LISTEN subprocess that wakes
;; `dl-satan-patch-inbox-handoff' on daemon-emitted NOTIFY events.

(require 'ert)
(require 'cl-lib)
(require 'dl-satan-patch-listener)
(require 'dl-satan-patch-store)
(require 'dl-satan-patch-inbox)

;; ---------------------------------------------------------------------
;; helpers
;; ---------------------------------------------------------------------

(defun dl-satan-patch-listener-test--notif-line (channel payload)
  "Build a `satan-attrd notify-stream' JSON line for CHANNEL + PAYLOAD."
  (format "{\"channel\":\"%s\",\"payload\":\"%s\"}\n" channel payload))

(defmacro dl-satan-patch-listener-test--with-mocked-deps
    (received-var &rest body)
  "Bind RECEIVED-VAR to a list capturing handoff calls during BODY.
`dl-satan-patch-store-get' returns a synthetic row; the inbox
handoff pushes the row onto RECEIVED-VAR."
  (declare (indent 1))
  `(let ((,received-var '()))
     (cl-letf (((symbol-function 'dl-satan-patch-store-get)
                (lambda (id &rest _)
                  (cons 'ok (list :id id :state "needs_review"
                                  :mode "self-edit-mech"
                                  :repo "/tmp/repo"))))
               ((symbol-function 'dl-satan-patch-inbox-handoff)
                (lambda (row) (push row ,received-var))))
       ,@body)))

;; ---------------------------------------------------------------------
;; filter — happy path
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-patch-listener/filter-emits-handoff-on-notification ()
  (dl-satan-patch-listener-test--with-mocked-deps received
    (let ((filter (dl-satan-patch-listener--make-filter)))
      (funcall filter nil
               (dl-satan-patch-listener-test--notif-line
                "patch_jobs_done" "patch_abc"))
      (should (= 1 (length received)))
      (should (equal "patch_abc" (plist-get (car received) :id))))))

(ert-deftest dl-satan-patch-listener/filter-fires-on-failed-channel ()
  (dl-satan-patch-listener-test--with-mocked-deps received
    (let ((filter (dl-satan-patch-listener--make-filter)))
      (funcall filter nil
               (dl-satan-patch-listener-test--notif-line
                "patch_jobs_failed" "patch_xyz"))
      (should (= 1 (length received)))
      (should (equal "patch_xyz" (plist-get (car received) :id))))))

;; ---------------------------------------------------------------------
;; filter — buffering partial lines
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-patch-listener/filter-buffers-partial-lines ()
  (dl-satan-patch-listener-test--with-mocked-deps received
    (let* ((filter (dl-satan-patch-listener--make-filter))
           (full (dl-satan-patch-listener-test--notif-line
                  "patch_jobs_done" "patch_split"))
           (mid (/ (length full) 2)))
      (funcall filter nil (substring full 0 mid))
      (should (= 0 (length received)))
      (funcall filter nil (substring full mid))
      (should (= 1 (length received)))
      (should (equal "patch_split" (plist-get (car received) :id))))))

(ert-deftest dl-satan-patch-listener/filter-handles-multiple-notifications-in-chunk ()
  (dl-satan-patch-listener-test--with-mocked-deps received
    (let ((filter (dl-satan-patch-listener--make-filter)))
      (funcall filter nil
               (concat
                (dl-satan-patch-listener-test--notif-line
                 "patch_jobs_done" "patch_a")
                (dl-satan-patch-listener-test--notif-line
                 "patch_jobs_failed" "patch_b")))
      (should (= 2 (length received)))
      (should (equal '("patch_b" "patch_a")
                     (mapcar (lambda (r) (plist-get r :id)) received))))))

;; ---------------------------------------------------------------------
;; filter — defensive: ignore unknown channels + noise
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-patch-listener/filter-ignores-unknown-channel ()
  (dl-satan-patch-listener-test--with-mocked-deps received
    (let ((filter (dl-satan-patch-listener--make-filter)))
      (funcall filter nil
               (dl-satan-patch-listener-test--notif-line
                "patch_jobs_other" "patch_a"))
      (should (= 0 (length received))))))

(ert-deftest dl-satan-patch-listener/filter-ignores-non-notification-output ()
  (dl-satan-patch-listener-test--with-mocked-deps received
    (let ((filter (dl-satan-patch-listener--make-filter)))
      (funcall filter nil "psql (16.3)\nType \"help\" for help.\n\n")
      (should (= 0 (length received))))))

(ert-deftest dl-satan-patch-listener/filter-skips-missing-row ()
  "store-get returning (ok . nil) must not call handoff."
  (let ((received '()))
    (cl-letf (((symbol-function 'dl-satan-patch-store-get)
               (lambda (_ &rest _r) (cons 'ok nil)))
              ((symbol-function 'dl-satan-patch-inbox-handoff)
               (lambda (row) (push row received))))
      (let ((filter (dl-satan-patch-listener--make-filter)))
        (funcall filter nil
                 (dl-satan-patch-listener-test--notif-line
                  "patch_jobs_done" "patch_missing"))
        (should (= 0 (length received)))))))

;; ---------------------------------------------------------------------
;; start/stop API
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-patch-listener/start-noop-when-disabled ()
  (let ((dl-satan-patch-listener-enabled nil)
        (dl-satan-patch-listener--proc nil))
    (should (null (dl-satan-patch-listener-start)))
    (should (null dl-satan-patch-listener--proc))))

(ert-deftest dl-satan-patch-listener/stop-is-idempotent ()
  (let ((dl-satan-patch-listener--proc nil))
    (should (null (dl-satan-patch-listener-stop)))
    (should (null (dl-satan-patch-listener-stop)))))

(ert-deftest dl-satan-patch-listener/status-when-not-running ()
  (let ((dl-satan-patch-listener--proc nil))
    (should (eq 'stopped (dl-satan-patch-listener-status)))))

;; ---------------------------------------------------------------------
;; sentinel — fail loud
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-patch-listener/report-death-fires-critical-notification ()
  (require 'notifications)
  (let ((notif-args nil))
    (cl-letf (((symbol-function 'notifications-notify)
               (lambda (&rest args) (setq notif-args args) 42)))
      (dl-satan-patch-listener--report-death 'exit 1 "boom\nfatal\n"))
    (should (equal 'critical (plist-get notif-args :urgency)))
    (should (string-match-p "satan-patch" (plist-get notif-args :title)))
    (should (string-match-p "boom" (plist-get notif-args :body)))))

(ert-deftest dl-satan-patch-listener/report-death-handles-nil-stderr ()
  (require 'notifications)
  (let ((notif-args nil))
    (cl-letf (((symbol-function 'notifications-notify)
               (lambda (&rest args) (setq notif-args args) 42)))
      (dl-satan-patch-listener--report-death 'signal 9 nil))
    (should (stringp (plist-get notif-args :body)))))

;; ---------------------------------------------------------------------
;; integration — gated on SATAN_PATCH_LIVE
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-patch-listener/integration-fires-from-real-pg ()
  "Real psql subprocess + real NOTIFY round-trip on satan_memory_test.
Mocks store-get + handoff to avoid the DB row dance; this verifies the
subprocess + filter wire end-to-end."
  (skip-unless (getenv "SATAN_PATCH_LIVE"))
  (skip-unless (executable-find "psql"))
  (let* ((dl-satan-patch-store-database "satan_memory_test")
         (dl-satan-patch-listener-enabled t)
         (dl-satan-patch-listener--proc nil)
         (received nil))
    (cl-letf (((symbol-function 'dl-satan-patch-store-get)
               (lambda (id &rest _)
                 (cons 'ok (list :id id :state "needs_review"))))
              ((symbol-function 'dl-satan-patch-inbox-handoff)
               (lambda (row) (push (plist-get row :id) received))))
      (unwind-protect
          (progn
            (dl-satan-patch-listener-start)
            (should (process-live-p dl-satan-patch-listener--proc))
            (accept-process-output dl-satan-patch-listener--proc 0.5)
            (dl-satan-patch-store--query
             "satan_memory_test"
             "SELECT pg_notify('patch_jobs_done', 'patch_live_test')"
             nil)
            (with-timeout (5 (ert-fail "timed out waiting for NOTIFY delivery"))
              (while (null received)
                (accept-process-output dl-satan-patch-listener--proc 0.2)))
            (should (member "patch_live_test" received)))
        (dl-satan-patch-listener-stop)))))

(provide 'dl-satan-patch-listener-test)
;;; dl-satan-patch-listener-test.el ends here
