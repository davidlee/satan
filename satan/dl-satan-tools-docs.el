;;; dl-satan-tools-docs.el --- docs_* lazy doc lookup tools -*- lexical-binding: t; -*-

;; Three read-only tools over the chunked, frontmatter-stamped markdown
;; corpus under `docs/satan/' and `docs/emacs/' (post-reshape 03398479):
;;
;;   docs_list                                  -> [slug entries]
;;   docs_search :query? :topic? :type? :status? -> [slug entries]
;;   docs_read   :name                          -> full body for slug
;;
;; Each chunk carries a fixed YAML frontmatter block:
;;
;;   ---
;;   name: <unique-slug>
;;   description: <one-line>
;;   metadata:
;;     type:        design|plan|handover|governance|reference|tracking
;;     topic:       satan|satan-memory|satan-patch|satan-at|emacs
;;     status:      canon|draft|archive|living
;;     updated_at:  <7-char SHA>
;;     verified_at: <7-char SHA>
;;   ---
;;
;; Lazy-load model: tiny INDEX in canon, chunks pulled on demand via
;; these tools.  No eager corpus ingest.
;;
;; Mind/mechanism split (see docs/satan/governance.md §Ownership): tool
;; descriptions live under `~/notes/satan/tools/docs_*.md', not here.

(require 'cl-lib)
(require 'subr-x)
(require 'dl-satan-tools)

(defcustom dl-satan-tools-docs-roots
  '("docs/satan" "docs/emacs")
  "List of doc-corpus roots, relative to `user-emacs-directory'.
Each entry is walked recursively for `*.md' chunks carrying the
standard frontmatter shape."
  :type '(repeat directory) :group 'dl-satan)

(defconst dl-satan-tools-docs--metadata-keys
  '(:type :topic :status :updated_at :verified_at)
  "Keys expected under the `metadata:' sub-block in frontmatter.")

;; ---------- frontmatter parser ----------

(defun dl-satan-tools-docs--read-file (path)
  "Return the contents of PATH as a string, utf-8."
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8))
      (insert-file-contents path))
    (buffer-string)))

(defun dl-satan-tools-docs--split-frontmatter (text)
  "Split TEXT into (FRONTMATTER-STRING . BODY-STRING).
Returns nil if TEXT does not open with a `---\\n' delimiter and a
matching `---\\n' terminator.  The frontmatter substring excludes
both delimiters; the body substring excludes the trailing delimiter
and the newline immediately after it."
  (when (string-prefix-p "---\n" text)
    (let* ((rest (substring text 4))
           ;; locate the next "---" at column 0
           (end (string-match "^---\n" rest)))
      (when end
        (let ((fm   (substring rest 0 end))
              (body (substring rest (+ end 4))))
          (cons fm body))))))

