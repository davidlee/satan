;;; satan-patch-listener-test.el --- ert for LISTEN subprocess -*- lexical-binding: t; -*-

;; Tests for the postgres LISTEN subprocess that wakes
;; `satan-patch-inbox-handoff' on daemon-emitted NOTIFY events.

(require 'ert)
(require 'cl-lib)
(require 'satan-patch-listener)
(require 'satan-patch-store)
(require 'satan-patch-inbox)

;; ---------------------------------------------------------------------
;; helpers
;; ---------------------------------------------------------------------

(defun satan-patch-listener-test--notif-line (channel payload)
  "Build a `satan-attrd notify-stream' JSON line for CHANNEL + PAYLOAD."
  (format "{\"channel\":\"%s\",\"payload\":\"%s\"}\n" channel payload))

(defmacro satan-patch-listener-test--with-mocked-deps
    (received-var &rest body)
  "Bind RECEIVED-VAR to a list capturing handoff calls during BODY.
`satan-patch-store-get' returns a synthetic row; the inbox
handoff pushes the row onto RECEIVED-VAR."
  (declare (indent 1))
  `(let ((,received-var '()))
     (cl-letf (((symbol-function 'satan-patch-store-get)
                (lambda (id &rest _)
                  (cons 'ok (list :id id :state "needs_review"
                                  :mode "self-edit-mech"
                                  :repo "/tmp/repo"))))
               ((symbol-function 'satan-patch-inbox-handoff)
                (lambda (row) (push row ,received-var))))
       ,@body)))

;; ---------------------------------------------------------------------
;; filter — happy path
;; ---------------------------------------------------------------------

(ert-deftest satan-patch-listener/filter-emits-handoff-on-notification ()
  (satan-patch-listener-test--with-mocked-deps received
    (let ((filter (satan-patch-listener--make-filter)))
      (funcall filter nil
               (satan-patch-listener-test--notif-line
                "patch_jobs_done" "patch_abc"))
      (should (= 1 (length received)))
      (should (equal "patch_abc" (plist-get (car received) :id))))))

(ert-deftest satan-patch-listener/filter-fires-on-failed-channel ()
  (satan-patch-listener-test--with-mocked-deps received
    (let ((filter (satan-patch-listener--make-filter)))
      (funcall filter nil
               (satan-patch-listener-test--notif-line
                "patch_jobs_failed" "patch_xyz"))
      (should (= 1 (length received)))
      (should (equal "patch_xyz" (plist-get (car received) :id))))))

;; ---------------------------------------------------------------------
;; filter — buffering partial lines
;; ---------------------------------------------------------------------

(ert-deftest satan-patch-listener/filter-buffers-partial-lines ()
  (satan-patch-listener-test--with-mocked-deps received
    (let* ((filter (satan-patch-listener--make-filter))
           (full (satan-patch-listener-test--notif-line
                  "patch_jobs_done" "patch_split"))
           (mid (/ (length full) 2)))
      (funcall filter nil (substring full 0 mid))
      (should (= 0 (length received)))
      (funcall filter nil (substring full mid))
      (should (= 1 (length received)))
      (should (equal "patch_split" (plist-get (car received) :id))))))

(ert-deftest satan-patch-listener/filter-handles-multiple-notifications-in-chunk ()
  (satan-patch-listener-test--with-mocked-deps received
    (let ((filter (satan-patch-listener--make-filter)))
      (funcall filter nil
               (concat
                (satan-patch-listener-test--notif-line
                 "patch_jobs_done" "patch_a")
                (satan-patch-listener-test--notif-line
                 "patch_jobs_failed" "patch_b")))
      (should (= 2 (length received)))
      (should (equal '("patch_b" "patch_a")
                     (mapcar (lambda (r) (plist-get r :id)) received))))))

;; ---------------------------------------------------------------------
;; filter — defensive: ignore unknown channels + noise
;; ---------------------------------------------------------------------

(ert-deftest satan-patch-listener/filter-ignores-unknown-channel ()
  (satan-patch-listener-test--with-mocked-deps received
    (let ((filter (satan-patch-listener--make-filter)))
      (funcall filter nil
               (satan-patch-listener-test--notif-line
                "patch_jobs_other" "patch_a"))
      (should (= 0 (length received))))))

(ert-deftest satan-patch-listener/filter-ignores-non-notification-output ()
  (satan-patch-listener-test--with-mocked-deps received
    (let ((filter (satan-patch-listener--make-filter)))
      (funcall filter nil "psql (16.3)\nType \"help\" for help.\n\n")
      (should (= 0 (length received))))))

(ert-deftest satan-patch-listener/filter-skips-missing-row ()
  "store-get returning (ok . nil) must not call handoff."
  (let ((received '()))
    (cl-letf (((symbol-function 'satan-patch-store-get)
               (lambda (_ &rest _r) (cons 'ok nil)))
              ((symbol-function 'satan-patch-inbox-handoff)
               (lambda (row) (push row received))))
      (let ((filter (satan-patch-listener--make-filter)))
        (funcall filter nil
                 (satan-patch-listener-test--notif-line
                  "patch_jobs_done" "patch_missing"))
        (should (= 0 (length received)))))))

;; ---------------------------------------------------------------------
;; start/stop API
;; ---------------------------------------------------------------------

(ert-deftest satan-patch-listener/start-noop-when-disabled ()
  (let ((satan-patch-listener-enabled nil)
        (satan-patch-listener--proc nil))
    (should (null (satan-patch-listener-start)))
    (should (null satan-patch-listener--proc))))

(ert-deftest satan-patch-listener/stop-is-idempotent ()
  (let ((satan-patch-listener--proc nil))
    (should (null (satan-patch-listener-stop)))
    (should (null (satan-patch-listener-stop)))))

(ert-deftest satan-patch-listener/status-when-not-running ()
  (let ((satan-patch-listener--proc nil))
    (should (eq 'stopped (satan-patch-listener-status)))))

;; ---------------------------------------------------------------------
;; sentinel — fail loud
;; ---------------------------------------------------------------------

(ert-deftest satan-patch-listener/report-death-fires-critical-notification ()
  (require 'notifications)
  (let ((notif-args nil))
    (cl-letf (((symbol-function 'notifications-notify)
               (lambda (&rest args) (setq notif-args args) 42)))
      (satan-patch-listener--report-death 'exit 1 "boom\nfatal\n"))
    (should (equal 'critical (plist-get notif-args :urgency)))
    (should (string-match-p "satan-patch" (plist-get notif-args :title)))
    (should (string-match-p "boom" (plist-get notif-args :body)))))

(ert-deftest satan-patch-listener/report-death-handles-nil-stderr ()
  (require 'notifications)
  (let ((notif-args nil))
    (cl-letf (((symbol-function 'notifications-notify)
               (lambda (&rest args) (setq notif-args args) 42)))
      (satan-patch-listener--report-death 'signal 9 nil))
    (should (stringp (plist-get notif-args :body)))))

;; ---------------------------------------------------------------------
;; integration — gated on SATAN_PATCH_LIVE
;; ---------------------------------------------------------------------

(ert-deftest satan-patch-listener/integration-fires-from-real-pg ()
  "Real psql subprocess + real NOTIFY round-trip on satan_memory_test.
Mocks store-get + handoff to avoid the DB row dance; this verifies the
subprocess + filter wire end-to-end."
  (skip-unless (getenv "SATAN_PATCH_LIVE"))
  (skip-unless (executable-find "psql"))
  (let* ((satan-patch-store-database "satan_memory_test")
         (satan-patch-listener-enabled t)
         (satan-patch-listener--proc nil)
         (received nil))
    (cl-letf (((symbol-function 'satan-patch-store-get)
               (lambda (id &rest _)
                 (cons 'ok (list :id id :state "needs_review"))))
              ((symbol-function 'satan-patch-inbox-handoff)
               (lambda (row) (push (plist-get row :id) received))))
      (unwind-protect
          (progn
            (satan-patch-listener-start)
            (should (process-live-p satan-patch-listener--proc))
            (accept-process-output satan-patch-listener--proc 0.5)
            (satan-patch-store--query
             "satan_memory_test"
             "SELECT pg_notify('patch_jobs_done', 'patch_live_test')"
             nil)
            (with-timeout (5 (ert-fail "timed out waiting for NOTIFY delivery"))
              (while (null received)
                (accept-process-output satan-patch-listener--proc 0.2)))
            (should (member "patch_live_test" received)))
        (satan-patch-listener-stop)))))

(provide 'satan-patch-listener-test)
;;; satan-patch-listener-test.el ends here
