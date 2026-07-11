;;; dl-satan-tools-motive.el --- motive_read / motive_replace -*- lexical-binding: t; -*-

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
;; Replace runs every proposal through `dl-satan-motive-validate-
;; for-write' (§A7 / §A8).  Bounds and the forbidden `:ceiling:'
;; field are rejected with a structured error before the file is
;; touched; the write itself is atomic (tmp + rename).

(require 'cl-lib)
(require 'subr-x)
(require 'dl-satan-tools)
(require 'dl-satan-motive)

;; ---------------------------------------------------------------------
;; motive_read
;; ---------------------------------------------------------------------

(defun dl-satan-tools-motive--summary (parsed)
  "Return a result plist summarising PARSED (a `motive-parse' result).
Kept narrow on purpose: the model gets the raw file via `:content';
counts here let it judge headroom against the §A7 bounds without
re-implementing the parser."
  (list :content (dl-satan-tools-motive--read-text dl-satan-motive-file)
        :active_motives
        (length (cl-remove-if (lambda (m) (plist-get m :dormant))
                              (plist-get parsed :motives)))
        :dormant_motives
        (length (cl-remove-if-not (lambda (m) (plist-get m :dormant))
                                  (plist-get parsed :motives)))
        :ruminations_count (length (plist-get parsed :ruminations))
        :max_active dl-satan-motive-max-active
        :max_ruminations dl-satan-motive-max-ruminations))

(defun dl-satan-tools-motive--read-text (path)
  "Return file contents at PATH, or empty string if absent."
  (if (and path (file-readable-p path))
      (with-temp-buffer
        (let ((coding-system-for-read 'utf-8))
          (insert-file-contents path))
        (buffer-string))
    ""))

(defun dl-satan-tool/motive-read (_args _tool-ctx)
  "Handler for `motive_read'.  No arguments; returns the file + summary."
  (let* ((parsed (dl-satan-motive-read dl-satan-motive-file)))
    (cons 'ok (dl-satan-tools-motive--summary parsed))))

;; ---------------------------------------------------------------------
;; motive_replace
;; ---------------------------------------------------------------------

(defun dl-satan-tools-motive--write-atomic (path content)
  "Write CONTENT to PATH atomically (tmp file + rename).
Matches `dl-satan-audit--write-json' pattern.  Caller has already
validated CONTENT."
  (let ((dir (file-name-directory path)))
    (unless (file-directory-p dir) (make-directory dir t)))
  (let ((tmp (concat path ".tmp"))
        (coding-system-for-write 'utf-8))
    (with-temp-file tmp (insert content))
    (rename-file tmp path t)))

(defun dl-satan-tool/motive-replace (args _tool-ctx)
  "Handler for `motive_replace'.
ARGS: (:content STR).  Validates against `dl-satan-motive-validate-
for-write' (§A7 / §A8); on accept, atomic-writes
`dl-satan-motive-file' and returns the new summary."
  (let* ((content (plist-get args :content))
         (err (cond
               ((not (stringp content)) "content must be string")
               (t (dl-satan-motive-validate-for-write content)))))
    (cond
     ((stringp err) (cons 'error err))
     (err (cons 'error (dl-satan-motive-format-write-error err)))
     (t
      (dl-satan-tools-motive--write-atomic dl-satan-motive-file content)
      (cons 'ok (dl-satan-tools-motive--summary
                 (dl-satan-motive-parse content)))))))

;; ---------------------------------------------------------------------
;; Registration
;; ---------------------------------------------------------------------

(dl-satan-tool-register
 (list :name "motive_read"
       :risk 'read
       :args-schema nil
       :handler 'dl-satan-tool/motive-read))

(dl-satan-tool-register
 (list :name "motive_replace"
       :risk 'medium
       :capability 'motive-write
       :args-schema (list 'content (list :type 'string :required t))
       :handler 'dl-satan-tool/motive-replace))

(provide 'dl-satan-tools-motive)
;;; dl-satan-tools-motive.el ends here
