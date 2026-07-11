;;; satan-sensor-content-test.el --- ert tests for satan-sensor-content -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'satan-attribute)           ; load before tests (defcustoms)
(require 'satan-tools-content)
(require 'satan-tools-content-test nil t) ; fixture macros
(require 'satan-sensor-content)

;; --- Helpers ---------------------------------------------------

(defmacro satan-sensor-content-test--with-temp-state (state-var &rest body)
  "Bind STATE-VAR to a temp file path for sensor-content state during BODY."
  (declare (indent 1))
  `(let ((,state-var (make-temp-file "satan-sensor-content-state-")))
     (unwind-protect
         (progn ,@body)
       (ignore-errors (delete-file ,state-var)))))

(defun satan-sensor-content-test--read-state (path)
  "Read sensor-content state JSON at PATH, return plist or nil."
  (when (file-readable-p path)
    (with-temp-buffer
      (insert-file-contents path)
      (json-parse-buffer :object-type 'plist))))

(defun satan-sensor-content-test--write-state (path plist)
  "Write PLIST as JSON to PATH."
  (with-temp-file path
    (insert (json-serialize plist :null-object :null :false-object :false))))

(defun satan-sensor-content-test--seed-state (path watermark)
  "Write a state file at PATH with :last_inspected WATERMARK."
  (satan-sensor-content-test--write-state path (list :last_inspected watermark)))

;; --- Tests -----------------------------------------------------

(ert-deftest satan-sensor-content/backlog-detected-emits-and-advances ()
  "When captures exist newer than the watermark, probe emits and advances watermark."
  (satan-sensor-content-test--with-temp-state state-path
    (satan-tools-content-test--with-store
      (let ((article1 (satan-tools-content-test--article-plist
                       "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
                       "https://example.com/1" "example.com"
                       "Article One" "2026-05-31T05:00:00.000Z"))
            (article2 (satan-tools-content-test--article-plist
                       "b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5"
                       "https://example.com/2" "example.com"
                       "Article Two" "2026-05-31T05:25:45.968Z"))
            (article3 (satan-tools-content-test--article-plist
                       "c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6"
                       "https://other.example/3" "other.example"
                       "Article Three" "2026-05-31T06:00:00.000Z")))
        (satan-tools-content-test--write-article-jsonl
         (list article1 article2 article3))
        (satan-sensor-content-test--seed-state
         state-path "2026-05-31T05:00:00.000Z")
        (let ((satan-sensor-content-state-file state-path)
              (satan-sensor-content-enabled t))
          (let ((result (satan-sensor-content-probe
                         :run-id "test-run-1"
                         :ts "2026-05-31T06:30:00+10:00")))
            ;; Should emit (2 captures after the seed watermark)
            (should result)
            ;; Watermark must advance to max captured_at (article3), NOT the ts
            (let ((state (satan-sensor-content-test--read-state state-path)))
              (should (equal "2026-05-31T06:00:00.000Z"
                             (plist-get state :last_inspected))))))))))

(ert-deftest satan-sensor-content/no-backlog-no-emit ()
  "When all captures are ≤ watermark, probe returns nil and watermark unchanged."
  (satan-sensor-content-test--with-temp-state state-path
    (satan-tools-content-test--with-store
      (let ((article1 (satan-tools-content-test--article-plist
                       "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
                       "https://example.com/1" "example.com"
                       "Article One" "2026-05-31T05:00:00.000Z")))
        (satan-tools-content-test--write-article-jsonl (list article1))
        ;; Watermark already ahead of all captures
        (satan-sensor-content-test--seed-state
         state-path "2026-05-31T06:00:00.000Z")
        (let ((satan-sensor-content-state-file state-path)
              (satan-sensor-content-enabled t))
          (let ((result (satan-sensor-content-probe
                         :run-id "test-run-2"
                         :ts "2026-05-31T06:30:00+10:00")))
            (should-not result)
            ;; Watermark unchanged
            (let ((state (satan-sensor-content-test--read-state state-path)))
              (should (equal "2026-05-31T06:00:00.000Z"
                             (plist-get state :last_inspected))))))))))

(ert-deftest satan-sensor-content/dec5-watermark-is-captured-at-not-ts ()
  "DEC-5: watermark is max captured_at string verbatim, NOT broker's formatted ts."
  (satan-sensor-content-test--with-temp-state state-path
    (satan-tools-content-test--with-store
      (let ((article (satan-tools-content-test--article-plist
                      "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
                      "https://example.com/1" "example.com"
                      "Article One" "2026-05-31T05:25:45.968Z")))
        (satan-tools-content-test--write-article-jsonl (list article))
        (satan-sensor-content-test--seed-state state-path "")
        (let ((satan-sensor-content-state-file state-path)
              (satan-sensor-content-enabled t))
          (satan-sensor-content-probe
           :run-id "test-dec5"
           :ts "2026-05-31T15:30:00+10:00") ; broker ts — DIFFERENT format
          (let ((wm (plist-get (satan-sensor-content-test--read-state state-path)
                               :last_inspected)))
            ;; DEC-5: watermark MUST be the captured_at string, NOT the broker ts
            (should (equal "2026-05-31T05:25:45.968Z" wm))
            ;; DEC-5: watermark must NOT be the broker ts
            (should-not (equal "2026-05-31T15:30:00+10:00" wm))))))))

(ert-deftest satan-sensor-content/disabled-returns-nil ()
  "When satan-sensor-content-enabled is nil, probe returns nil without emit."
  (satan-sensor-content-test--with-temp-state state-path
    (satan-tools-content-test--with-store
      (let ((article (satan-tools-content-test--article-plist
                      "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
                      "https://example.com/1" "example.com"
                      "Article One" "2026-05-31T05:25:45.968Z")))
        (satan-tools-content-test--write-article-jsonl (list article))
        (satan-sensor-content-test--seed-state state-path "")
        (let ((satan-sensor-content-state-file state-path)
              (satan-sensor-content-enabled nil)) ; DISABLED
          (let ((result (satan-sensor-content-probe
                         :run-id "test-disabled"
                         :ts "2026-05-31T06:30:00+10:00")))
            (should-not result)
            ;; Watermark must NOT advance when disabled
            (let ((wm (plist-get (satan-sensor-content-test--read-state state-path)
                                 :last_inspected)))
              (should (equal "" wm)))))))))

(ert-deftest satan-sensor-content/empty-store-no-crash ()
  "Empty articles.jsonl → no emit, no crash."
  (satan-sensor-content-test--with-temp-state state-path
    (satan-tools-content-test--with-store
      ;; No articles.jsonl written — empty store
      (satan-sensor-content-test--seed-state state-path "")
      (let ((satan-sensor-content-state-file state-path)
            (satan-sensor-content-enabled t))
        (let ((result (satan-sensor-content-probe
                       :run-id "test-empty"
                       :ts "2026-05-31T06:30:00+10:00")))
          (should-not result))))))

(ert-deftest satan-sensor-content/malformed-line-skipped ()
  "Malformed jsonl lines are skipped (O-1), valid lines still counted."
  (satan-sensor-content-test--with-temp-state state-path
    (satan-tools-content-test--with-store
      ;; Write articles.jsonl manually with a malformed line between valid ones
      (let ((path (expand-file-name "articles.jsonl"
                                    satan-tools-content-test--dir)))
        (with-temp-file path
          (insert (json-serialize
                   (satan-tools-content-test--article-plist
                    "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
                    "https://example.com/1" "example.com"
                    "Article One" "2026-05-31T05:00:00.000Z")))
          (insert "\n")
          ;; Malformed line (half-written by concurrent append)
          (insert "{broken json\n")
          (insert (json-serialize
                   (satan-tools-content-test--article-plist
                    "b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5"
                    "https://example.com/2" "example.com"
                    "Article Two" "2026-05-31T05:25:45.968Z")))
          (insert "\n")))
      (satan-sensor-content-test--seed-state state-path "")
      (let ((satan-sensor-content-state-file state-path)
            (satan-sensor-content-enabled t))
        (let ((result (satan-sensor-content-probe
                       :run-id "test-malformed"
                       :ts "2026-05-31T06:30:00+10:00")))
          ;; Should emit — 2 valid captures uninspected
          (should result)
          (let ((state (satan-sensor-content-test--read-state state-path)))
            ;; Watermark should be the max captured_at of valid lines
            (should (equal "2026-05-31T05:25:45.968Z"
                           (plist-get state :last_inspected)))))))))

(ert-deftest satan-sensor-content/initial-watermark-empty-string ()
  "Initial watermark is empty string, which sorts before all timestamps."
  (satan-sensor-content-test--with-temp-state state-path
    (satan-tools-content-test--with-store
      (let ((article (satan-tools-content-test--article-plist
                      "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
                      "https://example.com/1" "example.com"
                      "Article One" "2026-05-31T05:25:45.968Z")))
        (satan-tools-content-test--write-article-jsonl (list article))
        ;; No seed — probe reads empty state file (or non-existent) → watermark ""
        (let ((satan-sensor-content-state-file state-path)
              (satan-sensor-content-enabled t))
          (let ((result (satan-sensor-content-probe
                         :run-id "test-initial"
                         :ts "2026-05-31T06:30:00+10:00")))
            ;; With empty watermark, every capture is uninspected
            (should result)
            (should (equal "2026-05-31T05:25:45.968Z"
                           (plist-get
                            (satan-sensor-content-test--read-state state-path)
                            :last_inspected)))))))))

(ert-deftest satan-sensor-content/no-run-id-guards ()
  "When run-id is nil, probe returns nil (guarded same as curiosity)."
  (satan-sensor-content-test--with-temp-state state-path
    (satan-tools-content-test--with-store
      (let ((article (satan-tools-content-test--article-plist
                      "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
                      "https://example.com/1" "example.com"
                      "Article One" "2026-05-31T05:25:45.968Z")))
        (satan-tools-content-test--write-article-jsonl (list article))
        (satan-sensor-content-test--seed-state state-path "")
        (let ((satan-sensor-content-state-file state-path)
              (satan-sensor-content-enabled t))
          (let ((result (satan-sensor-content-probe
                         :run-id nil    ; no run-id
                         :ts "2026-05-31T06:30:00+10:00")))
            (should-not result)))))))

(ert-deftest satan-sensor-content/soft-fails-on-error ()
  "An error inside the probe is caught: returns nil, never propagates (DR-005 §5)."
  (satan-sensor-content-test--with-temp-state state-path
    (satan-tools-content-test--with-store
      (let ((article (satan-tools-content-test--article-plist
                      "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
                      "https://example.com/1" "example.com"
                      "Article One" "2026-05-31T05:25:45.968Z")))
        (satan-tools-content-test--write-article-jsonl (list article))
        (satan-sensor-content-test--seed-state state-path "")
        (let ((satan-sensor-content-state-file state-path)
              (satan-sensor-content-enabled t)
              (satan-attribute-updates-enabled t))
          (cl-letf (((symbol-function 'satan-sensor-content--count-uninspected)
                     (lambda (&rest _) (error "boom"))))
            ;; Must not signal; soft-fails to nil.
            (should-not (satan-sensor-content-probe
                         :run-id "test-run-soft-fail"
                         :ts "2026-05-31T06:30:00+10:00"))))))))

;; --- VT-probe-split (DR-010 §5): read/commit split -------------

(ert-deftest satan-sensor-content/read-snapshot-charges-nothing ()
  "VT-probe-split: `-probe-read' enqueues nothing and never advances the
watermark.  The forbidden writers are spied to fail if called."
  (satan-sensor-content-test--with-temp-state state-path
    (satan-tools-content-test--with-store
      (satan-tools-content-test--write-article-jsonl
       (list (satan-tools-content-test--article-plist
              "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
              "https://example.com/1" "example.com"
              "Article One" "2026-05-31T06:00:00.000Z")))
      (satan-sensor-content-test--seed-state state-path "2026-05-31T05:00:00.000Z")
      (let ((satan-sensor-content-state-file state-path)
            (satan-sensor-content-enabled t)
            (satan-attribute-updates-enabled t))
        (cl-letf (((symbol-function 'satan-attribute-enqueue)
                   (lambda (&rest _) (ert-fail "read enqueued an attribute")))
                  ((symbol-function 'satan-sensor-content-mark-inspected)
                   (lambda (&rest _) (ert-fail "read advanced the watermark"))))
          (let ((snap (satan-sensor-content-probe-read
                       :run-id "rid" :ts "2026-05-31T06:30:00+10:00")))
            (should (plist-get snap :emit))
            ;; Watermark untouched by the read.
            (should (equal (plist-get
                            (satan-sensor-content-test--read-state state-path)
                            :last_inspected)
                           "2026-05-31T05:00:00.000Z"))))))))

(ert-deftest satan-sensor-content/commit-advances-to-max-captured-at-not-ts ()
  "VT-probe-split: commit advances the watermark to the snapshot's native
high-water captured_at (max across rows), NOT the broker `ts'.  Rows are
written out of `captured_at' order to prove the max wins and the lagging
row is still counted."
  (satan-sensor-content-test--with-temp-state state-path
    (satan-tools-content-test--with-store
      ;; Out-of-order: newest captured_at (06:00) listed before older (05:30).
      (satan-tools-content-test--write-article-jsonl
       (list (satan-tools-content-test--article-plist
              "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
              "https://example.com/1" "example.com"
              "Newer" "2026-05-31T06:00:00.000Z")
             (satan-tools-content-test--article-plist
              "b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5"
              "https://example.com/2" "example.com"
              "Older" "2026-05-31T05:30:00.000Z")))
      (satan-sensor-content-test--seed-state state-path "2026-05-31T05:00:00.000Z")
      (let ((satan-sensor-content-state-file state-path)
            (satan-sensor-content-enabled t)
            (satan-attribute-updates-enabled t))
        (cl-letf (((symbol-function 'satan-attribute-enqueue)
                   (lambda (&rest _) nil)))
          (let* ((ts "2026-05-31T15:30:00+10:00") ; broker ts — must NOT win
                 (snap (satan-sensor-content-probe-read :run-id "rid" :ts ts)))
            (should (plist-get snap :emit))
            (should (equal (plist-get snap :high-water) "2026-05-31T06:00:00.000Z"))
            (should (satan-sensor-content-probe-commit snap))
            (let ((wm (plist-get
                       (satan-sensor-content-test--read-state state-path)
                       :last_inspected)))
              (should (equal wm "2026-05-31T06:00:00.000Z"))
              (should-not (equal wm ts)))))))))

(ert-deftest satan-sensor-content/read-without-commit-keeps-backlog ()
  "VT-probe-split: a read taken but never committed (budget-denied path)
leaves the watermark unchanged; a later commit still sees the backlog."
  (satan-sensor-content-test--with-temp-state state-path
    (satan-tools-content-test--with-store
      (satan-tools-content-test--write-article-jsonl
       (list (satan-tools-content-test--article-plist
              "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
              "https://example.com/1" "example.com"
              "Article One" "2026-05-31T06:00:00.000Z")))
      (satan-sensor-content-test--seed-state state-path "2026-05-31T05:00:00.000Z")
      (let ((satan-sensor-content-state-file state-path)
            (satan-sensor-content-enabled t)
            (satan-attribute-updates-enabled t))
        (cl-letf (((symbol-function 'satan-attribute-enqueue)
                   (lambda (&rest _) nil)))
          ;; First tick: read only, no commit.
          (let ((snap1 (satan-sensor-content-probe-read
                        :run-id "rid" :ts "2026-05-31T06:30:00+10:00")))
            (should (plist-get snap1 :emit))
            (should (equal (plist-get
                            (satan-sensor-content-test--read-state state-path)
                            :last_inspected)
                           "2026-05-31T05:00:00.000Z")))
          ;; Next tick: backlog still visible; commit advances the watermark.
          (let ((snap2 (satan-sensor-content-probe-read
                        :run-id "rid" :ts "2026-05-31T06:45:00+10:00")))
            (should (plist-get snap2 :emit))
            (should (equal (plist-get snap2 :high-water) "2026-05-31T06:00:00.000Z"))
            (should (satan-sensor-content-probe-commit snap2))
            (should (equal (plist-get
                            (satan-sensor-content-test--read-state state-path)
                            :last_inspected)
                           "2026-05-31T06:00:00.000Z"))))))))

(provide 'satan-sensor-content-test)
;;; satan-sensor-content-test.el ends here
