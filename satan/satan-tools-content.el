;;; satan-tools-content.el --- content_read tool handler -*- lexical-binding: t; -*-

;; Read-only window into panopticon's content store:
;;   ~/.local/state/behaviour/content/
;;     articles.jsonl            (index of record)
;;     <shard>/<hash>.{md,json}  (md=snippet src, json.text_content=body)
;;
;; Scopes:
;;   - "recent" -> newest-first tail of articles.jsonl, metadata only
;;   - "get"    -> char-offset paginated text_content from sidecar
;;   - "filter" -> articles.jsonl rows matching domain/url, metadata + excerpt
;;   - "search" -> rg over .md projection, deduped + recency-sorted matches
;;
;; Risk = `read'; no capability required.  Panopticon is the producer
;; that handles redaction; SATAN is a downstream consumer.

(require 'cl-lib)
(require 'subr-x)
(require 'satan-tools)
(require 'satan-jsonl)

;; --- Defcustoms -----------------------------------------------

(defcustom satan-tools-content-dir
  (let ((xdg (getenv "XDG_STATE_HOME")))
    (expand-file-name
     "behaviour/content/"
     (if xdg (expand-file-name xdg) "~/.local/state/")))
  "Root directory holding panopticon's content store."
  :type 'directory :group 'satan)

(defcustom satan-tools-content-default-limit 20
  "Default `:limit' for `recent' and `filter' scopes."
  :type 'integer :group 'satan)

(defcustom satan-tools-content-search-limit 10
  "Default `:limit' for `search' scope."
  :type 'integer :group 'satan)

(defcustom satan-tools-content-page-max 5000
  "Maximum characters per `get' page."
  :type 'integer :group 'satan)

(defcustom satan-tools-content-recent-scan-max 500
  "Maximum rows to parse from the tail of `articles.jsonl'.
Bounds I/O for the unbounded index (see DE-005 R6 / DR-005 DEC-6)."
  :type 'integer :group 'satan)

(defcustom satan-tools-content-rg-path nil
  "Path to `rg' binary for search scope.  nil means `executable-find'."
  :type '(choice (const :tag "Auto-detect" nil)
                 (file :tag "Custom path"))
  :group 'satan)

(defconst satan-tools-content--limit-hard-max 200
  "Hard cap on :limit for metadata scopes (recent/filter).")

(defconst satan-tools-content--search-limit-hard-max 50
  "Hard cap on :limit for search scope.")

(defconst satan-tools-content--search-snippet-max 200
  "Maximum characters for a search match snippet.")

;; --- Internal helpers -----------------------------------------

(defun satan-tools-content--articles-path ()
  "Return the full path to `articles.jsonl'."
  (expand-file-name "articles.jsonl" satan-tools-content-dir))

(defun satan-tools-content--sidecar-json-path (hash)
  "Return the path to `<shard>/<hash>.json' for HASH."
  (expand-file-name
   (format "%s/%s.json" (substring hash 0 2) hash)
   satan-tools-content-dir))

(defun satan-tools-content--clamp-limit (raw default hard-max)
  "Clamp RAW integer to [1, HARD-MAX], defaulting to DEFAULT if nil."
  (cond
   ((null raw) default)
   ((< raw 1) 1)
   ((> raw hard-max) hard-max)
   (t raw)))

