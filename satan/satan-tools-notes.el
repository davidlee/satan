;;; satan-tools-notes.el --- notes_recent / notes_read / notes_grep -*- lexical-binding: t; -*-

;; Three read-only windows into the user's notes corpus
;; (`satan-tools-notes-root', default `satan-notes-root'):
;;
;;   notes_recent  what moved recently (fd; paths/titles/tags/mtimes, no bodies)
;;   notes_read    one note's body, confined to the root and byte-capped
;;   notes_grep    a literal search over the set `notes_read' can open
;;
;; `notes_recent' complements `activity_read' (window focus) and
;; `org_read_context' (fixed files): it says which notes *artifacts* moved,
;; regardless of which window the user was looking at.
;;
;; Each `notes_recent' entry is a plist:
;;   :path        relative to the root (e.g. "journal/foo.org")
;;   :mtime       ISO-8601 string (local time, with TZ offset)
;;   :title       human title parsed from denote-style filename, or nil
;;   :tags        list of tag strings parsed from denote-style filename
;;   :ext         file extension (e.g. "org")
;;
;; The denote filename convention is
;;   <DATE>--<TITLE-SLUG>__<TAG1_TAG2>.<EXT>
;; Dashes in the slug → spaces in :title; underscores in the tag block
;; → list of strings in :tags.  A name without the date prefix returns
;; :title nil and a raw :path.
;;
;; Backend: shells out to `fd' (`satan-tools-notes--fd-program') and `rg'
;; (`satan-tools-notes--rg-program').  Each is resolved on PATH before it is
;; spawned, so an unavailable probe is an error in this module's own words
;; rather than a generic spawn failure.  gitignore-aware by default — keeps
;; `~/notes/elpa', `~/notes/.git' etc. out of results without us having to
;; maintain an exclude list.
;;
;; Failure policy (one rule, two probes): an unavailable or failing probe, and
;; any `rg' exit above 1, is an error.  `rg' exit 1 (no matches) is a clean
;; empty result.  A soft-failed search would be indistinguishable from a corpus
;; with no hits — the wrong-but-readable answer SL-015 rules out.
;;
;; Risk = `read'; no capability required.  The notes corpus is the user's and
;; read-only to SATAN: nothing here writes.

(require 'cl-lib)
(require 'subr-x)
(require 'satan-custom)
(require 'satan-tools)

(defcustom satan-tools-notes-root
  satan-notes-root
  "Root directory the notes tools search under."
  :type 'directory :group 'satan)

(defcustom satan-tools-notes-default-hours 24
  "Default `:since-hours' window for `notes_recent'."
  :type 'integer :group 'satan)

(defcustom satan-tools-notes-default-limit 30
  "Default `:limit' for `notes_recent' and `notes_grep'."
  :type 'integer :group 'satan)

(defcustom satan-tools-notes-read-max-bytes 32768
  "Maximum bytes `notes_read' returns from one note body.
Over the cap the body is truncated and flagged; the unit is bytes because the
cap is applied at the read syscall, where decoding the whole file to count
characters is exactly the cost the cap exists to avoid."
  :type 'integer :group 'satan)

(defconst satan-tools-notes--hours-max 720
  "Hard upper bound on `:since-hours' (30 days); clamped without error.")

(defconst satan-tools-notes--limit-max 200
  "Hard upper bound on `:limit'; clamped without error.")

(defconst satan-tools-notes--grep-max 50
  "Hard upper bound on matches returned by `notes_grep'.")

(defconst satan-tools-notes--openable-extensions '("org" "md" "txt")
  "File extensions `notes_read' opens, and `notes_grep' searches.
One list, two consumers: the read door and the search set cannot drift apart.")

(defvar satan-tools-notes--fd-program "fd"
  "Name (or absolute path) of the `fd' binary.  Overridable for tests.")

(defvar satan-tools-notes--rg-program "rg"
  "Name (or absolute path) of the `rg' binary.  Overridable for tests.")

(defun satan-tools-notes--clamp (raw default min max)
  (cond ((null raw) default)
        ((< raw min) min)
        ((> raw max) max)
        (t raw)))

(defun satan-tools-notes--root ()
  "Return the expanded notes root as a directory name, or nil if unusable.
A corpus that is unreachable is named as such by the callers rather than
reported as a bad path: every path would otherwise look like an escape."
  (let ((root (file-name-as-directory (expand-file-name satan-tools-notes-root))))
    (and (file-directory-p root) root)))

(defun satan-tools-notes--ensure-program (name)
  "Return NAME when an executable by that name is on PATH, else nil."
  (and (executable-find name) name))

(defun satan-tools-notes--build-argv (hours)
  (list "--changed-after" (format "%dh" hours)
        "-t" "f"
        "--print0"
        ;; `call-process' performs no shell tilde expansion, so a literal
        ;; "~/notes" base-directory would reach fd as a nonexistent path.
        ;; Expand here.
        "--base-directory"
        (expand-file-name satan-tools-notes-root)
        ;; Without this, `--base-directory' makes fd print `./'-prefixed
        ;; paths; `--resolve' refuses a leading-dot component, so
        ;; `notes_recent' would hand `notes_read' paths it cannot open.
        ;; Absolute output + `--relativize' is the one shape both probes
        ;; agree on.
        "--absolute-path"))

(defun satan-tools-notes--grep-argv (query root)
  "Build the rg argv searching ROOT for QUERY.
The extension globs are derived from `satan-tools-notes--openable-extensions'
rather than restated, so the search set is the read door's set by construction.
`--max-columns-preview' keeps a long matching line readable: without it rg
replaces the line with `[Omitted long matching line]' and the phrase is lost."
  (append (list "--no-heading" "--line-number" "--ignore-case" "--fixed-strings"
                "--max-columns" "200" "--max-columns-preview")
          (cl-loop for ext in satan-tools-notes--openable-extensions
                   append (list "--glob" (concat "*." ext)))
          (list "--" query root)))

(defun satan-tools-notes--run (program argv)
  "Invoke PROGRAM with ARGV.
Return a plist `(:exit N :stdout STR :stderr STR)'."
  (let ((stdout-buf (generate-new-buffer " *satan-notes-out*"))
        (stderr-file (make-temp-file "satan-notes-err-")))
    (unwind-protect
        (let ((exit (apply #'call-process
                           program nil
                           (list stdout-buf stderr-file) nil argv)))
          (list :exit exit
                :stdout (with-current-buffer stdout-buf (buffer-string))
                :stderr (with-temp-buffer
                          (when (file-readable-p stderr-file)
                            (insert-file-contents stderr-file))
                          (buffer-string))))
      (when (buffer-live-p stdout-buf) (kill-buffer stdout-buf))
      (when (file-exists-p stderr-file) (delete-file stderr-file)))))

(defun satan-tools-notes--result-error (prefix run)
  "Build the error string for a failed RUN, prefixed with PREFIX."
  (let ((detail (string-trim (or (plist-get run :stderr) ""))))
    (format "%s: exit %s%s" prefix (plist-get run :exit)
            (if (string-empty-p detail) "" (concat " " detail)))))

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

(defun satan-tools-notes--public (entry)
  "Return ENTRY without the internal `:_sort' key.
`:_sort' is an Emacs time object: it exists so `notes_recent' can order
entries, and it cannot cross the wire meaningfully — the JSON layer renders
it as a bare integer array.  No tool result carries it."
  (let ((copy (copy-sequence entry)))
    (cl-remf copy :_sort)
    copy))

(defun satan-tools-notes--split-stdout (stdout)
  "Split fd NUL-delimited STDOUT into a list of non-empty paths."
  (cl-remove-if #'string-empty-p
                (split-string stdout "\0" t)))

(defun satan-tools-notes--split-lines (stdout)
  "Split rg's newline-delimited STDOUT into non-empty lines."
  (cl-remove-if #'string-empty-p
                (split-string stdout "\n" t)))

(defun satan-tools-notes--relativize (path root)
  "Return PATH relative to ROOT (a directory name) when it sits under it.
Both probes echo the path form they were handed — rg echoes the argument, fd
the base directory it was given — so this is a prefix strip, not a filesystem
call.  A nil ROOT (an unreachable corpus) leaves PATH untouched."
  (if (and root (string-prefix-p root path))
      (substring path (length root))
    path))

(defun satan-tools-notes--parse-match (line root)
  "Parse one `PATH:LINE:TEXT' rg output LINE into a plist, or nil.
PATH is returned relative to ROOT."
  (when (string-match "\\`\\(.+\\):\\([0-9]+\\):\\(.*\\)\\'" line)
    (list :path (satan-tools-notes--relativize (match-string 1 line) root)
          :line (string-to-number (match-string 2 line))
          :text (match-string 3 line))))

(defun satan-tools-notes--resolve (rel)
  "Return (:path ABS) for a notes-root-relative REL, or (:error MESSAGE).
Two independent checks: containment is decided on the resolved path (truename,
so a symlink escaping the root is refused), shape on the requested name (so a
link cannot smuggle a format the door is closed to).  A directory — including
the root itself, which `file-in-directory-p' counts as inside itself — is left
to the caller, which refuses it as a non-file."
  (let ((root (satan-tools-notes--root)))
    (cond
     ((null root)
      (list :error (format "notes root not found: %s" satan-tools-notes-root)))
     ((not (stringp rel))
      (list :error "path must be a string"))
     ((string-empty-p rel)
      (list :error "path must be non-empty"))
     ((file-name-absolute-p rel)
      (list :error (format "path escapes notes root: %s" rel)))
     ((member ".." (split-string rel "/"))
      (list :error (format "path escapes notes root: %s" rel)))
     ((cl-some (lambda (c) (string-prefix-p "." c)) (split-string rel "/"))
      (list :error (format "hidden path not readable: %s" rel)))
     (t
      (let ((abs (expand-file-name rel root)))
        (cond
         ((not (file-in-directory-p abs root))
          (list :error (format "path escapes notes root: %s" rel)))
         ((and (not (file-directory-p abs))
               (not (member (downcase (or (file-name-extension rel) ""))
                            satan-tools-notes--openable-extensions)))
          (list :error (format "not a note file: %s" rel)))
         (t (list :path abs))))))))

(defun satan-tools-notes--read-capped (abs max)
  "Return (:body STR :bytes N :total-bytes M :truncated BOOL) for ABS.
Reads at most MAX bytes, decoded as utf-8.  Emacs aligns the read to a
character boundary, so a capped body never ends mid-character; :total-bytes
comes from one `file-attributes' call."
  (let* ((size (file-attribute-size (file-attributes abs)))
         (truncated (> size max))
         (body (with-temp-buffer
                 (let ((coding-system-for-read 'utf-8))
                   (insert-file-contents abs nil 0 (if truncated max nil)))
                 (buffer-string))))
    (list :body body
          :bytes (string-bytes body)
          :total-bytes size
          :truncated truncated)))

;; ---------- notes_recent ----------

(defun satan-tool/notes-recent (args _ctx)
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
         (program (satan-tools-notes--ensure-program satan-tools-notes--fd-program)))
    (cond
     ((null program)
      (cons 'error (format "%s not found on PATH" satan-tools-notes--fd-program)))
     (t
      (let ((run (satan-tools-notes--run program
                                         (satan-tools-notes--build-argv hours))))
        (if (not (eq (plist-get run :exit) 0))
            (cons 'error (satan-tools-notes--result-error "fd failed" run))
          (let* ((paths (satan-tools-notes--split-stdout
                         (plist-get run :stdout)))
                 (root (satan-tools-notes--root))
                 (entries (mapcar (lambda (p)
                                    (satan-tools-notes--file-plist
                                     (satan-tools-notes--relativize p root)))
                                  paths))
                 (sorted (sort entries
                               (lambda (a b)
                                 (time-less-p (plist-get b :_sort)
                                              (plist-get a :_sort)))))
                 (capped (if (> (length sorted) limit)
                             (cl-subseq sorted 0 limit)
                           sorted))
                 (clean (mapcar #'satan-tools-notes--public capped)))
            (cons 'ok
                  (list :scope "notes_recent"
                        :root satan-tools-notes-root
                        :since-hours hours
                        :limit limit
                        :count (length clean)
                        :files clean)))))))))

;; ---------- notes_read ----------

(defun satan-tool/notes-read (args _ctx)
  "Implements notes_read.  ARGS: (:path STRING).
Returns (ok PLIST) | (error STRING).  Every refusal is an error, never an
empty success: silence would be indistinguishable from an empty note."
  (let* ((rel (plist-get args :path))
         (resolved (satan-tools-notes--resolve rel)))
    (if-let ((msg (plist-get resolved :error)))
        (cons 'error msg)
      (let ((abs (plist-get resolved :path)))
        (cond
         ((not (file-exists-p abs))
          (cons 'error (format "not found: %s" rel)))
         ((not (file-regular-p abs))
          (cons 'error (format "not a file: %s" rel)))
         (t
          (cons 'ok
                (append (list :scope "notes_read"
                              :root satan-tools-notes-root)
                        (satan-tools-notes--public
                         (satan-tools-notes--file-plist rel))
                        (satan-tools-notes--read-capped
                         abs satan-tools-notes-read-max-bytes)))))))))

;; ---------- notes_grep ----------

(defun satan-tool/notes-grep (args _ctx)
  "Implements notes_grep.  ARGS: (:query STRING :limit INT?).
Searches exactly the file set `notes_read' can open, so every hit is a hit
the caller can follow up.  Returns (ok PLIST) | (error STRING)."
  (let ((query (plist-get args :query))
        (limit (satan-tools-notes--clamp
                (plist-get args :limit)
                satan-tools-notes-default-limit
                1 satan-tools-notes--limit-max)))
    (cond
     ((not (stringp query)) (cons 'error "query must be a string"))
     ((string-empty-p query) (cons 'error "query must be non-empty"))
     (t
      (let ((root (satan-tools-notes--root))
            (program (satan-tools-notes--ensure-program
                      satan-tools-notes--rg-program)))
        (cond
         ((null root)
          (cons 'error (format "notes root not found: %s" satan-tools-notes-root)))
         ((null program)
          (cons 'error (format "%s not found on PATH" satan-tools-notes--rg-program)))
         (t
          (let* ((run (satan-tools-notes--run
                       program (satan-tools-notes--grep-argv query root)))
                 (exit (plist-get run :exit)))
            (cond
             ;; rg exits 1 on no matches: a clean empty answer, not a failure.
             ((= exit 1)
              (cons 'ok (list :scope "notes_grep"
                              :root satan-tools-notes-root
                              :query query :limit limit
                              :count 0 :truncated nil :matches '())))
             ((not (= exit 0))
              (cons 'error (satan-tools-notes--result-error "rg failed" run)))
             (t
              (let* ((all (delq nil
                                (mapcar (lambda (line)
                                          (satan-tools-notes--parse-match line root))
                                        (satan-tools-notes--split-lines
                                         (plist-get run :stdout)))))
                     (hard (cl-subseq all 0 (min (length all)
                                                 satan-tools-notes--grep-max)))
                     (shown (cl-subseq hard 0 (min (length hard) limit))))
                (cons 'ok (list :scope "notes_grep"
                                :root satan-tools-notes-root
                                :query query :limit limit
                                :count (length shown)
                                :truncated (> (length all) (length hard))
                                :matches shown)))))))))))))

;; ---------- registration ----------

(satan-tool-register
 (list :name "notes_recent"
       :risk 'read
       :args-schema '(since-hours (:type integer :required nil)
                      limit       (:type integer :required nil))
       :handler 'satan-tool/notes-recent))

(satan-tool-register
 (list :name "notes_read"
       :risk 'read
       :args-schema (list 'path (list :type 'string :required t))
       :handler 'satan-tool/notes-read))

(satan-tool-register
 (list :name "notes_grep"
       :risk 'read
       :args-schema '(query (:type string :required t)
                      limit (:type integer :required nil))
       :handler 'satan-tool/notes-grep))

(provide 'satan-tools-notes)
;;; satan-tools-notes.el ends here
