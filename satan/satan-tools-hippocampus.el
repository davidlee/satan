;;; satan-tools-hippocampus.el --- hippocampus tools -*- lexical-binding: t; -*-

;; The hippocampus is SATAN's self-curated memory.  Entries are denote-named
;; org files written into `~/notes/satan/hippocampus/'.  SATAN owns the
;; directory: write is auto-applied, no candidate / confirmed ceremony.
;; Risk `low' — the user can grep, edit, or delete files directly.
;;
;; Tools: hippocampus_list, hippocampus_read, hippocampus_write,
;;         hippocampus_overwrite, hippocampus_delete, hippocampus_grep,
;;         hippocampus_rename.

(require 'cl-lib)
(require 'subr-x)
(require 'satan-custom)
(require 'satan-tools)
(require 'satan-memory-grammar)
(require 'satan-memory-canon)
(require 'satan-memory-evidence)
(require 'satan-memory-store)
(require 'satan-attribute)

(defcustom satan-hippocampus-dir
  (expand-file-name "satan/hippocampus" satan-notes-root)
  "Directory holding SATAN hippocampus entries."
  :type 'directory :group 'satan)

(defun satan-tools-hippocampus--slugify (s)
  (or (satan-memory-canon--slugify s) "untitled"))

(defun satan-tools-hippocampus--mode-str (raw)
  (cond ((null raw) nil)
        ((symbolp raw) (symbol-name raw))
        ((stringp raw) raw)
        (t (format "%s" raw))))

(defun satan-tools-hippocampus--cross-ref (title path tool-ctx)
  "Mark an `auto_rule' observation trace cross-referencing the
hippocampus PATH (§10.7 of memory.design.md).  Soft failure: any
substrate error is logged and does not affect the caller."
  (condition-case err
      (let* ((mode-str (satan-tools-hippocampus--mode-str
                        (plist-get tool-ctx :mode-name)))
             (canon-ctx
              (list :current_grammar_version
                    satan-memory-grammar-current-version
                    :mode_name mode-str
                    :time_now (or (plist-get tool-ctx :time-now)
                                  (format-time-string "%Y-%m-%dT%T%:z"))
                    :run_id (plist-get tool-ctx :id)
                    :run_started_at (plist-get tool-ctx :run-started-at)))
             (slug (satan-tools-hippocampus--slugify title))
             (raw-hints (list :topic (list slug)))
             (evidence (satan-memory-evidence-assemble
                        canon-ctx
                        (list :run_started_at
                              (plist-get canon-ctx :run_started_at))))
             (canon (satan-memory-canon-canonicalize-from-raw
                     evidence raw-hints canon-ctx))
             (handles (plist-get canon :handles))
             (sources (plist-get canon :handle_sources))
             (normalized (plist-get canon :normalized))
             (gv (plist-get canon-ctx :current_grammar_version))
             (handle-rows
              (mapcar (lambda (h)
                        (list :handle h
                              :source (cdr (assoc h sources))
                              :grammar_version gv))
                      handles))
             (metadata
              (list :evidence evidence
                    :hints raw-hints
                    :normalized_hints (or normalized '())
                    :ctx canon-ctx
                    :hippocampus_path (abbreviate-file-name path)
                    :truncated_at (plist-get evidence :truncated_at)))
             (result
              (satan-memory-store-mark
               :kind "observation"
               :trace-origin "auto_rule"
               :source (format "hippocampus_write@%s"
                               (or mode-str "unknown"))
               :observed-start-at (plist-get evidence :window_start_at)
               :observed-end-at   (plist-get evidence :window_end_at)
               :payload (format "hippocampus entry: %s" title)
               :grammar-version gv
               :metadata-json metadata
               :handles handle-rows)))
        (pcase result
          (`(ok . ,tid) tid)
          (`(error . ,msg)
           (message "hippocampus cross-ref skipped: %s" msg)
           nil)))
    (error
     (message "hippocampus cross-ref error: %s"
              (error-message-string err))
     nil)))

(defun satan-tools-hippocampus--emit-attribute-signal
    (reason tool-name filename ctx)
  "Emit a hippocampus attribute signal (design-contract §6H).
Soft-fail: log on error, do not affect tool return value."
  (condition-case err
      (when satan-attribute-updates-enabled
        (let* ((run-id (plist-get ctx :id))
               (ts (or (plist-get ctx :time-now)
                       (format-time-string "%Y-%m-%dT%T%:z")))
               (payload (satan-attribute-build-hippocampus-payload
                         :run-id run-id
                         :ts ts
                         :reason reason
                         :tool-name tool-name
                         :filename filename)))
          (satan-attribute-enqueue payload)))
    (error
     (message "hippocampus attribute signal error: %s"
              (error-message-string err))
     nil)))

;; ---------- hippocampus_list ----------

(defun satan-tools-hippocampus--parse-title (filename)
  "Extract title from denote-style FILENAME, or return FILENAME."
  (if (string-match "^[0-9T]+--\\([^_]+\\)" filename)
      (replace-regexp-in-string "-" " " (match-string 1 filename))
    filename))

(defun satan-tools-hippocampus--entry (path)
  "Build an entry plist for PATH (absolute)."
  (let* ((filename (file-name-nondirectory path))
         (mtime (file-attribute-modification-time (file-attributes path))))
    (list :filename filename
          :title (satan-tools-hippocampus--parse-title filename)
          :mtime (format-time-string "%Y-%m-%dT%H:%M:%S%z" mtime))))

(defun satan-tool/hippocampus-list (_args _ctx)
  "List all hippocampus entries.  Returns (ok :entries [...])."
  (if (not (file-directory-p satan-hippocampus-dir))
      (cons 'ok (list :entries nil :count 0))
    (let* ((files (directory-files satan-hippocampus-dir t "\\.org\\'"))
           (entries (mapcar #'satan-tools-hippocampus--entry files))
           (sorted (sort entries
                         (lambda (a b)
                           (string> (plist-get a :mtime)
                                    (plist-get b :mtime))))))
      (cons 'ok (list :entries sorted
                       :count (length sorted))))))

;; ---------- hippocampus_read ----------

(defun satan-tools-hippocampus--safe-path-p (filename)
  "Return non-nil if FILENAME is a plain basename (no traversal)."
  (and (stringp filename)
       (not (string-empty-p filename))
       (not (string-match-p "/" filename))
       (not (string-match-p "\\.\\." filename))))

(defun satan-tool/hippocampus-read (args _ctx)
  "Read a hippocampus entry by filename.  Returns (ok :filename :body)."
  (let ((filename (plist-get args :filename)))
    (cond
     ((not (satan-tools-hippocampus--safe-path-p filename))
      (cons 'error "filename must be a plain basename, no path separators"))
     (t
      (let ((path (expand-file-name filename satan-hippocampus-dir)))
        (if (not (file-readable-p path))
            (cons 'error (format "not found: %s" filename))
          (cons 'ok
                (list :filename filename
                      :body (with-temp-buffer
                              (let ((coding-system-for-read 'utf-8))
                                (insert-file-contents path))
                              (buffer-string))))))))))

;; ---------- hippocampus_write ----------

(defun satan-tool/hippocampus-write (args ctx)
  "Implements hippocampus_write.
ARGS: (:title STR :body STR).  The `hippocampus-write' capability is
enforced by the dispatcher (spec `:capability').  Returns
(ok :path P) | (error MSG).
When `memory-write' is also present, emits an `auto_rule' observation
trace cross-referencing PATH (§10.7); cross-ref errors are soft."
  (let* ((title (plist-get args :title))
         (body  (plist-get args :body))
         (run-id    (plist-get ctx :id))
         (mode-str  (plist-get ctx :mode-name))
         (caps      (plist-get ctx :capabilities)))
    (cond
     ((not (and (stringp title) (stringp body)))
      (cons 'error "title and body must be strings"))
     (t
      (unless (file-directory-p satan-hippocampus-dir)
        (make-directory satan-hippocampus-dir t))
      (let* ((id (format-time-string "%Y%m%dT%H%M%S" nil))
             (slug (satan-tools-hippocampus--slugify title))
             (filename (format "%s--%s__satan_hippocampus.org" id slug))
             (path (expand-file-name filename
                                     satan-hippocampus-dir))
             (coding-system-for-write 'utf-8))
        (with-temp-file path
          (insert "#+title:      " title "\n")
          (insert "#+date:       "
                  (format-time-string "[%Y-%m-%d %a %H:%M]" nil) "\n")
          (insert "#+filetags:   :satan:hippocampus:\n")
          (insert "#+identifier: " id "\n\n")
          (insert ":PROPERTIES:\n")
          (insert ":RUN_ID: " (or run-id "") "\n")
          (insert ":MODE: "   (or mode-str "") "\n")
          (insert ":END:\n\n")
          (insert body)
          (unless (string-suffix-p "\n" body) (insert "\n")))
        (when (memq 'memory-write caps)
          (satan-tools-hippocampus--cross-ref title path ctx))
        (satan-tools-hippocampus--emit-attribute-signal
         "written" "hippocampus_write" filename ctx)
        (cons 'ok (list :path path)))))))

;; ---------- hippocampus_overwrite ----------

(defun satan-tools-hippocampus--replace-body (path new-body)
  "Replace body content in PATH (everything after :END:\\n\\n)."
  (let ((text (with-temp-buffer
                (let ((coding-system-for-read 'utf-8))
                  (insert-file-contents path))
                (buffer-string))))
    (if (string-match ":END:\n\n" text)
        (let ((header (substring text 0 (match-end 0)))
              (coding-system-for-write 'utf-8))
          (with-temp-file path
            (insert header)
            (insert new-body)
            (unless (string-suffix-p "\n" new-body) (insert "\n")))
          t)
      nil)))

(defun satan-tool/hippocampus-overwrite (args ctx)
  "Replace body of an existing hippocampus entry."
  (let ((filename (plist-get args :filename))
        (body (plist-get args :body)))
    (cond
     ((not (satan-tools-hippocampus--safe-path-p filename))
      (cons 'error "filename must be a plain basename"))
     ((not (stringp body))
      (cons 'error "body must be a string"))
     (t
      (let ((path (expand-file-name filename satan-hippocampus-dir)))
        (cond
         ((not (file-exists-p path))
          (cons 'error (format "not found: %s" filename)))
         ((not (satan-tools-hippocampus--replace-body path body))
          (cons 'error "could not locate :END: block in file"))
         (t
          (satan-tools-hippocampus--emit-attribute-signal
           "overwritten" "hippocampus_overwrite" filename ctx)
          (cons 'ok (list :filename filename)))))))))

;; ---------- hippocampus_delete ----------

(defun satan-tool/hippocampus-delete (args ctx)
  "Delete a hippocampus entry by filename."
  (let ((filename (plist-get args :filename)))
    (cond
     ((not (satan-tools-hippocampus--safe-path-p filename))
      (cons 'error "filename must be a plain basename"))
     (t
      (let ((path (expand-file-name filename satan-hippocampus-dir)))
        (if (not (file-exists-p path))
            (cons 'error (format "not found: %s" filename))
          (delete-file path)
          (satan-tools-hippocampus--emit-attribute-signal
           "deleted" "hippocampus_delete" filename ctx)
          (cons 'ok (list :deleted filename))))))))

;; ---------- hippocampus_grep ----------

(defvar satan-tools-hippocampus--rg-program "rg"
  "Name or path of the rg binary.")

(defconst satan-tools-hippocampus--grep-max 50
  "Maximum matches returned by hippocampus_grep.")

(defun satan-tool/hippocampus-grep (args ctx)
  "Search hippocampus entries with rg.  Returns matching lines."
  (let ((query (plist-get args :query)))
    (cond
     ((not (stringp query))
      (cons 'error "query must be a string"))
     ((string-empty-p query)
      (cons 'error "query must be non-empty"))
     ((not (file-directory-p satan-hippocampus-dir))
      (cons 'ok (list :matches nil :count 0)))
     (t
      (let* ((stdout-buf (generate-new-buffer " *satan-hippo-rg*"))
             (stderr-file (make-temp-file "satan-hippo-rg-err-"))
             (argv (list "--no-heading" "--line-number"
                         "--max-count" "10"
                         "--max-columns" "200"
                         "--ignore-case"
                         "--" query satan-hippocampus-dir))
             (exit (apply #'call-process
                          satan-tools-hippocampus--rg-program nil
                          (list stdout-buf stderr-file) nil argv))
             (stdout (with-current-buffer stdout-buf (buffer-string))))
        (kill-buffer stdout-buf)
        (when (file-exists-p stderr-file) (delete-file stderr-file))
        (if (and (not (= exit 0)) (not (= exit 1)))
            (cons 'error (format "rg failed: exit %d" exit))
          (let* ((lines (cl-remove-if #'string-empty-p
                                      (split-string stdout "\n" t)))
                 (capped (if (> (length lines)
                                satan-tools-hippocampus--grep-max)
                             (cl-subseq lines 0
                                        satan-tools-hippocampus--grep-max)
                           lines))
                 (matches
                  (mapcar
                   (lambda (line)
                     (if (string-match
                          "\\([^:]+\\):\\([0-9]+\\):\\(.*\\)" line)
                         (list :filename (file-name-nondirectory
                                          (match-string 1 line))
                               :line (string-to-number
                                      (match-string 2 line))
                               :text (match-string 3 line))
                       (list :text line)))
                   capped)))
            (when (null matches)
              (satan-tools-hippocampus--emit-attribute-signal
               "searched" "hippocampus_grep" query ctx))
            (cons 'ok (list :query query
                            :matches matches
                            :count (length matches))))))))))

;; ---------- hippocampus_rename ----------

(defun satan-tools-hippocampus--update-title-header (path new-title)
  "Replace #+title: line in PATH with NEW-TITLE."
  (let* ((text (with-temp-buffer
                 (let ((coding-system-for-read 'utf-8))
                   (insert-file-contents path))
                 (buffer-string)))
         (updated (replace-regexp-in-string
                   "^#\\+title:.*$"
                   (concat "#+title:      " new-title)
                   text nil nil nil 0)))
    (let ((coding-system-for-write 'utf-8))
      (with-temp-file path (insert updated)))))

(defun satan-tool/hippocampus-rename (args ctx)
  "Rename a hippocampus entry: update filename slug and #+title."
  (let ((filename (plist-get args :filename))
        (new-title (plist-get args :title)))
    (cond
     ((not (satan-tools-hippocampus--safe-path-p filename))
      (cons 'error "filename must be a plain basename"))
     ((not (stringp new-title))
      (cons 'error "title must be a string"))
     (t
      (let ((old-path (expand-file-name filename satan-hippocampus-dir)))
        (if (not (file-exists-p old-path))
            (cons 'error (format "not found: %s" filename))
          (let* ((new-slug (satan-tools-hippocampus--slugify new-title))
                 (new-filename
                  (if (string-match "^\\([0-9T]+\\)--" filename)
                      (let ((ts (match-string 1 filename)))
                        (format "%s--%s__satan_hippocampus.org" ts new-slug))
                    (format "%s__satan_hippocampus.org" new-slug)))
                 (new-path (expand-file-name new-filename
                                             satan-hippocampus-dir)))
            (satan-tools-hippocampus--update-title-header
             old-path new-title)
            (unless (equal old-path new-path)
              (rename-file old-path new-path))
            (satan-tools-hippocampus--emit-attribute-signal
             "renamed" "hippocampus_rename" new-filename ctx)
            (cons 'ok (list :old_filename filename
                            :new_filename new-filename)))))))))

;; ---------- registration ----------

(satan-tool-register
 (list :name "hippocampus_list"
       :risk 'read
       :args-schema nil
       :handler 'satan-tool/hippocampus-list))

(satan-tool-register
 (list :name "hippocampus_read"
       :risk 'read
       :args-schema (list 'filename (list :type 'string :required t))
       :handler 'satan-tool/hippocampus-read))

(satan-tool-register
 (list :name "hippocampus_write"
       :risk 'low
       :capability 'hippocampus-write
       :args-schema '(title (:type string :required t)
                      body  (:type string :required t))
       :handler 'satan-tool/hippocampus-write))

(satan-tool-register
 (list :name "hippocampus_overwrite"
       :risk 'low
       :capability 'hippocampus-write
       :args-schema (list 'filename (list :type 'string :required t)
                          'body     (list :type 'string :required t))
       :handler 'satan-tool/hippocampus-overwrite))

(satan-tool-register
 (list :name "hippocampus_delete"
       :risk 'low
       :capability 'hippocampus-write
       :args-schema (list 'filename (list :type 'string :required t))
       :handler 'satan-tool/hippocampus-delete))

(satan-tool-register
 (list :name "hippocampus_grep"
       :risk 'read
       :args-schema (list 'query (list :type 'string :required t))
       :handler 'satan-tool/hippocampus-grep))

(satan-tool-register
 (list :name "hippocampus_rename"
       :risk 'low
       :capability 'hippocampus-write
       :args-schema (list 'filename (list :type 'string :required t)
                          'title    (list :type 'string :required t))
       :handler 'satan-tool/hippocampus-rename))

(defun satan-hippocampus ()
  "Open the SATAN hippocampus directory in dired."
  (interactive)
  (unless (file-directory-p satan-hippocampus-dir)
    (make-directory satan-hippocampus-dir t))
  (dired satan-hippocampus-dir))

(provide 'satan-tools-hippocampus)
;;; satan-tools-hippocampus.el ends here
