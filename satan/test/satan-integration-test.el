;;; satan-integration-test.el --- End-to-end broker run -*- lexical-binding: t; -*-

;; Drives `satan-broker-run' against the real jailed fake harness in an
;; isolated temp notes root.  Skipped unless SATAN_TEST_JAIL_BIN points at
;; the jailed binary.
;;
;;   JAIL=$(nix build .#satan-jailed-fake-harness --no-link --print-out-paths)/bin/jailed-satan-fake-harness
;;   SATAN_TEST_JAIL_BIN=$JAIL emacs --batch \
;;     -L core -L lisp -L org -L satan -L satan/test \
;;     -l satan/test/satan-integration-test.el \
;;     -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'satan)

(defvar satan-test--jail-bin (getenv "SATAN_TEST_JAIL_BIN"))

(defun satan-test--wait-for-finalize (run-id timeout)
  "Block until status file exists in the run dir, or TIMEOUT seconds elapse."
  (let* ((dir (expand-file-name run-id satan-runs-dir))
         (status-path (expand-file-name "status" dir))
         (deadline (+ (float-time) timeout)))
    (while (and (not (file-readable-p status-path))
                (< (float-time) deadline))
      (accept-process-output nil 0.05))
    (file-readable-p status-path)))

(ert-deftest satan-integration/morning-end-to-end ()
  (skip-unless (and satan-test--jail-bin
                    (file-executable-p satan-test--jail-bin)))
  (let* ((temp (make-temp-file "satan-it-" t))
         (journal-dir (expand-file-name "journal" temp))
         (runs-dir    (expand-file-name "satan/runs" temp))
         (hipp-dir    (expand-file-name "satan/hippocampus" temp))
         (motd-path   (expand-file-name "satan/motd.txt" temp)))
    (make-directory journal-dir t)
    (make-directory runs-dir t)
    (make-directory hipp-dir t)
    ;; Override the harness command + paths.  Use a copy of the morning
    ;; mode so we don't mutate the global registry permanently.
    (let* ((satan-notes-root temp)
           ;; Inject today's-journal resolver (the config wires `my/journal--*'
           ;; here in production); the broker writes the SATAN block into it.
           (satan-journal-today
            (lambda ()
              (let ((f (expand-file-name
                        (format-time-string "%Y-%m-%d.org") journal-dir)))
                (unless (file-exists-p f) (write-region "" nil f))
                f)))
           (satan-runs-dir runs-dir)
           (satan-hippocampus-dir hipp-dir)
           (satan-motd-path motd-path)
           ;; Shadow the morning mode with an absolute-path harness.
           (mode (copy-tree (satan-mode-resolve "morning")))
           (_ (plist-put mode :harness
                         (list :cmd satan-test--jail-bin :args () :env nil)))
           (satan-modes
            (cons (cons "morning" mode)
                  (cl-remove "morning" satan-modes
                             :key #'car :test #'equal))))
      (unwind-protect
          (let ((run-id (satan-broker-run "morning")))
            (should (stringp run-id))
            (should (satan-test--wait-for-finalize run-id 10))
            (let* ((run-dir (expand-file-name run-id runs-dir))
                   (status-path (expand-file-name "status" run-dir))
                   (status (string-trim
                            (with-temp-buffer
                              (insert-file-contents status-path)
                              (buffer-string)))))
              (should (equal status "done"))
              (should (eq (satan-audit-verify-run run-dir) t))
              (should (file-readable-p (expand-file-name "final.json" run-dir)))
              (should (file-readable-p (expand-file-name "actions.json" run-dir)))
              ;; Daily-note should now contain the SATAN block.
              (let ((today (satan-notes-today)))
                (should (file-readable-p today))
                (let ((text (with-temp-buffer
                              (insert-file-contents today)
                              (buffer-string))))
                  (should (string-match-p
                           "#\\+begin_satan :block satan :owner SATAN" text))
                  (should (string-match-p "SATAN was here\\." text))))))
        (delete-directory temp t)))))

(provide 'satan-integration-test)
;;; satan-integration-test.el ends here
