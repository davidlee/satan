;;; satan-tools-docs-test.el --- docs_* tool tests -*- lexical-binding: t; -*-

;; Run from CLI:
;;   emacs --batch \
;;     -L ~/.emacs.d/core -L ~/.emacs.d/satan -L ~/.emacs.d/satan/test \
;;     -l satan-tools-docs-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'satan-tools)
(require 'satan-tools-docs)

(defconst satan-tools-docs-test--root
  (expand-file-name "docs-fixtures/"
                    (file-name-directory
                     (or load-file-name buffer-file-name)))
  "Absolute path to this test file's `docs-fixtures/' tree.")

(defmacro satan-tools-docs-test--with-fixtures (&rest body)
  "Bind `satan-tools-docs-roots' to the fixture tree for BODY.
Roots are absolute (test fixtures live next to this file, not under
`user-emacs-directory'); the resolver passes absolute strings
through `expand-file-name' unchanged."
  (declare (indent 0))
  `(let ((satan-tools-docs-roots
          (list (expand-file-name "satan/" satan-tools-docs-test--root)
                (expand-file-name "emacs/" satan-tools-docs-test--root))))
     ,@body))

;; ---------- parser ----------

(ert-deftest satan-tools-docs/parse-chunk-happy ()
  (let* ((path (expand-file-name "satan/foo.md"
                                 satan-tools-docs-test--root))
         (chunk (satan-tools-docs--parse-chunk path)))
    (should chunk)
    (should (equal "fix-satan-foo" (plist-get chunk :name)))
    (should (equal "Fixture design chunk about flux capacitors"
                   (plist-get chunk :description)))
    (should (equal "design" (plist-get chunk :type)))
    (should (equal "satan"  (plist-get chunk :topic)))
    (should (equal "canon"  (plist-get chunk :status)))
    (should (equal "bbbbbbb" (plist-get chunk :updated_at)))
    (should (equal "bbbbbbb" (plist-get chunk :verified_at)))
    (should (equal path (plist-get chunk :path)))
    (should (string-match-p "ZIGZAG" (plist-get chunk :body)))))

(ert-deftest satan-tools-docs/parse-chunk-rejects-malformed ()
  (let ((path (expand-file-name "emacs/malformed.md"
                                satan-tools-docs-test--root)))
    (should-not (satan-tools-docs--parse-chunk path))))

(ert-deftest satan-tools-docs/parse-kv-basic ()
  (should (equal '("name" . "foo")
                 (satan-tools-docs--parse-kv "name: foo")))
  (should (equal '("description" . "one two three")
                 (satan-tools-docs--parse-kv
                  "description:   one two three  ")))
  (should-not (satan-tools-docs--parse-kv "no colon here")))

(ert-deftest satan-tools-docs/split-frontmatter-shape ()
  (let* ((text "---\nname: x\n---\nbody here\n")
         (split (satan-tools-docs--split-frontmatter text)))
    (should (equal "name: x\n" (car split)))
    (should (equal "body here\n" (cdr split))))
  (should-not (satan-tools-docs--split-frontmatter "no front\n"))
  (should-not (satan-tools-docs--split-frontmatter "---\nname: x\n")))

;; ---------- walker ----------

(ert-deftest satan-tools-docs/list-chunks-counts ()
  (satan-tools-docs-test--with-fixtures
    (let ((chunks (satan-tools-docs--list-chunks)))
      ;; 3 valid (index, foo, bar); malformed silently dropped.
      (should (= 3 (length chunks)))
      (should (cl-every (lambda (c) (plist-get c :name)) chunks))
      (should (member "fix-satan-index"
                      (mapcar (lambda (c) (plist-get c :name)) chunks))))))

(ert-deftest satan-tools-docs/list-chunks-skips-missing-root ()
  (let ((satan-tools-docs-roots '("/nonexistent/path/x")))
    (should (null (satan-tools-docs--list-chunks)))))

;; ---------- registration ----------

(ert-deftest satan-tools-docs/registers-three-tools ()
  (dolist (name '("docs_list" "docs_search" "docs_read"))
    (let ((spec (satan-tool-lookup name)))
      (should spec)
      (should (eq 'read (plist-get spec :risk))))))

;; ---------- docs_list ----------

(ert-deftest satan-tools-docs/list-handler-returns-entries ()
  (satan-tools-docs-test--with-fixtures
    (let* ((res (satan-tool/docs-list nil nil))
           (payload (cdr res))
           (entries (plist-get payload :entries)))
      (should (eq 'ok (car res)))
      (should (equal "docs_list" (plist-get payload :scope)))
      (should (= 3 (length entries)))
      ;; Entries are skinny — no :body, no :updated_at.
      (let ((first (car entries)))
        (should (plist-get first :name))
        (should (plist-get first :description))
        (should-not (plist-member first :body))
        (should-not (plist-member first :updated_at))))))

;; ---------- docs_search ----------

(ert-deftest satan-tools-docs/search-by-topic ()
  (satan-tools-docs-test--with-fixtures
    (let* ((res (satan-tool/docs-search (list :topic "emacs") nil))
           (entries (plist-get (cdr res) :entries)))
      (should (eq 'ok (car res)))
      (should (= 1 (length entries)))
      (should (equal "fix-emacs-bar" (plist-get (car entries) :name))))))

(ert-deftest satan-tools-docs/search-by-type ()
  (satan-tools-docs-test--with-fixtures
    (let* ((res (satan-tool/docs-search (list :type "design") nil))
           (entries (plist-get (cdr res) :entries)))
      (should (= 1 (length entries)))
      (should (equal "fix-satan-foo" (plist-get (car entries) :name))))))

(ert-deftest satan-tools-docs/search-by-status ()
  (satan-tools-docs-test--with-fixtures
    (let* ((res (satan-tool/docs-search (list :status "living") nil))
           (entries (plist-get (cdr res) :entries)))
      (should (= 1 (length entries)))
      (should (equal "fix-satan-index" (plist-get (car entries) :name))))))

(ert-deftest satan-tools-docs/search-by-query-substring ()
  (satan-tools-docs-test--with-fixtures
    (let* ((res (satan-tool/docs-search (list :query "ZIGZAG") nil))
           (entries (plist-get (cdr res) :entries)))
      (should (= 1 (length entries)))
      (should (equal "fix-satan-foo" (plist-get (car entries) :name))))))

(ert-deftest satan-tools-docs/search-query-case-insensitive ()
  (satan-tools-docs-test--with-fixtures
    (let* ((res (satan-tool/docs-search (list :query "hexagon") nil))
           (entries (plist-get (cdr res) :entries)))
      (should (= 1 (length entries)))
      (should (equal "fix-emacs-bar" (plist-get (car entries) :name))))))

(ert-deftest satan-tools-docs/search-combined-filters-intersect ()
  (satan-tools-docs-test--with-fixtures
    (let* ((res (satan-tool/docs-search
                 (list :topic "satan" :type "reference") nil))
           (entries (plist-get (cdr res) :entries)))
      (should (= 1 (length entries)))
      (should (equal "fix-satan-index" (plist-get (car entries) :name))))))

(ert-deftest satan-tools-docs/search-no-filters-returns-all ()
  (satan-tools-docs-test--with-fixtures
    (let* ((res (satan-tool/docs-search nil nil))
           (entries (plist-get (cdr res) :entries)))
      (should (= 3 (length entries))))))

(ert-deftest satan-tools-docs/search-no-match-returns-empty ()
  (satan-tools-docs-test--with-fixtures
    (let* ((res (satan-tool/docs-search
                 (list :query "DEFINITELY_ABSENT_TOKEN") nil))
           (entries (plist-get (cdr res) :entries)))
      (should (null entries)))))

;; ---------- docs_read ----------

(ert-deftest satan-tools-docs/read-roundtrips-body ()
  (satan-tools-docs-test--with-fixtures
    (let* ((res (satan-tool/docs-read (list :name "fix-satan-foo") nil))
           (payload (cdr res)))
      (should (eq 'ok (car res)))
      (should (equal "fix-satan-foo" (plist-get payload :name)))
      (should (equal "bbbbbbb" (plist-get payload :updated_at)))
      (should (string-match-p "ZIGZAG" (plist-get payload :body))))))

(ert-deftest satan-tools-docs/read-unknown-slug-errors ()
  (satan-tools-docs-test--with-fixtures
    (let ((res (satan-tool/docs-read (list :name "nope") nil)))
      (should (eq 'error (car res)))
      (should (string-match-p "unknown" (cdr res))))))

(ert-deftest satan-tools-docs/read-rejects-empty-name ()
  (let ((res (satan-tool/docs-read (list :name "") nil)))
    (should (eq 'error (car res)))))

(ert-deftest satan-tools-docs/read-rejects-nonstring-name ()
  (let ((res (satan-tool/docs-read (list :name 42) nil)))
    (should (eq 'error (car res)))))

;; ---------- schema validation (registry level) ----------

(ert-deftest satan-tools-docs/schema-read-requires-name ()
  (let* ((spec (satan-tool-lookup "docs_read"))
         (err (satan-tool-validate-args spec nil)))
    (should err)
    (should (string-match-p "name" err))))

(ert-deftest satan-tools-docs/schema-search-all-optional ()
  (let* ((spec (satan-tool-lookup "docs_search"))
         (err (satan-tool-validate-args spec nil)))
    (should-not err)))

(ert-deftest satan-tools-docs/schema-list-takes-no-args ()
  (let* ((spec (satan-tool-lookup "docs_list"))
         (err (satan-tool-validate-args spec nil)))
    (should-not err)))

(provide 'satan-tools-docs-test)
;;; satan-tools-docs-test.el ends here