(defun dl-satan-tools-docs--parse-frontmatter (fm)
  "Parse FM (raw frontmatter string) into a plist.
Top-level keys (`name', `description') appear at column 0; keys
nested under `metadata:' are two-space indented.  Returns
`(:name S :description S :type S :topic S :status S
   :updated_at S :verified_at S)' — keys absent in FM are simply
missing from the plist."
  (let ((out nil)
        (in-meta nil))
    (dolist (line (split-string fm "\n"))
      (cond
       ((string-empty-p (string-trim line))
        ;; blank line — ignore
        nil)
       ((string-prefix-p "metadata:" line)
        (setq in-meta t))
       ((and in-meta (string-prefix-p "  " line))
        (let ((kv (dl-satan-tools-docs--parse-kv (substring line 2))))
          (when kv
            (let ((key (intern (concat ":" (car kv)))))
              (when (memq key dl-satan-tools-docs--metadata-keys)
                (setq out (plist-put out key (cdr kv))))))))
       ((not (string-prefix-p " " line))
        (setq in-meta nil)
        (let ((kv (dl-satan-tools-docs--parse-kv line)))
          (when kv
            (let ((key (car kv)))
              (when (member key '("name" "description"))
                (setq out (plist-put out
                                     (intern (concat ":" key))
                                     (cdr kv))))))))))
    out))

(defun dl-satan-tools-docs--parse-kv (line)
  "Parse `KEY: VALUE' LINE.  Returns (KEY . VALUE) strings or nil."
  (when (string-match "\\`\\([A-Za-z_][A-Za-z0-9_]*\\):[ \t]*\\(.*\\)\\'"
                      line)
    (cons (match-string 1 line)
          (string-trim (match-string 2 line)))))

(defun dl-satan-tools-docs--parse-chunk (path)
  "Read PATH and return a chunk plist, or nil if frontmatter missing/invalid.
Plist keys: :name :description :type :topic :status :updated_at
:verified_at :path :body.  PATH is preserved verbatim (caller
decides whether to abbreviate)."
  (let* ((text (dl-satan-tools-docs--read-file path))
         (split (dl-satan-tools-docs--split-frontmatter text)))
    (when split
      (let* ((fm (dl-satan-tools-docs--parse-frontmatter (car split)))
             (body (cdr split)))
        (when (plist-get fm :name)
          (append fm
                  (list :path path
                        :body body)))))))

;; ---------- corpus walker ----------

(defun dl-satan-tools-docs--resolve-roots (&optional roots)
  "Resolve ROOTS (default `dl-satan-tools-docs-roots') to absolute paths
under `user-emacs-directory'.  Drops entries that don't exist."
  (cl-loop for r in (or roots dl-satan-tools-docs-roots)
           for abs = (expand-file-name r user-emacs-directory)
           when (file-directory-p abs)
           collect abs))

(defun dl-satan-tools-docs--list-chunks (&optional roots)
  "Walk ROOTS recursively, return a list of chunk plists.
Each plist carries the full body too; callers that don't need the
body can strip it (cf. `dl-satan-tools-docs--entry-of').  Malformed
chunks (no frontmatter, no :name) are silently skipped."
  (cl-loop for root in (dl-satan-tools-docs--resolve-roots roots)
           nconc
           (cl-loop for path in (directory-files-recursively root "\\.md\\'")
                    for chunk = (dl-satan-tools-docs--parse-chunk path)
                    when chunk collect chunk)))

(defun dl-satan-tools-docs--entry-of (chunk)
  "Project CHUNK plist to the skinny entry shape (no body).
Used by `docs_list' / `docs_search' result lists."
  (list :name        (plist-get chunk :name)
        :description (plist-get chunk :description)
        :path        (plist-get chunk :path)
        :type        (plist-get chunk :type)
        :topic       (plist-get chunk :topic)
        :status      (plist-get chunk :status)))

;; ---------- docs_list ----------

(defun dl-satan-tool/docs-list (_args _ctx)
  "Handler for `docs_list'.  Returns all chunks as skinny entries."
  (cons 'ok
        (list :scope "docs_list"
              :entries (mapcar #'dl-satan-tools-docs--entry-of
                               (dl-satan-tools-docs--list-chunks)))))

;; ---------- docs_search ----------

(defun dl-satan-tools-docs--matches-p (chunk query topic type status)
  "Return non-nil if CHUNK satisfies all non-nil filters.
QUERY is a case-insensitive literal substring matched against the
body; TOPIC / TYPE / STATUS are exact-match against frontmatter."
  (and (or (null topic)  (equal topic  (plist-get chunk :topic)))
       (or (null type)   (equal type   (plist-get chunk :type)))
       (or (null status) (equal status (plist-get chunk :status)))
       (or (null query)
           (let ((case-fold-search t))
             (string-match-p (regexp-quote query)
                             (or (plist-get chunk :body) ""))))))

(defun dl-satan-tool/docs-search (args _ctx)
  "Handler for `docs_search'.  Filters by frontmatter + body substring.
With no filters set, returns all chunks (== `docs_list')."
  (let ((query  (plist-get args :query))
        (topic  (plist-get args :topic))
        (type   (plist-get args :type))
        (status (plist-get args :status)))
    (cons 'ok
          (list :scope "docs_search"
                :query  query
                :topic  topic
                :type   type
                :status status
                :entries
                (cl-loop for chunk in (dl-satan-tools-docs--list-chunks)
                         when (dl-satan-tools-docs--matches-p
                               chunk query topic type status)
                         collect (dl-satan-tools-docs--entry-of chunk))))))

;; ---------- docs_read ----------

(defun dl-satan-tool/docs-read (args _ctx)
  "Handler for `docs_read'.  Round-trip a chunk by slug."
  (let ((name (plist-get args :name)))
    (cond
     ((not (stringp name))  (cons 'error "name must be string"))
     ((string-empty-p name) (cons 'error "name must be non-empty"))
     (t
      (let ((chunk (cl-find-if
                    (lambda (c) (equal name (plist-get c :name)))
                    (dl-satan-tools-docs--list-chunks))))
        (if (null chunk)
            (cons 'error (format "unknown doc slug: %s" name))
          (cons 'ok
                (list :scope       "docs_read"
                      :name        (plist-get chunk :name)
                      :description (plist-get chunk :description)
                      :path        (plist-get chunk :path)
                      :type        (plist-get chunk :type)
                      :topic       (plist-get chunk :topic)
                      :status      (plist-get chunk :status)
                      :updated_at  (plist-get chunk :updated_at)
                      :verified_at (plist-get chunk :verified_at)
                      :body        (plist-get chunk :body)))))))))

;; ---------- registration ----------

(dl-satan-tool-register
 (list :name "docs_list"
       :risk 'read
       :args-schema nil
       :handler 'dl-satan-tool/docs-list))

(dl-satan-tool-register
 (list :name "docs_search"
       :risk 'read
       :args-schema
       (list 'query  (list :type 'string :required nil)
             'topic  (list :type 'string :required nil)
             'type   (list :type 'string :required nil)
             'status (list :type 'string :required nil))
       :handler 'dl-satan-tool/docs-search))

(dl-satan-tool-register
 (list :name "docs_read"
       :risk 'read
       :args-schema (list 'name (list :type 'string :required t))
       :handler 'dl-satan-tool/docs-read))

(provide 'dl-satan-tools-docs)
;;; dl-satan-tools-docs.el ends here
