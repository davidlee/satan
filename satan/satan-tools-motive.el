;;; satan-tools-motive.el --- motive_read / motive_replace -*- lexical-binding: t; -*-

;; Phase 3.2 of perceptual-design.md (§S3 / §A7 / §A8).  Two tools:
;;
;;   motive_read     (risk: read,   no capability)
;;   motive_replace  (risk: medium, capability: motive-write)
;;
;; Read returns the raw motives.org text plus a small structured
;; summary (active count, rumination count).  The model already
;; knows the org format; the diagnostic counts let it see at a
;; glance whether it is near the §A7 bounds before proposing a
;; replacement.
;;
;; Replace runs every proposal through `satan-motive-validate-
;; for-write' (§A7 / §A8).  Bounds and the forbidden `:ceiling:'
;; field are rejected with a structured error before the file is
;; touched; the write itself is atomic (tmp + rename).

(require 'cl-lib)
(require 'subr-x)
(require 'satan-tools)
(require 'satan-motive)

;; ---------------------------------------------------------------------
;; motive_read
;; ---------------------------------------------------------------------

(defun satan-tools-motive--summary (parsed)
  "Return a result plist summarising PARSED (a `motive-parse' result).
Kept narrow on purpose: the model gets the raw file via `:content';
counts here let it judge headroom against the §A7 bounds without
re-implementing the parser."
  (list :content (satan-tools-motive--read-text satan-motive-file)
        :active_motives
        (length (cl-remove-if (lambda (m) (plist-get m :dormant))
                              (plist-get parsed :motives)))
        :dormant_motives
        (length (cl-remove-if-not (lambda (m) (plist-get m :dormant))
                                  (plist-get parsed :motives)))
        :ruminations_count (length (plist-get parsed :ruminations))
        :max_active satan-motive-max-active
        :max_ruminations satan-motive-max-ruminations))

(defun satan-tools-motive--read-text (path)
  "Return file contents at PATH, or empty string if absent."
  (if (and path (file-readable-p path))
      (with-temp-buffer
        (let ((coding-system-for-read 'utf-8))
          (insert-file-contents path))
        (buffer-string))
    ""))

(defun satan-tool/motive-read (_args _tool-ctx)
  "Handler for `motive_read'.  No arguments; returns the file + summary."
  (let* ((parsed (satan-motive-read satan-motive-file)))
    (cons 'ok (satan-tools-motive--summary parsed))))

;; ---------------------------------------------------------------------
;; motive_replace
;; ---------------------------------------------------------------------

(defun satan-tools-motive--write-atomic (path content)
  "Write CONTENT to PATH atomically (tmp file + rename).
Matches `satan-audit--write-json' pattern.  Caller has already
validated CONTENT."
  (let ((dir (file-name-directory path)))
    (unless (file-directory-p dir) (make-directory dir t)))
  (let ((tmp (concat path ".tmp"))
        (coding-system-for-write 'utf-8))
    (with-temp-file tmp (insert content))
    (rename-file tmp path t)))

(defun satan-tool/motive-replace (args _tool-ctx)
  "Handler for `motive_replace'.
ARGS: (:content STR).  Validates against `satan-motive-validate-
for-write' (§A7 / §A8); on accept, atomic-writes
`satan-motive-file' and returns the new summary."
  (let* ((content (plist-get args :content))
         (err (cond
               ((not (stringp content)) "content must be string")
               (t (satan-motive-validate-for-write content)))))
    (cond
     ((stringp err) (cons 'error err))
     (err (cons 'error (satan-motive-format-write-error err)))
     (t
      (satan-tools-motive--write-atomic satan-motive-file content)
      (cons 'ok (satan-tools-motive--summary
                 (satan-motive-parse content)))))))

;; ---------------------------------------------------------------------
;; Registration
;; ---------------------------------------------------------------------

(satan-tool-register
 (list :name "motive_read"
       :risk 'read
       :args-schema nil
       :handler 'satan-tool/motive-read))

(satan-tool-register
 (list :name "motive_replace"
       :risk 'medium
       :capability 'motive-write
       :args-schema (list 'content (list :type 'string :required t))
       :handler 'satan-tool/motive-replace))

(provide 'satan-tools-motive)
;;; satan-tools-motive.el ends here
