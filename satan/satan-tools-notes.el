;;; satan-tools-notes.el --- notes_recent tool handler -*- lexical-binding: t; -*-

;; Read-only window into recently-changed files under the user's notes
;; corpus (`satan-tools-notes-root', default `satan-notes-root').
;; Complements `activity_read' (window focus) and `org_read_context'
;; (fixed files): tells SATAN which notes *artifacts* moved recently,
;; regardless of which window the user was looking at.
;;
;; Each result entry is a plist:
;;   :path        relative to the root (e.g. "journal/foo.org")
;;   :mtime       ISO-8601 string (local time, with TZ offset)
;;   :title       human title parsed from denote-style filename, or nil
;;   :tags        list of tag strings parsed from denote-style filename
;;   :ext         file extension (e.g. "org")
;;
;; The denote filename convention is
;;   <DATE>--<TITLE-SLUG>__<TAG1_TAG2>.<EXT>
;; Dashes in the slug → spaces in :title; underscores in the tag block
;; → list of strings in :tags.  Non-denote filenames return :title nil
;; and a raw :path.
;;
;; Backend: shells out to `fd' (`satan-tools-notes--fd-program').
;; gitignore-aware by default — keeps `~/notes/elpa', `~/notes/.git'
;; etc. out of results without us having to maintain an exclude list.
;;
;; The `satan/' subtree is always excluded to keep SATAN from
;; self-spamming on its own inbox/proposals/motd churn.
;;
;; Risk = `read'; no capability required.

(require 'cl-lib)
(require 'subr-x)
(require 'satan-custom)
(require 'satan-tools)

(defcustom satan-tools-notes-root
  satan-notes-root
  "Root directory `notes_recent' searches under."
  :type 'directory :group 'satan)

(defcustom satan-tools-notes-default-hours 24
  "Default `:since-hours' window for `notes_recent'."
  :type 'integer :group 'satan)

(defcustom satan-tools-notes-default-limit 30
  "Default `:limit' for `notes_recent'."
  :type 'integer :group 'satan)

(defconst satan-tools-notes--hours-max 720
  "Hard upper bound on `:since-hours' (30 days); clamped without error.")

(defconst satan-tools-notes--limit-max 200
  "Hard upper bound on `:limit'; clamped without error.")

(defconst satan-tools-notes--exclude '("satan")
  "Top-level subdir names dropped from `notes_recent' results.")

(defvar satan-tools-notes--fd-program "fd"
  "Name (or absolute path) of the `fd' binary.  Overridable for tests.")

(defun satan-tools-notes--clamp (raw default min max)
  (cond ((null raw) default)
        ((< raw min) min)
        ((> raw max) max)
        (t raw)))

(defun satan-tools-notes--build-argv (hours)
  (let ((argv (list "--changed-after" (format "%dh" hours)
                    "-t" "f"
                    "--print0"
                    "--base-directory" satan-tools-notes-root)))
    (dolist (name satan-tools-notes--exclude)
      (setq argv (append argv (list "--exclude" name))))
    argv))

(defun satan-tools-notes--run-fd (argv)
  "Invoke fd with ARGV.
Return a plist `(:exit N :stdout STR :stderr STR)'."
  (let ((stdout-buf (generate-new-buffer " *satan-notes-fd-out*"))
        (stderr-file (make-temp-file "satan-notes-fd-err-")))
    (unwind-protect
        (let ((exit (apply #'call-process
                           satan-tools-notes--fd-program nil
                           (list stdout-buf stderr-file) nil argv)))
          (list :exit exit
                :stdout (with-current-buffer stdout-buf (buffer-string))
                :stderr (with-temp-buffer
                          (when (file-readable-p stderr-file)
                            (insert-file-contents stderr-file))
                          (buffer-string))))
      (when (buffer-live-p stdout-buf) (kill-buffer stdout-buf))
      (when (file-exists-p stderr-file) (delete-file stderr-file)))))

(defconst satan-tools-notes--denote-re
  "\\`\\(?:[0-9T]+--\\)?\\([^_/]+?\\)\\(?:__\\([^.]+\\)\\)?\\.\\([^.]+\\)\\'"
  "Match `[DATE--]TITLE-SLUG[__TAG_TAG].EXT' in a basename.")

(defun satan-tools-notes--parse-basename (basename)
  "Return plist (:title :tags :ext) for BASENAME.
If BASENAME doesn't carry a denote `--TITLE' segment, :title is nil."
  (if (string-match satan-tools-notes--denote-re basename)
      (let* ((slug (match-string 1 basename))
             (tags-raw (match-string 2 basename))
             (ext (match-string 3 basename))
             (has-date (string-match-p "\\`[0-9T]+--" basename))
             (title (when has-date
                      (replace-regexp-in-string "-" " " slug)))
             (tags (when tags-raw (split-string tags-raw "_" t))))
        (list :title title :tags tags :ext ext))
    (list :title nil :tags nil :ext nil)))

(defun satan-tools-notes--mtime-iso (path)
  (format-time-string "%Y-%m-%dT%H:%M:%S%z"
                      (file-attribute-modification-time
                       (file-attributes path))))

(defun satan-tools-notes--file-plist (rel-path)
  (let* ((abs (expand-file-name rel-path satan-tools-notes-root))
         (basename (file-name-nondirectory rel-path))
         (meta (satan-tools-notes--parse-basename basename))
         (mtime (file-attribute-modification-time (file-attributes abs))))
    (list :path rel-path
          :mtime (satan-tools-notes--mtime-iso abs)
          :title (plist-get meta :title)
          :tags (plist-get meta :tags)
          :ext (plist-get meta :ext)
          :_sort mtime)))

(defun satan-tools-notes--split-stdout (stdout)
  "Split fd NUL-delimited STDOUT into a list of non-empty paths."
  (cl-remove-if #'string-empty-p
                (split-string stdout "\0" t)))

(defun satan-tool/notes-read (args _ctx)
  "Implements notes_recent.  ARGS: (:since-hours INT? :limit INT?).
Returns (ok PLIST) | (error STRING)."
  (let* ((hours (satan-tools-notes--clamp
                 (plist-get args :since-hours)
                 satan-tools-notes-default-hours
                 1 satan-tools-notes--hours-max))
         (limit (satan-tools-notes--clamp
                 (plist-get args :limit)
                 satan-tools-notes-default-limit
                 1 satan-tools-notes--limit-max))
         (argv  (satan-tools-notes--build-argv hours))
         (run   (satan-tools-notes--run-fd argv)))
    (if (not (eq (plist-get run :exit) 0))
        (cons 'error
              (format "fd failed: exit=%s %s"
                      (plist-get run :exit)
                      (string-trim (plist-get run :stderr))))
      (let* ((paths (satan-tools-notes--split-stdout
                     (plist-get run :stdout)))
             (entries (mapcar #'satan-tools-notes--file-plist paths))
             (sorted (sort entries
                           (lambda (a b)
                             (time-less-p (plist-get b :_sort)
                                          (plist-get a :_sort)))))
             (capped (if (> (length sorted) limit)
                         (cl-subseq sorted 0 limit)
                       sorted))
             (clean (mapcar (lambda (e)
                              (let ((copy (copy-sequence e)))
                                (cl-remf copy :_sort)
                                copy))
                            capped)))
        (cons 'ok
              (list :scope "notes_recent"
                    :root satan-tools-notes-root
                    :since-hours hours
                    :limit limit
                    :count (length clean)
                    :files clean))))))

(satan-tool-register
 (list :name "notes_recent"
       :risk 'read
       :args-schema '(since-hours (:type integer :required nil)
                      limit       (:type integer :required nil))
       :handler 'satan-tool/notes-read))

(provide 'satan-tools-notes)
;;; satan-tools-notes.el ends here
