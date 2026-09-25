;;; satan-hippocampus.el --- hippocampus entries and capsule block -*- lexical-binding: t; -*-

;; The hippocampus is SATAN's self-curated memory: denote-named org files
;; under `satan-hippocampus-dir'.  This module owns the hippocampus as
;; *data* — listing entries, extracting their titles, and rendering the
;; titles-only block the context capsule carries — so that the memory the
;; agent writes is the memory the next capsule reads back.  The tool
;; handlers (`hippocampus_list' &c.) live in `satan-tools-hippocampus'.
;;
;; The block self-suppresses when the directory is absent/empty or when
;; framing.txt supplies no header (same contract as the percept/motive
;; blocks); the header text is mind-owned, never hardcoded here.

(require 'cl-lib)
(require 'subr-x)
(require 'satan-custom)
(require 'satan-run)

(defcustom satan-hippocampus-capsule-limit 5
  "Max hippocampus titles rendered into the context capsule.
The hippocampus grows without bound; the capsule needs only enough
recent titles to make memory present, so this bounds the block."
  :type 'integer :group 'satan)

(defconst satan-hippocampus--framing-key "hippocampus_block_header"
  "Framing.txt key that supplies the hippocampus block's section header.
Owned by mind (`satan-system-framing-file'); an absent key suppresses
the block, the same contract as the other render blocks.")

(defun satan-hippocampus--parse-title (filename)
  "Extract title from denote-style FILENAME, or return FILENAME."
  (if (string-match "^[0-9T]+--\\([^_]+\\)" filename)
      (replace-regexp-in-string "-" " " (match-string 1 filename))
    filename))

(defun satan-hippocampus--parse-date (filename)
  "Return FILENAME's leading denote date as YYYY-MM-DD, or nil.
The authored timestamp in the name is the entry's date; file mtime is
only a fallback (it moves on copy/edit)."
  (when (string-match "^\\([0-9]\\{4\\}\\)\\([0-9]\\{2\\}\\)\\([0-9]\\{2\\}\\)" filename)
    (format "%s-%s-%s"
            (match-string 1 filename)
            (match-string 2 filename)
            (match-string 3 filename))))

(defun satan-hippocampus-entry (path)
  "Build an entry plist for PATH (absolute)."
  (let* ((filename (file-name-nondirectory path))
         (mtime (file-attribute-modification-time (file-attributes path)))
         (mtime-str (format-time-string "%Y-%m-%dT%H:%M:%S%z" mtime)))
    (list :filename filename
          :title (satan-hippocampus--parse-title filename)
          :date (or (satan-hippocampus--parse-date filename)
                    (substring mtime-str 0 10))
          :mtime mtime-str)))

(defun satan-hippocampus-entries ()
  "Return all hippocampus entries, newest first.
Sorts by authored date, falling back to the denote filename (whose
leading timestamp is authoritative) so entries written within the same
second still order deterministically."
  (if (not (file-directory-p satan-hippocampus-dir))
      nil
    (let* ((files (directory-files satan-hippocampus-dir t "\\.org\\'"))
           (entries (mapcar #'satan-hippocampus-entry files)))
      (sort entries
            (lambda (a b)
              (let ((ad (plist-get a :date))
                    (bd (plist-get b :date)))
                (if (string= ad bd)
                    (string> (plist-get a :filename) (plist-get b :filename))
                  (string> ad bd))))))))

(defun satan-hippocampus-render-block (framing entries &optional limit)
  "Return the rendered `# Hippocampus' block as a list of lines, or nil.
FRAMING is the parsed framing alist.  ENTRIES is
`satan-hippocampus-entries' output.  LIMIT caps the entries rendered
\(default `satan-hippocampus-capsule-limit'); the newest are kept.
Returns nil when ENTRIES is empty or framing carries no header, so the
renderer drops the block entirely instead of emitting an empty header."
  (let ((header (cdr (assoc satan-hippocampus--framing-key framing)))
        (limit (or limit satan-hippocampus-capsule-limit)))
    (when (and header entries)
      (cons header
            (mapcar (lambda (e)
                      (format "- [%s] %s"
                              (plist-get e :date)
                              (plist-get e :title)))
                    (if (and (integerp limit) (> (length entries) limit))
                        (cl-subseq entries 0 limit)
                      entries))))))

(provide 'satan-hippocampus)
;;; satan-hippocampus.el ends here
