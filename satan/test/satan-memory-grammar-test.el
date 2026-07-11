;;; satan-memory-grammar-test.el --- grammar drift detector -*- lexical-binding: t; -*-

;; Two test classes:
;; - Pure: elisp-side internal consistency (closed-world namespaces
;;   match the values table, accessors return expected things).
;; - Sync: the elisp constants for grammar v1 equal the rows in
;;   `satan_memory.grammar_versions/handle_aliases/handle_weights'.
;;
;; Run from CLI:
;;   emacs --batch \
;;     -L ~/.emacs.d/core -L ~/.emacs.d/satan -L ~/.emacs.d/satan/test \
;;     -l satan-memory-grammar-test.el -f ert-run-tests-batch-and-exit
;;
;; Override target DB with env var SATAN_MEMORY_TEST_DB (default
;; `satan_memory').  Sync tests skip when the DB is unreachable.

(require 'ert)
(require 'cl-lib)
(require 'satan-db)
(require 'satan-memory-grammar)

(defconst satan-memory-grammar-test--db
  (or (getenv "SATAN_MEMORY_TEST_DB") "satan_memory"))

(defconst satan-memory-grammar-test--host "/run/postgresql"
  "Production host default.  Overridden at call time by `satan-db-resolve-host';
the actual connection target is the resolved host, not this literal.")

(defun satan-memory-grammar-test--psql (sql)
  "Run SQL against the configured DB.  Return rows as list-of-strings.
Each line is split on `|'.  Returns nil on connection failure."
  (with-temp-buffer
    (let* ((args (list "-h" (satan-db-resolve-host satan-memory-grammar-test--host)
                       "-d" satan-memory-grammar-test--db
                       "--no-psqlrc" "-A" "-t" "-F" "|"
                       "-v" "ON_ERROR_STOP=1"
                       "-c" sql))
           (status (apply #'call-process "psql" nil t nil args)))
      (when (and (integerp status) (zerop status))
        (cl-remove-if-not
         #'identity
         (mapcar (lambda (line)
                   (and (not (string-empty-p line))
                        (split-string line "|")))
                 (split-string (buffer-string) "\n")))))))

(defun satan-memory-grammar-test--db-reachable-p ()
  (satan-db-test-db-available-p satan-memory-grammar-test--db))

;; ---------- pure internal consistency ----------

(ert-deftest satan-memory-grammar/closed-values-match-namespaces ()
  "Every namespace in `-closed-values' is declared closed in `-namespaces',
and every namespace declared closed has a values entry."
  (let ((closed-ns
         (mapcar #'car
                 (cl-remove-if-not
                  (lambda (e) (eq (cdr e) 'closed))
                  satan-memory-grammar-namespaces)))
        (values-ns
         (mapcar #'car satan-memory-grammar-closed-values)))
    (should (equal (sort (copy-sequence closed-ns) #'string<)
                   (sort (copy-sequence values-ns) #'string<)))))

(ert-deftest satan-memory-grammar/accessors-return-known ()
  (should (eq 'closed (satan-memory-grammar-namespace-world 'surface)))
  (should (eq 'open   (satan-memory-grammar-namespace-world 'topic)))
  (should (null      (satan-memory-grammar-namespace-world 'no_such)))
  (should (member "browser" (satan-memory-grammar-closed-values 'surface)))
  (should (null (satan-memory-grammar-closed-values 'topic)))
  (should (equal "domain_kind:docs"
                 (satan-memory-grammar-alias-target "reference")))
  (should (= 2 (satan-memory-grammar-default-weight 'event)))
  (should (= 0 (satan-memory-grammar-default-weight 'bough_node))))

(ert-deftest satan-memory-grammar/valid-value-p ()
  (should (satan-memory-grammar-valid-value-p 'surface "browser"))
  (should-not (satan-memory-grammar-valid-value-p 'surface "Browser"))
  (should-not (satan-memory-grammar-valid-value-p 'surface "Vespa"))
  (should (satan-memory-grammar-valid-value-p 'topic "anything-goes"))
  (should-not (satan-memory-grammar-valid-value-p 'topic ""))
  (should-not (satan-memory-grammar-valid-value-p 'no_such "x")))

;; ---------- DB sync ----------

(ert-deftest satan-memory-grammar/db-sync-current-version ()
  ;; Elisp's `current-version' must exist as a row in `grammar_versions'.
  ;; DB is permitted to be AHEAD of elisp — fixture migrations
  ;; (e.g. 0004 v2) introduce later versions whose elisp counterparts
  ;; are cl-letf'd inside tests, not committed as live constants.
  ;; The sister tests `db-sync-aliases' and `db-sync-default-weights'
  ;; pin the table contents at `current-version', so real drift is
  ;; still caught.
  (skip-unless (satan-memory-grammar-test--db-reachable-p))
  (let* ((rows (satan-memory-grammar-test--psql
                (format "SELECT 1 FROM grammar_versions WHERE version = %d"
                        satan-memory-grammar-current-version)))
         (max-rows (satan-memory-grammar-test--psql
                    "SELECT MAX(version) FROM grammar_versions"))
         (db-max (and max-rows (string-to-number (caar max-rows)))))
    (should rows)
    (should (>= db-max satan-memory-grammar-current-version))))

(ert-deftest satan-memory-grammar/db-sync-aliases ()
  (skip-unless (satan-memory-grammar-test--db-reachable-p))
  (let* ((rows (satan-memory-grammar-test--psql
                (format
                 "SELECT alias, canonical_handle FROM handle_aliases WHERE grammar_version = %d ORDER BY alias"
                 satan-memory-grammar-current-version)))
         (db-pairs (mapcar (lambda (r) (cons (nth 0 r) (nth 1 r))) rows))
         (el-pairs (sort (copy-sequence satan-memory-grammar-aliases)
                         (lambda (a b) (string< (car a) (car b))))))
    (should (equal el-pairs db-pairs))))

(ert-deftest satan-memory-grammar/db-sync-default-weights ()
  (skip-unless (satan-memory-grammar-test--db-reachable-p))
  (let* ((rows (satan-memory-grammar-test--psql
                (format
                 "SELECT namespace, weight::text FROM handle_weights WHERE grammar_version = %d AND value = '__default__' ORDER BY namespace"
                 satan-memory-grammar-current-version)))
         (db-pairs (mapcar (lambda (r)
                             (cons (intern (nth 0 r))
                                   (string-to-number (nth 1 r))))
                           rows))
         (el-pairs (sort (copy-sequence
                          satan-memory-grammar-default-weights)
                         (lambda (a b)
                           (string< (symbol-name (car a))
                                    (symbol-name (car b)))))))
    (should (equal el-pairs db-pairs))))

(provide 'satan-memory-grammar-test)
;;; satan-memory-grammar-test.el ends here
