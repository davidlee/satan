;;; satan-memory-content-rule-test.el --- ert for panopticon.content rule -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'satan-tools-content)
(require 'satan-tools-content-test nil t) ; fixture macros
(require 'satan-memory-evidence)
(require 'satan-memory-canon)
(require 'satan-resonance)

;; --- Evidence probe tests --------------------------------------

(ert-deftest satan-memory-content/probe-returns-ok-with-metadata ()
  "Content probe returns (cons \"ok\" CAPTURES) with correct metadata shape."
  (satan-tools-content-test--with-store
    (let ((article1 (satan-tools-content-test--article-plist
                     "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
                     "https://example.com/1" "example.com"
                     "Article One" "2026-05-31T05:00:00.000Z"))
          (article2 (satan-tools-content-test--article-plist
                     "b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5"
                     "https://other.example/2" "other.example"
                     "Article Two" "2026-05-31T05:25:45.968Z")))
      (satan-tools-content-test--write-article-jsonl
       (list article1 article2))
      (let* ((result (satan-memory-evidence--content-probe 10))
             (status (car result))
             (captures (cdr result)))
        (should (equal "ok" status))
        (should (= 2 (length captures)))
        (let ((c1 (elt captures 0)))
          (should (equal "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
                         (plist-get c1 :hash)))
          (should (equal "example.com" (plist-get c1 :domain)))
          (should (equal "https://example.com/1" (plist-get c1 :url)))
          (should (equal "Article One" (plist-get c1 :title)))
          (should (equal "2026-05-31T05:00:00.000Z"
                         (plist-get c1 :captured_at))))
        (let ((c2 (elt captures 1)))
          (should (equal "other.example" (plist-get c2 :domain)))
          (should (equal "Article Two" (plist-get c2 :title))))))))

(ert-deftest satan-memory-content/probe-empty-store-returns-missing ()
  "Empty content store → (cons \"missing\" '())."
  (satan-tools-content-test--with-store
    ;; No articles.jsonl written
    (let* ((result (satan-memory-evidence--content-probe 10))
           (status (car result))
           (captures (cdr result)))
      (should (equal "missing" status))
      (should (null captures)))))

(ert-deftest satan-memory-content/probe-respects-limit ()
  "Content probe returns at most LIMIT captures."
  (satan-tools-content-test--with-store
    (let ((articles
           (cl-loop for i from 1 to 5
                    collect (satan-tools-content-test--article-plist
                             (format "%064d" i)
                             (format "https://example.com/%d" i) "example.com"
                             (format "Article %d" i)
                             (format "2026-05-31T0%d:00:00.000Z" i)))))
      (satan-tools-content-test--write-article-jsonl articles)
      (let* ((result (satan-memory-evidence--content-probe 3))
             (captures (cdr result)))
        (should (equal "ok" (car result)))
        (should (= 3 (length captures)))))))

(ert-deftest satan-memory-content/probe-malformed-line-skipped ()
  "Content probe skips malformed jsonl lines (O-1)."
  (satan-tools-content-test--with-store
    (let ((path (expand-file-name "articles.jsonl"
                                  satan-tools-content-test--dir)))
      (with-temp-file path
        (insert (json-serialize
                 (satan-tools-content-test--article-plist
                  "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
                  "https://example.com/1" "example.com"
                  "Article One" "2026-05-31T05:00:00.000Z")))
        (insert "\n")
        (insert "{broken json\n")
        (insert (json-serialize
                 (satan-tools-content-test--article-plist
                  "b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5"
                  "https://example.com/2" "example.com"
                  "Article Two" "2026-05-31T05:25:45.968Z")))
        (insert "\n")))
    (let* ((result (satan-memory-evidence--content-probe 10))
           (captures (cdr result)))
      (should (equal "ok" (car result)))
      (should (= 2 (length captures))))))

;; --- Canon defrule tests ---------------------------------------

(defun satan-memory-content-test--apply-rule (evidence &optional hints ctx)
  "Apply the panopticon.content rule to EVIDENCE, return emission handles."
  (let ((emissions (satan-memory-canon--rule/panopticon.content
                    evidence (or hints '()) (or ctx '()))))
    (mapcar (lambda (e) (plist-get e :handle)) emissions)))

(ert-deftest satan-memory-content/rule-emits-content-domain-handles ()
  "panopticon.content emits content_domain:<d> per unique domain."
  (let ((evidence (list :content_recent
                        (list
                         (list :hash "aaa" :domain "example.com"
                               :url "https://example.com/1"
                               :title "Article One"
                               :captured_at "2026-05-31T05:00:00.000Z")
                         (list :hash "bbb" :domain "other.example"
                               :url "https://other.example/2"
                               :title "Article Two"
                               :captured_at "2026-05-31T05:25:45.968Z")
                         (list :hash "ccc" :domain "example.com"
                               :url "https://example.com/3"
                               :title "Article Three"
                               :captured_at "2026-05-31T06:00:00.000Z")))))
    (let ((handles (satan-memory-content-test--apply-rule evidence)))
      (should (= 2 (length handles)))
      (should (member "content_domain:example.com" handles))
      (should (member "content_domain:other.example" handles))
      (should (= 1 (cl-count "content_domain:example.com"
                             handles :test #'string=))))))

(ert-deftest satan-memory-content/rule-empty-content-recent ()
  "Empty :content_recent → no emissions."
  (let ((evidence (list :content_recent '())))
    (let ((handles (satan-memory-content-test--apply-rule evidence)))
      (should (null handles)))))

(ert-deftest satan-memory-content/rule-no-content-recent ()
  "Missing :content_recent → no emissions, no crash."
  (let ((evidence '(:other_key "value")))
    (let ((handles (satan-memory-content-test--apply-rule evidence)))
      (should (null handles)))))

;; --- Resonance admittability test ------------------------------

(ert-deftest satan-memory-content/panopticon-content-admits-resonance ()
  "panopticon.content is NOT in the §S2 exclude list → its handles admit resonance."
  (should-not (member "panopticon.content"
                      satan-resonance--excluded-rule-ids))
  ;; Verify a handle with rule_id panopticon.content passes the gate
  (let ((sources (list (list :rule_id "panopticon.content"
                             :handle "content_domain:example.com"))))
    (should (satan-resonance--admittable-p sources))))

(ert-deftest satan-memory-content/only-excluded-rules-fail-gate ()
  "Handles from only-excluded rules do NOT admit §S2."
  (let ((sources (list (list :rule_id "ctx.mode" :handle "mode:tick-pulse")
                       (list :rule_id "time.day_week" :handle "day:sat"))))
    (should-not (satan-resonance--admittable-p sources))))

(provide 'satan-memory-content-rule-test)
;;; satan-memory-content-rule-test.el ends here