(defun satan-tools-content--read-json (path)
  "Parse JSON at PATH into a plist, or return nil if unreadable/empty."
  (when (and (file-readable-p path)
             (> (file-attribute-size (file-attributes path)) 0))
    (with-temp-buffer
      (let ((coding-system-for-read 'utf-8))
        (insert-file-contents path))
      (json-parse-string (buffer-string)
                         :object-type 'plist
                         :array-type 'list
                         :null-object nil
                         :false-object :false))))

(cl-defun satan-tools-content--read-articles-jsonl (&key skip-malformed)
  "Read `articles.jsonl' into a list of plists, in file (oldest-first) order.
nil if unreadable.  Callers that want newest-first (e.g. `recent') reverse
the tail themselves.  Uses a lenient parser that drops malformed lines
(see DE-005 R6 / O-1) — the skip-malformed flag is accepted for
symmetry but currently always uses lenient mode."
  (let ((path (satan-tools-content--articles-path)))
    (when (file-readable-p path)
      (satan-tools-content--read-jsonl-lenient path))))

(defun satan-tools-content--read-jsonl-lenient (path)
  "Read JSONL at PATH, dropping malformed lines.  Returns list of plists."
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8))
      (insert-file-contents path))
    (let (acc)
      (goto-char (point-min))
      (while (not (eobp))
        (let ((line (buffer-substring-no-properties
                     (point) (line-end-position))))
          (unless (string-empty-p (string-trim line))
            (condition-case nil
                (push (json-parse-string line
                                         :object-type 'plist
                                         :array-type 'list
                                         :null-object nil
                                         :false-object :false)
                      acc)
              (error nil))))
        (forward-line 1))
      (nreverse acc))))

(defun satan-tools-content--lookup-article (hash articles)
  "Find the plist in ARTICLES whose :content_hash equals HASH."
  (cl-find hash articles
           :key (lambda (a) (plist-get a :content_hash))
           :test #'string=))

(defun satan-tools-content--excerpt (sidecar)
  "Return :excerpt from SIDECAR plist, or nil."
  (plist-get sidecar :excerpt))

;; --- recent ---------------------------------------------------

(defun satan-tools-content--scope-recent (args)
  "Handle `recent' scope.  ARGS: (:limit INT?)."
  (let* ((limit (satan-tools-content--clamp-limit
                 (plist-get args :limit)
                 satan-tools-content-default-limit
                 satan-tools-content--limit-hard-max))
         (all (satan-tools-content--read-articles-jsonl :skip-malformed t))
         (scanned (or all '()))
         (tail (last scanned (min limit (length scanned)
                                  satan-tools-content-recent-scan-max)))
         (reversed (nreverse tail)))
    (cons 'ok (list :scope "recent"
                    :limit limit
                    :captures reversed))))

;; --- get ------------------------------------------------------

(defun satan-tools-content--scope-get (args)
  "Handle `get' scope.  ARGS: (:hash STRING :offset INT? :limit INT?).
Returns paginated text_content per DR-005 DEC-4."
  (let* ((hash (plist-get args :hash))
         (raw-offset (or (plist-get args :offset) 0))
         (offset (max 0 raw-offset))            ; F-5: clamp negative
         (raw-limit (plist-get args :limit))
         (limit (satan-tools-content--clamp-limit
                 raw-limit satan-tools-content-page-max
                 satan-tools-content-page-max))
         (articles (satan-tools-content--read-articles-jsonl)))
    ;; Resolve hash -> article metadata
    (cond
     ((null articles)
      (cons 'error "content index unreadable"))
     ((null (satan-tools-content--lookup-article hash articles))
      (cons 'error (format "unknown content_hash: %s" hash)))
     (t
      (let* ((article (satan-tools-content--lookup-article hash articles))
             (sidecar-path (satan-tools-content--sidecar-json-path hash))
             (sidecar (satan-tools-content--read-json sidecar-path)))
        (if (null sidecar)
            (cons 'error (format "content body missing for hash: %s" hash))
          (let* ((text (or (plist-get sidecar :text_content) ""))
                 (total (length text))
                 (start (min offset total))
                 (end (min (+ start limit) total))
                 (page (substring text start end))
                 (returned (length page))
                 (next (if (< end total) (+ offset returned) :null)))
            (cons 'ok (list :scope "get"
                            :hash hash
                            :url (plist-get article :url)
                            :domain (plist-get article :domain)
                            :title (plist-get article :title)
                            :captured_at (plist-get article :captured_at)
                            :total_chars total
                            :offset offset
                            :returned returned
                            :next_offset next
                            :text page)))))))))

;; --- filter ---------------------------------------------------

(defun satan-tools-content--scope-filter (args)
  "Handle `filter' scope.  ARGS: (:domain STRING? :url STRING?).
At least one of :domain / :url is required (DR-005 §4.1)."
  (let* ((domain (plist-get args :domain))
         (url    (plist-get args :url))
         (limit  (satan-tools-content--clamp-limit
                  (plist-get args :limit)
                  satan-tools-content-default-limit
                  satan-tools-content--limit-hard-max))
         (all (satan-tools-content--read-articles-jsonl :skip-malformed t))
         (articles (or all '()))
         matched)
    (if (and (null domain) (null url))
        (cons 'error "filter requires at least one of: domain, url")
    (dolist (a articles)
      (when (and (or (null domain)
                     (string= domain (plist-get a :domain)))
                 (or (null url)
                     (string-match-p (regexp-quote url)
                                     (or (plist-get a :url) ""))))
        (let* ((hash (plist-get a :content_hash))
               (sidecar (satan-tools-content--read-json
                         (satan-tools-content--sidecar-json-path hash)))
               (excerpt (when sidecar
                          (satan-tools-content--excerpt sidecar))))
          (push (append (list :hash hash
                              :url (plist-get a :url)
                              :domain (plist-get a :domain)
                              :title (plist-get a :title)
                              :captured_at (plist-get a :captured_at)
                              :quality_score (plist-get a :quality_score))
                        (when excerpt (list :excerpt excerpt)))
                matched))))
    (let ((result (nreverse matched)))
      (cons 'ok (list :scope "filter"
                      :domain domain
                      :url url
                      :limit limit
                      :captures (cl-subseq result 0 (min limit (length result)))))))))

;; --- search ---------------------------------------------------

(defun satan-tools-content--resolve-rg ()
  "Return the `rg' binary path, or nil."
  (or satan-tools-content-rg-path
      (executable-find "rg")))

(defun satan-tools-content--scope-search (args)
  "Handle `search' scope.  ARGS: (:query STRING :limit INT?).
Uses `rg' subprocess via `call-process' (never shell-command)."
  (let* ((query (plist-get args :query))
         (limit (satan-tools-content--clamp-limit
                 (plist-get args :limit)
                 satan-tools-content-search-limit
                 satan-tools-content--search-limit-hard-max))
         (rg (satan-tools-content--resolve-rg))
         (root satan-tools-content-dir)
         (articles (satan-tools-content--read-articles-jsonl :skip-malformed t))
         (index (or articles '())))
    (if (null rg)
        ;; No rg binary → soft-fail empty
        (cons 'ok (list :scope "search"
                        :query query
                        :limit limit
                        :matches '()
                        :truncated_results :false))
      (let* ((raw-output
              (condition-case nil
                  (with-temp-buffer
                    (setq default-directory root)
                    (call-process rg nil t nil
                                  "--json" "--fixed-strings" "-i"
                                  query "-g" "*.md")
                    (buffer-string))
                (error "")))
             (lines (split-string raw-output "\n" t))
             (snippet-map (make-hash-table :test 'equal))
             (seen-map (make-hash-table :test 'equal))
             hashes-in-file-order)
        ;; Single pass: collect first snippet + first-seen order per hash
        (dolist (line lines)
          (condition-case nil
              (let* ((parsed (json-parse-string line
                                                :object-type 'plist
                                                :array-type 'list))
                     (type (plist-get parsed :type))
                     (data (plist-get parsed :data))
                     (path (plist-get data :path)))
                (when (string= type "match")
                  ;; rg --json wraps path in {:text "..."}
                  (let* ((path-str (plist-get (plist-get data :path) :text))
                         (hash (when path-str (file-name-base path-str))))
                    (when hash
                      (unless (gethash hash seen-map)
                        (puthash hash t seen-map)
                        (push hash hashes-in-file-order)
                        (puthash hash
                                 (plist-get (plist-get data :lines) :text)
                                 snippet-map))))))
            (error nil)))
        (setq hashes-in-file-order (nreverse hashes-in-file-order))
        (let ((article-map (make-hash-table :test 'equal)))
          (dolist (a index)
            (let ((h (plist-get a :content_hash)))
              (when (gethash h snippet-map)
                (puthash h a article-map))))
          (let* ((deduped
                  (sort (cl-remove-if-not
                         (lambda (h) (gethash h article-map))
                         hashes-in-file-order)
                        (lambda (a b)
                          (let ((ta (plist-get (gethash a article-map) :captured_at))
                                (tb (plist-get (gethash b article-map) :captured_at)))
                            (string< tb ta)))))
                 (truncated (> (length deduped) limit))
                 (result-hashes (cl-subseq deduped 0 (min limit (length deduped))))
                 (matches
                  (mapcar
                   (lambda (h)
                     (let* ((a (gethash h article-map))
                            (raw-snippet (gethash h snippet-map ""))
                            (snippet
                             (if (> (length raw-snippet)
                                    satan-tools-content--search-snippet-max)
                                 (concat (substring raw-snippet 0
                                                    satan-tools-content--search-snippet-max)
                                         "…")
                               raw-snippet)))
                       (list :hash h
                             :url (plist-get a :url)
                             :domain (plist-get a :domain)
                             :title (plist-get a :title)
                             :snippet snippet)))
                   result-hashes)))
            (cons 'ok (list :scope "search"
                            :query query
                            :limit limit
                            :matches matches
                            :truncated_results (if truncated t :false)))))))))

;; --- Tool handler ---------------------------------------------

(defun satan-tool/content-read (args _ctx)
  "Implements `content_read'.  ARGS: (:scope recent|get|filter|search …).
Returns (ok PLIST) | (error STRING)."
  (let ((scope (plist-get args :scope)))
    (pcase scope
      ("recent"  (satan-tools-content--scope-recent args))
      ("get"     (satan-tools-content--scope-get args))
      ("filter"  (satan-tools-content--scope-filter args))
      ("search"  (satan-tools-content--scope-search args))
      (_ (cons 'error (format "unknown scope: %s" scope))))))

(satan-tool-register
 (list :name "content_read"
       :risk 'read
       :args-schema '(scope (:type string :required t
                             :enum ("recent" "get" "filter" "search"))
                      hash (:type string :required nil)
                      query (:type string :required nil)
                      domain (:type string :required nil)
                      url (:type string :required nil)
                      limit (:type integer :required nil)
                      offset (:type integer :required nil))
       :handler 'satan-tool/content-read))

(provide 'satan-tools-content)
;;; satan-tools-content.el ends here
