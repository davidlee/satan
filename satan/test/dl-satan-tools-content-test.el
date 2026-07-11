;;; dl-satan-tools-content-test.el --- ert tests for dl-satan-tools-content -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'dl-satan-tools)
(require 'dl-satan-tools-content)

;; --- Fixture helpers ------------------------------------------

(defvar dl-satan-tools-content-test--dir nil
  "Temp content store root bound during `--with-store'.")

(defmacro dl-satan-tools-content-test--with-store (&rest body)
  "Bind `dl-satan-tools-content-dir' to a temp content store for BODY.
Also binds `dl-satan-tools-descriptions-dir' to a temp dir so tool
schema assembly works in tests."
  (declare (indent 0))
  `(let* ((store-dir (make-temp-file "satan-content-" t))
          (desc-dir  (make-temp-file "satan-desc-" t))
          (dl-satan-tools-content-dir store-dir)
          (dl-satan-tools-descriptions-dir desc-dir))
     ;; Provide a minimal tool description so schema assembly doesn't crash
     (with-temp-file (expand-file-name "content_read.md" desc-dir)
       (insert "Read panopticon page captures."))
     (setq dl-satan-tools-content-test--dir store-dir)
     (unwind-protect (progn ,@body)
       (delete-directory store-dir t)
       (delete-directory desc-dir t))))

(defun dl-satan-tools-content-test--shard-dir (hash)
  "Return the shard directory path for HASH."
  (expand-file-name (substring hash 0 2) dl-satan-tools-content-test--dir))

(defun dl-satan-tools-content-test--write-sidecar (hash plist)
  "Write a .json sidecar for HASH from PLIST (plist -> json)."
  (let ((dir (dl-satan-tools-content-test--shard-dir hash)))
    (make-directory dir t)
    (with-temp-file (expand-file-name (concat hash ".json") dir)
      (insert (json-serialize (dl-satan-jsonl-prepare plist)
                              :null-object :null :false-object :false)))))

(defun dl-satan-tools-content-test--write-article-jsonl (entries)
  "Write ENTRIES (list of plists) as `articles.jsonl'."
  (let ((path (expand-file-name "articles.jsonl"
                                dl-satan-tools-content-test--dir)))
    (with-temp-file path
      (dolist (e entries)
        (insert (json-serialize (dl-satan-jsonl-prepare e)
                                :null-object :null :false-object :false))
        (insert "\n")))))

(cl-defun dl-satan-tools-content-test--article-plist (hash url domain title captured-at
                                                        &key quality-score)
  "Return a plist representing an articles.jsonl row."
  (list :content_hash hash
        :url url
        :domain domain
        :title title
        :captured_at captured-at
        :extractor "readability"
        :quality_score (or quality-score 1.0)))

(cl-defun dl-satan-tools-content-test--sidecar-plist (hash text-content &key excerpt)
  "Return a plist representing a sidecar .json."
  (list :content_hash hash
        :text_content text-content
        :excerpt (or excerpt (substring text-content 0 (min 80 (length text-content))))
        :content_html (concat "<html><body>" text-content "</body></html>")
        :length (length text-content)))

(defun dl-satan-tools-content-test--make-store (articles)
  "Create a temp content store from ARTICLES.
ARTICLES is a list of (hash url domain title captured-at text-content).
Also writes .json sidecars.  Returns the store dir."
  (cl-loop for (hash url domain title captured-at text-content) in articles
           do (dl-satan-tools-content-test--write-sidecar
               hash
               (dl-satan-tools-content-test--sidecar-plist
                hash text-content)))
  (dl-satan-tools-content-test--write-article-jsonl
   (cl-loop for (hash url domain title captured-at text-content) in articles
            collect (dl-satan-tools-content-test--article-plist
                     hash url domain title captured-at))))

;; --- recent tests ---------------------------------------------

(ert-deftest dl-satan-content/recent-returns-newest-first ()
  "Recent returns captures in newest-first order (file append order)."
  (dl-satan-tools-content-test--with-store
    (dl-satan-tools-content-test--make-store
     `(("a1a2a3a4a5a6a7a8a9a0b1b2b3b4b5b6b7b8b9b0c1c2c3c4c5c6c7c8c9c0d1d2"
        "https://example.com/1" "example.com" "Title 1" "2026-05-31T01:00:00.000Z" "Body one.")
       ("a1a2a3a4a5a6a7a8a9a0b1b2b3b4b5b6b7b8b9b0c1c2c3c4c5c6c7c8c9c0d1e2"
        "https://example.com/2" "example.com" "Title 2" "2026-05-31T02:00:00.000Z" "Body two.")
       ("a1a2a3a4a5a6a7a8a9a0b1b2b3b4b5b6b7b8b9b0c1c2c3c4c5c6c7c8c9c0d1f2"
        "https://example.com/3" "example.com" "Title 3" "2026-05-31T03:00:00.000Z" "Body three.")))
    (let* ((res (dl-satan-tool/content-read '(:scope "recent" :limit 2) nil))
           (p (cdr res))
           (caps (plist-get p :captures)))
      (should (eq (car res) 'ok))
      (should (equal (plist-get p :scope) "recent"))
      (should (equal (plist-get p :limit) 2))
      (should (equal (length caps) 2))
      (should (equal (plist-get (car caps) :url) "https://example.com/3"))
      (should (equal (plist-get (cadr caps) :url) "https://example.com/2")))))

(ert-deftest dl-satan-content/recent-clamps-default-limit ()
  "Missing :limit uses default; out-of-range clamps."
  (dl-satan-tools-content-test--with-store
    (dl-satan-tools-content-test--make-store
     `(("a1a2a3a4a5a6a7a8a9a0b1b2b3b4b5b6b7b8b9b0c1c2c3c4c5c6c7c8c9c0d1d2"
        "https://x.com" "x.com" "T" "2026-05-31T01:00:00.000Z" "Body.")))
    (let* ((default-res (dl-satan-tool/content-read '(:scope "recent") nil))
           (hi-res (dl-satan-tool/content-read '(:scope "recent" :limit 9999) nil))
           (lo-res (dl-satan-tool/content-read '(:scope "recent" :limit 0) nil)))
      (should (equal (plist-get (cdr default-res) :limit)
                     dl-satan-tools-content-default-limit))
      (should (equal (plist-get (cdr hi-res) :limit)
                     dl-satan-tools-content--limit-hard-max))
      (should (equal (plist-get (cdr lo-res) :limit) 1)))))

(ert-deftest dl-satan-content/recent-empty-store ()
  "Empty store returns ok with empty captures."
  (dl-satan-tools-content-test--with-store
    (let* ((res (dl-satan-tool/content-read '(:scope "recent") nil))
           (p (cdr res)))
      (should (eq (car res) 'ok))
      (should (equal (plist-get p :captures) '())))))

(ert-deftest dl-satan-content/recent-honours-scan-max ()
  "Recent caps scanned rows to `dl-satan-tools-content-recent-scan-max'.
With scan-max=2 and 5 articles, only the last 2 are returned even with limit=5."
  (dl-satan-tools-content-test--with-store
    (dl-satan-tools-content-test--make-store
     (cl-loop for i from 1 to 5 collect
              (list (format "a%063d" i)
                    (format "https://example.com/%d" i)
                    "example.com" (format "T%d" i)
                    (format "2026-05-31T0%d:00:00.000Z" i)
                    (format "Body %d." i))))
    (let ((dl-satan-tools-content-recent-scan-max 2))
      (let* ((res (dl-satan-tool/content-read '(:scope "recent" :limit 5) nil))
             (caps (plist-get (cdr res) :captures)))
        (should (eq (car res) 'ok))
        (should (<= (length caps) 2))
        ;; Should have the last 2 (i=4,5), reversed to newest-first (5,4)
        ;; (car (last caps)) = 4
        (should (equal (plist-get (car (last caps)) :url)
                       "https://example.com/4"))))))

;; --- get tests ------------------------------------------------

(ert-deftest dl-satan-content/get-returns-full-body-small ()
  "Get returns full text_content when body fits in a single page."
  (dl-satan-tools-content-test--with-store
    (dl-satan-tools-content-test--make-store
     `(("a1a2a3a4a5a6a7a8a9a0b1b2b3b4b5b6b7b8b9b0c1c2c3c4c5c6c7c8c9c0d1d2"
        "https://example.com/one" "example.com" "One"
        "2026-05-31T01:00:00.000Z" "Hello, world.")))
    (let* ((res (dl-satan-tool/content-read
                 `(:scope "get" :hash "a1a2a3a4a5a6a7a8a9a0b1b2b3b4b5b6b7b8b9b0c1c2c3c4c5c6c7c8c9c0d1d2") nil))
           (p (cdr res)))
      (should (eq (car res) 'ok))
      (should (equal (plist-get p :scope) "get"))
      (should (equal (plist-get p :hash) "a1a2a3a4a5a6a7a8a9a0b1b2b3b4b5b6b7b8b9b0c1c2c3c4c5c6c7c8c9c0d1d2"))
      (should (equal (plist-get p :text) "Hello, world."))
      (should (equal (plist-get p :total_chars) 13))
      (should (equal (plist-get p :offset) 0))
      (should (equal (plist-get p :returned) 13))
      (should (eq (plist-get p :next_offset) :null)))))

(ert-deftest dl-satan-content/get-paginates-large-body ()
  "Get returns a page of text_content with correct next_offset."
  (dl-satan-tools-content-test--with-store
    (let* ((long-body (make-string 12000 ?X))
           (hash "a1a2a3a4a5a6a7a8a9a0b1b2b3b4b5b6b7b8b9b0c1c2c3c4c5c6c7c8c9c0d1d2"))
      (dl-satan-tools-content-test--make-store
       `((,hash "https://example.com/long" "example.com" "Long"
          "2026-05-31T01:00:00.000Z" ,long-body)))
      ;; Page 1 — offset 0
      (let* ((res1 (dl-satan-tool/content-read
                    `(:scope "get" :hash ,hash :limit 5000) nil))
             (p1 (cdr res1)))
        (should (eq (car res1) 'ok))
        (should (equal (plist-get p1 :offset) 0))
        (should (equal (plist-get p1 :returned) 5000))
        (should (equal (plist-get p1 :next_offset) 5000))
        (should (equal (plist-get p1 :total_chars) 12000))
        (should (equal (length (plist-get p1 :text)) 5000)))
      ;; Page 2 — offset 5000
      (let* ((res2 (dl-satan-tool/content-read
                    `(:scope "get" :hash ,hash :offset 5000) nil))
             (p2 (cdr res2)))
        (should (eq (car res2) 'ok))
        (should (equal (plist-get p2 :offset) 5000))
        (should (equal (plist-get p2 :returned) 5000))
        (should (equal (plist-get p2 :next_offset) 10000)))
      ;; Page 3 — offset 10000, remaining 2000 chars
      (let* ((res3 (dl-satan-tool/content-read
                    `(:scope "get" :hash ,hash :offset 10000) nil))
             (p3 (cdr res3)))
        (should (eq (car res3) 'ok))
        (should (equal (plist-get p3 :returned) 2000))
        (should (eq (plist-get p3 :next_offset) :null))))))

(ert-deftest dl-satan-content/get-negative-offset-clamped-to-zero ()
  "Negative offset is clamped to 0 (DR-005 F-5)."
  (dl-satan-tools-content-test--with-store
    (dl-satan-tools-content-test--make-store
     `(("a1a2a3a4a5a6a7a8a9a0b1b2b3b4b5b6b7b8b9b0c1c2c3c4c5c6c7c8c9c0d1d2"
        "https://x.com" "x.com" "X" "2026-05-31T01:00:00.000Z" "Hello.")))
    (let* ((res (dl-satan-tool/content-read
                 '(:scope "get" :hash "a1a2a3a4a5a6a7a8a9a0b1b2b3b4b5b6b7b8b9b0c1c2c3c4c5c6c7c8c9c0d1d2" :offset -5) nil))
           (p (cdr res)))
      (should (eq (car res) 'ok))
      (should (equal (plist-get p :offset) 0))
      (should (equal (plist-get p :returned) 6)))))

(ert-deftest dl-satan-content/get-offset-past-end-empty ()
  "Offset >= total_chars returns empty text with next_offset :null."
  (dl-satan-tools-content-test--with-store
    (dl-satan-tools-content-test--make-store
     `(("a1a2a3a4a5a6a7a8a9a0b1b2b3b4b5b6b7b8b9b0c1c2c3c4c5c6c7c8c9c0d1d2"
        "https://x.com" "x.com" "X" "2026-05-31T01:00:00.000Z" "Hi.")))
    (let* ((res (dl-satan-tool/content-read
                 '(:scope "get" :hash "a1a2a3a4a5a6a7a8a9a0b1b2b3b4b5b6b7b8b9b0c1c2c3c4c5c6c7c8c9c0d1d2" :offset 999) nil))
           (p (cdr res)))
      (should (eq (car res) 'ok))
      (should (equal (plist-get p :returned) 0))
      (should (equal (plist-get p :text) ""))
      (should (eq (plist-get p :next_offset) :null)))))

(ert-deftest dl-satan-content/get-unknown-hash-error ()
  "Unknown hash returns a distinct 'unknown content_hash' error."
  (dl-satan-tools-content-test--with-store
    (dl-satan-tools-content-test--make-store
     `(("a1a2a3a4a5a6a7a8a9a0b1b2b3b4b5b6b7b8b9b0c1c2c3c4c5c6c7c8c9c0d1d2"
        "https://x.com" "x.com" "X" "2026-05-31T01:00:00.000Z" "Hi.")))
    (let* ((res (dl-satan-tool/content-read
                 '(:scope "get" :hash "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb") nil)))
      (should (eq (car res) 'error))
      (should (string-match-p "unknown content_hash" (cdr res))))))

(ert-deftest dl-satan-content/get-missing-sidecar-error ()
  "Hash present in index but missing sidecar gives distinct 'content body missing' error."
  (dl-satan-tools-content-test--with-store
    ;; Write article WITHOUT sidecar
    (dl-satan-tools-content-test--write-article-jsonl
     (list (dl-satan-tools-content-test--article-plist
            "a1a2a3a4a5a6a7a8a9a0b1b2b3b4b5b6b7b8b9b0c1c2c3c4c5c6c7c8c9c0d1d2"
            "https://x.com" "x.com" "X" "2026-05-31T01:00:00.000Z")))
    (let* ((res (dl-satan-tool/content-read
                 '(:scope "get" :hash "a1a2a3a4a5a6a7a8a9a0b1b2b3b4b5b6b7b8b9b0c1c2c3c4c5c6c7c8c9c0d1d2") nil)))
      (should (eq (car res) 'error))
      (should (string-match-p "content body missing" (cdr res))))))

;; --- filter tests ---------------------------------------------

(ert-deftest dl-satan-content/filter-by-domain ()
  "Filter returns only captures matching the given domain."
  (dl-satan-tools-content-test--with-store
    (dl-satan-tools-content-test--make-store
     `(("a000000000000000000000000000000000000000000000000000000000000001"
        "https://a.com/1" "a.com" "A1" "2026-05-31T01:00:00.000Z" "Body A1.")
       ("a000000000000000000000000000000000000000000000000000000000000002"
        "https://b.com/1" "b.com" "B1" "2026-05-31T02:00:00.000Z" "Body B1.")
       ("a000000000000000000000000000000000000000000000000000000000000003"
        "https://a.com/2" "a.com" "A2" "2026-05-31T03:00:00.000Z" "Body A2.")))
    (let* ((res (dl-satan-tool/content-read '(:scope "filter" :domain "a.com") nil))
           (p (cdr res))
           (caps (plist-get p :captures)))
      (should (eq (car res) 'ok))
      (should (equal (plist-get p :domain) "a.com"))
      (should (equal (length caps) 2))
      (should (equal (plist-get (car caps) :domain) "a.com"))
      (should (equal (plist-get (cadr caps) :domain) "a.com"))
      (should (plist-get (car caps) :excerpt))   ; excerpt present
      )))

(ert-deftest dl-satan-content/filter-by-url ()
  "Filter returns captures whose URL contains the substring."
  (dl-satan-tools-content-test--with-store
    (dl-satan-tools-content-test--make-store
     `(("a000000000000000000000000000000000000000000000000000000000000001"
        "https://example.com/blog/post-one" "example.com" "One"
        "2026-05-31T01:00:00.000Z" "Body 1.")
       ("a000000000000000000000000000000000000000000000000000000000000002"
        "https://example.com/about" "example.com" "About"
        "2026-05-31T02:00:00.000Z" "Body 2.")
       ("a000000000000000000000000000000000000000000000000000000000000003"
        "https://other.com/blog/other" "other.com" "Other"
        "2026-05-31T03:00:00.000Z" "Body 3.")))
    (let* ((res (dl-satan-tool/content-read '(:scope "filter" :url "blog") nil))
           (caps (plist-get (cdr res) :captures)))
      (should (eq (car res) 'ok))
      (should (equal (length caps) 2))
      ;; Both contain "blog" in URL
      (should (string-match-p "blog" (plist-get (car caps) :url)))
      (should (string-match-p "blog" (plist-get (cadr caps) :url))))))

(ert-deftest dl-satan-content/filter-by-domain-and-url ()
  "Filter with both domain and url applies both constraints."
  (dl-satan-tools-content-test--with-store
    (dl-satan-tools-content-test--make-store
     `(("a000000000000000000000000000000000000000000000000000000000000001"
        "https://other.com/blog/post" "other.com" "P1"
        "2026-05-31T01:00:00.000Z" "B1.")
       ("a000000000000000000000000000000000000000000000000000000000000002"
        "https://example.com/blog/post" "example.com" "P2"
        "2026-05-31T02:00:00.000Z" "B2.")
       ("a000000000000000000000000000000000000000000000000000000000000003"
        "https://other.com/about" "other.com" "P3"
        "2026-05-31T03:00:00.000Z" "B3.")))
    (let* ((res (dl-satan-tool/content-read
                 '(:scope "filter" :domain "example.com" :url "blog") nil))
           (caps (plist-get (cdr res) :captures)))
      (should (eq (car res) 'ok))
      (should (equal (length caps) 1))
      (should (equal (plist-get (car caps) :url) "https://example.com/blog/post")))))

(ert-deftest dl-satan-content/filter-empty-store ()
  "Filter on empty store returns ok with empty captures."
  (dl-satan-tools-content-test--with-store
    (let* ((res (dl-satan-tool/content-read '(:scope "filter" :domain "x.com") nil))
           (p (cdr res)))
      (should (eq (car res) 'ok))
      (should (equal (plist-get p :captures) '())))))

(ert-deftest dl-satan-content/filter-requires-domain-or-url ()
  "Filter with neither domain nor url errors (DR-005 §4.1), not match-all."
  (dl-satan-tools-content-test--with-store
    (dl-satan-tools-content-test--make-store
     `(("a000000000000000000000000000000000000000000000000000000000000001"
        "https://example.com/p" "example.com" "P1"
        "2026-05-31T01:00:00.000Z" "B1.")))
    (let ((res (dl-satan-tool/content-read '(:scope "filter") nil)))
      (should (eq (car res) 'error))
      (should (string-match-p "requires at least one" (cdr res))))))

;; --- search tests ---------------------------------------------

(ert-deftest dl-satan-content/search-finds-matches ()
  "Search returns matches from .md files with metadata from articles.jsonl."
  (dl-satan-tools-content-test--with-store
    (dl-satan-tools-content-test--make-store
     `(("a000000000000000000000000000000000000000000000000000000000000001"
        "https://example.com/quantum" "example.com" "Quantum"
        "2026-05-31T01:00:00.000Z" "Quantum mechanics is fascinating.")
       ("a000000000000000000000000000000000000000000000000000000000000002"
        "https://other.com/dogs" "other.com" "Dogs"
        "2026-05-31T02:00:00.000Z" "Dogs are loyal companions.")))
    ;; Also write .md files (search reads .md)
    (with-temp-file
        (expand-file-name
         "a0/a000000000000000000000000000000000000000000000000000000000000001.md"
         dl-satan-tools-content-test--dir)
      (insert "---\nurl: https://example.com/quantum\ntitle: Quantum\n---\n\nQuantum mechanics is fascinating.\n"))
    (with-temp-file
        (expand-file-name
         "a0/a000000000000000000000000000000000000000000000000000000000000002.md"
         dl-satan-tools-content-test--dir)
      (insert "---\nurl: https://other.com/dogs\ntitle: Dogs\n---\n\nDogs are loyal companions.\n"))
    (let* ((res (dl-satan-tool/content-read
                 '(:scope "search" :query "quantum") nil))
           (p (cdr res))
           (matches (plist-get p :matches)))
      (should (eq (car res) 'ok))
      (should (>= (length matches) 1))
      (should (equal (plist-get (car matches) :domain) "example.com"))
      (should (string-match-p "[Qq]uantum" (plist-get (car matches) :snippet))))))

(ert-deftest dl-satan-content/search-no-matches-empty ()
  "Search with no matches returns ok with empty matches."
  (dl-satan-tools-content-test--with-store
    (dl-satan-tools-content-test--make-store
     `(("a000000000000000000000000000000000000000000000000000000000000001"
        "https://x.com" "x.com" "X" "2026-05-31T01:00:00.000Z" "Hello.")))
    (let* ((res (dl-satan-tool/content-read
                 '(:scope "search" :query "xyznonexistent") nil))
           (p (cdr res)))
      (should (eq (car res) 'ok))
      (should (equal (plist-get p :matches) '())))))

(ert-deftest dl-satan-content/search-truncated-results ()
  "Search sets :truncated_results t when more matches than limit."
  (dl-satan-tools-content-test--with-store
    (dl-satan-tools-content-test--make-store
     (cl-loop for i from 1 to 5 collect
              (list (format "a%063d" i)
                    (format "https://example.com/%d" i)
                    "example.com" (format "T%d" i)
                    (format "2026-05-31T0%d:00:00.000Z" i)
                    (format "Body %d with common word present." i))))
    ;; Write .md files for search
    (cl-loop for i from 1 to 5
             do (let* ((hash (format "a%063d" i))
                       (dir (dl-satan-tools-content-test--shard-dir hash)))
                  (make-directory dir t)
                  (with-temp-file (expand-file-name (concat hash ".md") dir)
                    (insert (format "---\nurl: https://example.com/%d\n---\n\nBody %d with common word present.\n" i i)))))
    (let* ((res (dl-satan-tool/content-read
                 '(:scope "search" :query "common" :limit 2) nil))
           (p (cdr res)))
      (should (eq (car res) 'ok))
      (should (<= (length (plist-get p :matches)) 2))
      (should (eq (plist-get p :truncated_results) t)))))

(ert-deftest dl-satan-content/search-soft-fails-no-rg ()
  "Search returns ok with empty matches when rg is unavailable."
  (dl-satan-tools-content-test--with-store
    (let ((dl-satan-tools-content-rg-path "/nonexistent/rg"))
      (let* ((res (dl-satan-tool/content-read
                   '(:scope "search" :query "anything") nil))
             (p (cdr res)))
        (should (eq (car res) 'ok))
        (should (equal (plist-get p :matches) '()))))))

(ert-deftest dl-satan-content/search-dedupes-by-hash ()
  "Multiple rg hits for same file → only one match per hash."
  (dl-satan-tools-content-test--with-store
    (dl-satan-tools-content-test--make-store
     `(("a000000000000000000000000000000000000000000000000000000000000001"
        "https://example.com/repeat" "example.com" "Repeat"
        "2026-05-31T01:00:00.000Z" "repeat repeat repeat repeat repeat")))
    ;; .md with repeated word
    (let* ((hash "a000000000000000000000000000000000000000000000000000000000000001")
           (dir (dl-satan-tools-content-test--shard-dir hash)))
      (make-directory dir t)
      (with-temp-file (expand-file-name (concat hash ".md") dir)
        (insert "---\nurl: https://example.com/repeat\n---\n\nrepeat repeat repeat repeat repeat\n")))
    (let* ((res (dl-satan-tool/content-read
                 '(:scope "search" :query "repeat") nil))
           (matches (plist-get (cdr res) :matches)))
      (should (eq (car res) 'ok))
      ;; Should have exactly 1 match (deduped by hash), not 5
      (should (equal (length matches) 1)))))

(ert-deftest dl-satan-content/search-sorts-by-recency-desc ()
  "Search matches are ordered by captured_at DESC (F-2), not file/append order."
  (dl-satan-tools-content-test--with-store
    ;; Append order (1,2,3) deliberately differs from recency: 2 newest, 1 oldest.
    (dl-satan-tools-content-test--make-store
     `(("a000000000000000000000000000000000000000000000000000000000000001"
        "https://example.com/1" "example.com" "T1"
        "2026-05-31T01:00:00.000Z" "shared term one")
       ("a000000000000000000000000000000000000000000000000000000000000002"
        "https://example.com/2" "example.com" "T2"
        "2026-05-31T03:00:00.000Z" "shared term two")
       ("a000000000000000000000000000000000000000000000000000000000000003"
        "https://example.com/3" "example.com" "T3"
        "2026-05-31T02:00:00.000Z" "shared term three")))
    (cl-loop for i from 1 to 3
             do (let* ((hash (format "a%063d" i))
                       (dir (dl-satan-tools-content-test--shard-dir hash)))
                  (make-directory dir t)
                  (with-temp-file (expand-file-name (concat hash ".md") dir)
                    (insert (format "---\nurl: https://example.com/%d\n---\n\nshared term %d\n" i i)))))
    (let* ((res (dl-satan-tool/content-read '(:scope "search" :query "shared") nil))
           (matches (plist-get (cdr res) :matches))
           (hashes (mapcar (lambda (m) (plist-get m :hash)) matches)))
      (should (eq (car res) 'ok))
      (should (equal (length hashes) 3))
      ;; Newest captured_at first (…02 @03:00), then …03 @02:00, then …01 @01:00.
      (should (equal hashes
                     (list "a000000000000000000000000000000000000000000000000000000000000002"
                           "a000000000000000000000000000000000000000000000000000000000000003"
                           "a000000000000000000000000000000000000000000000000000000000000001"))))))

;; --- malformed line handling ----------------------------------

(ert-deftest dl-satan-content/malformed-jsonl-line-skipped ()
  "Malformed articles.jsonl line is skipped, not propagated as error."
  (dl-satan-tools-content-test--with-store
    (dl-satan-tools-content-test--make-store
     `(("a000000000000000000000000000000000000000000000000000000000000001"
        "https://example.com/1" "example.com" "Good" "2026-05-31T01:00:00.000Z" "Good.")
       ("a000000000000000000000000000000000000000000000000000000000000002"
        "https://example.com/2" "example.com" "AlsoGood" "2026-05-31T02:00:00.000Z" "Also good.")))
    ;; Append a malformed line to articles.jsonl
    (let ((path (expand-file-name "articles.jsonl"
                                  dl-satan-tools-content-test--dir)))
      (write-region "this is not json\n" nil path 'append))
    (let* ((res (dl-satan-tool/content-read '(:scope "recent" :limit 10) nil))
           (caps (plist-get (cdr res) :captures)))
      (should (eq (car res) 'ok))
      (should (>= (length caps) 2)))))

;; --- unknown scope --------------------------------------------

(ert-deftest dl-satan-content/unknown-scope-errors ()
  "Unknown :scope returns a structured error."
  (let ((res (dl-satan-tool/content-read '(:scope "nonesuch") nil)))
    (should (eq (car res) 'error))
    (should (string-match-p "unknown scope" (cdr res)))))

;; --- dispatch schema validation -------------------------------

(ert-deftest dl-satan-content/dispatch-schema-enum ()
  "Dispatcher rejects scope values outside the registered enum."
  (dl-satan-tools-content-test--with-store
    (let ((res (dl-satan-tool-dispatch
                '(:type "tool_call" :id "cr1" :name "content_read"
                  :args (:scope "tomorrow"))
                '("content_read") nil)))
      (should (equal (plist-get res :ok) :false))
      (should (string-match-p "must be one of" (plist-get res :error))))))

(ert-deftest dl-satan-content/dispatch-ok-call ()
  "Dispatcher correctly routes a valid call."
  (dl-satan-tools-content-test--with-store
    (dl-satan-tools-content-test--make-store
     `(("a1a2a3a4a5a6a7a8a9a0b1b2b3b4b5b6b7b8b9b0c1c2c3c4c5c6c7c8c9c0d1d2"
        "https://x.com" "x.com" "X" "2026-05-31T01:00:00.000Z" "Hi.")))
    (let ((res (dl-satan-tool-dispatch
                '(:type "tool_call" :id "cr1" :name "content_read"
                  :args (:scope "get" :hash "a1a2a3a4a5a6a7a8a9a0b1b2b3b4b5b6b7b8b9b0c1c2c3c4c5c6c7c8c9c0d1d2"))
                '("content_read") nil)))
      (should (equal (plist-get res :ok) t))
      (should (plist-get res :result))
      (should (equal (plist-get (plist-get res :result) :text) "Hi.")))))

(provide 'dl-satan-tools-content-test)
;;; dl-satan-tools-content-test.el ends here
