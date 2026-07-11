;;; satan-tools-motive-test.el --- motive_* tool ert -*- lexical-binding: t; -*-

;; Phase 3.2 of perceptual-design.md.  Cover the two motive tools:
;;
;;   motive_read     no args, no capability, returns content + counts
;;   motive_replace  validates against §A7 / §A8 bounds, atomic write,
;;                   guarded by `:capability 'motive-write' on the
;;                   Phase 0.2 dispatcher rail
;;
;; File I/O is real but quarantined to a per-test tmp file via dynamic
;; rebinding of `satan-motive-file'.

(require 'ert)
(require 'cl-lib)
(require 'subr-x)
(require 'satan-tools)
(require 'satan-tools-motive)
(require 'satan-motive)

;; ---------------------------------------------------------------------
;; Fixtures
;; ---------------------------------------------------------------------

(defconst satan-tools-motive-test--tool-ctx
  '(:id "20260519T100000-motd-deadbe"
    :mode-name motd
    :capabilities (motive-write memory-write notify)
    :run-dir "/tmp/satan-run"))

(defconst satan-tools-motive-test--well-formed
  "* test: docs-after-error
  Docs after terminal error often substitute orientation for contact.
  :cue: project:emacs.d surface_transition:terminal->browser domain_kind:docs
  :cooldown_s: 1800
  :worked_count: 0

* ruminations
  - 2026-05-22  example rumination
")

(defmacro satan-tools-motive-test--with-tmp-file (sym &rest body)
  "Bind SYM to a fresh tmp file path; rebind `satan-motive-file' to
it for BODY's dynamic extent.  File deleted on exit."
  (declare (indent 1))
  `(let* ((,sym (make-temp-file "satan-motive-tool-" nil ".org"))
          (satan-motive-file ,sym))
     (unwind-protect (progn ,@body)
       (when (file-exists-p ,sym) (delete-file ,sym)))))

;; ---------------------------------------------------------------------
;; motive_read
;; ---------------------------------------------------------------------

(ert-deftest satan-tools-motive/read-returns-content-and-counts ()
  (satan-tools-motive-test--with-tmp-file path
    (with-temp-file path
      (insert satan-tools-motive-test--well-formed))
    (let ((result (satan-tool/motive-read
                   nil satan-tools-motive-test--tool-ctx)))
      (should (eq 'ok (car result)))
      (let ((payload (cdr result)))
        (should (= 1 (plist-get payload :active_motives)))
        (should (= 1 (plist-get payload :ruminations_count)))
        (should (= 3 (plist-get payload :max_active)))
        (should (= 10 (plist-get payload :max_ruminations)))
        (should (string-match-p "docs-after-error"
                                (plist-get payload :content)))))))

(ert-deftest satan-tools-motive/read-missing-file-returns-zero-counts ()
  "Silent self-suppression — missing file is a valid state (§S3)."
  (let* ((tmp (make-temp-file "satan-motive-missing-"))
         (_ (delete-file tmp))
         (satan-motive-file tmp)
         (result (satan-tool/motive-read
                  nil satan-tools-motive-test--tool-ctx)))
    (should (eq 'ok (car result)))
    (should (= 0 (plist-get (cdr result) :active_motives)))
    (should (equal "" (plist-get (cdr result) :content)))))

;; ---------------------------------------------------------------------
;; motive_replace — accept path
;; ---------------------------------------------------------------------

(ert-deftest satan-tools-motive/replace-writes-atomically ()
  (satan-tools-motive-test--with-tmp-file path
    (let ((result (satan-tool/motive-replace
                   (list :content satan-tools-motive-test--well-formed)
                   satan-tools-motive-test--tool-ctx)))
      (should (eq 'ok (car result)))
      (should (= 1 (plist-get (cdr result) :active_motives)))
      (should (file-readable-p path))
      (with-temp-buffer
        (insert-file-contents path)
        (should (equal (buffer-string)
                       satan-tools-motive-test--well-formed))))))

(ert-deftest satan-tools-motive/replace-rejects-non-string ()
  (satan-tools-motive-test--with-tmp-file _path
    (let ((result (satan-tool/motive-replace
                   '(:content 42)
                   satan-tools-motive-test--tool-ctx)))
      (should (eq 'error (car result)))
      (should (string-match-p "must be string" (cdr result))))))

;; ---------------------------------------------------------------------
;; motive_replace — reject paths (A7 / A8 via the handler)
;; ---------------------------------------------------------------------

(ert-deftest satan-tools-motive/replace-rejects-ceiling-field ()
  (satan-tools-motive-test--with-tmp-file path
    (let* ((bad "* test: bad
  :cue: app:firefox
  :ceiling: 5
")
           (result (satan-tool/motive-replace
                    (list :content bad)
                    satan-tools-motive-test--tool-ctx)))
      (should (eq 'error (car result)))
      (should (string-match-p "forbidden field" (cdr result)))
      ;; File untouched on reject (atomic-on-validation guarantee).
      ;; `make-temp-file' pre-creates an empty file; the rejected
      ;; write must leave it that way.
      (with-temp-buffer
        (insert-file-contents path)
        (should (zerop (buffer-size)))))))

(ert-deftest satan-tools-motive/replace-rejects-too-many-actives ()
  (satan-tools-motive-test--with-tmp-file _path
    (let* ((bad (concat "* test: a\n  :cue: app:firefox\n  :cooldown_s: 1800\n"
                        "* test: b\n  :cue: app:firefox\n  :cooldown_s: 1800\n"
                        "* test: c\n  :cue: app:firefox\n  :cooldown_s: 1800\n"
                        "* test: d\n  :cue: app:firefox\n  :cooldown_s: 1800\n"))
           (result (satan-tool/motive-replace
                    (list :content bad)
                    satan-tools-motive-test--tool-ctx)))
      (should (eq 'error (car result)))
      (should (string-match-p "too many active motives: limit 3, got 4"
                              (cdr result))))))

;; ---------------------------------------------------------------------
;; Dispatcher integration — capability rail + allowlist
;; ---------------------------------------------------------------------

(ert-deftest satan-tools-motive/dispatch-blocks-without-capability ()
  "Phase 0.2 — motive_replace requires `motive-write'.  A tool-ctx
without it is rejected before the handler runs."
  (satan-tools-motive-test--with-tmp-file path
    (let* ((no-cap-ctx (plist-put (copy-sequence
                                   satan-tools-motive-test--tool-ctx)
                                  :capabilities nil))
           (call (list :type "tool_call" :id "1" :name "motive_replace"
                       :args (list :content
                                   satan-tools-motive-test--well-formed)))
           (result (satan-tool-dispatch
                    call '("motive_replace") no-cap-ctx)))
      (should (eq :false (plist-get result :ok)))
      (should (string-match-p "capability denied"
                              (plist-get result :error)))
      ;; File untouched — capability denial happens before any write.
      (with-temp-buffer
        (insert-file-contents path)
        (should (zerop (buffer-size)))))))

(ert-deftest satan-tools-motive/dispatch-blocks-when-not-in-mode-allowlist ()
  (let* ((call (list :type "tool_call" :id "2" :name "motive_replace"
                     :args (list :content "irrelevant")))
         (result (satan-tool-dispatch
                  call '("memory_resonate")
                  satan-tools-motive-test--tool-ctx)))
    (should (eq :false (plist-get result :ok)))
    (should (string-match-p "not allowed" (plist-get result :error)))))

(ert-deftest satan-tools-motive/dispatch-read-needs-no-capability ()
  "motive_read declares no `:capability' — dispatcher must not gate
it on `motive-write'."
  (satan-tools-motive-test--with-tmp-file path
    (with-temp-file path (insert satan-tools-motive-test--well-formed))
    (let* ((no-cap-ctx (plist-put (copy-sequence
                                   satan-tools-motive-test--tool-ctx)
                                  :capabilities nil))
           (call (list :type "tool_call" :id "3" :name "motive_read"
                       :args nil))
           (result (satan-tool-dispatch
                    call '("motive_read") no-cap-ctx)))
      (should (eq t (plist-get result :ok))))))

;; ---------------------------------------------------------------------
;; Mode allowlist sanity (regression: handover §S1 sequence + §6 file map)
;; ---------------------------------------------------------------------

(ert-deftest satan-tools-motive/registered-with-capability ()
  (let ((spec (satan-tool-lookup "motive_replace")))
    (should spec)
    (should (eq 'motive-write (plist-get spec :capability)))
    (should (eq 'medium (plist-get spec :risk)))))

(ert-deftest satan-tools-motive/read-registered-without-capability ()
  (let ((spec (satan-tool-lookup "motive_read")))
    (should spec)
    (should (null (plist-get spec :capability)))
    (should (eq 'read (plist-get spec :risk)))))

(provide 'satan-tools-motive-test)
;;; satan-tools-motive-test.el ends here
