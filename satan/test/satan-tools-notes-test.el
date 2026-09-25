;;; satan-tools-notes-test.el --- ert tests for satan-tools-notes -*- lexical-binding: t; -*-

;; Run from CLI:
;;   emacs --batch \
;;     -L ~/.emacs.d/core -L ~/.emacs.d/satan -L ~/.emacs.d/satan/test \
;;     -l satan-tools-notes-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'satan-tools-notes)

(defvar satan-tools-notes-test--exec-calls nil
  "List of (PROGRAM ARGS) recorded by `satan-tools-notes-test--with-exec-stub'.")

(defvar satan-tools-notes-test--absent-programs nil
  "Program names the stub's `executable-find' must report as missing.")

(defmacro satan-tools-notes-test--with-notes-root (&rest body)
  "Bind `satan-tools-notes-root' to a temp dir for BODY."
  (declare (indent 0))
  `(let* ((dir (make-temp-file "satan-notes-" t))
          (satan-tools-notes-root dir))
     (unwind-protect (progn ,@body)
       (delete-directory dir t))))

(defmacro satan-tools-notes-test--with-exec-stub (stdout exit-code &rest body)
  "Stub `call-process' (and `executable-find') so any external probe returns
EXIT-CODE and writes STDOUT to the capture buffer.  Serves both the `fd' and
`rg' paths; records each (PROGRAM ARGS) into
`satan-tools-notes-test--exec-calls'.  `executable-find' answers present for
everything except `satan-tools-notes-test--absent-programs', so the suite does
not depend on the host having those binaries."
  (declare (indent 2))
  `(let ((satan-tools-notes-test--exec-calls nil))
     (cl-letf (((symbol-function 'executable-find)
                (lambda (name &optional _remote)
                  (unless (member name satan-tools-notes-test--absent-programs)
                    name)))
               ((symbol-function 'call-process)
                (lambda (program &optional _infile destination _display &rest args)
                  (push (cons program args) satan-tools-notes-test--exec-calls)
                  (when (and destination (not (eq destination 0)))
                    (let ((out-buf (if (consp destination) (car destination) destination)))
                      (when (bufferp out-buf)
                        (with-current-buffer out-buf
                          (insert ,stdout)))
                      (when (eq out-buf t)
                        (insert ,stdout))))
                  ,exit-code)))
       ,@body)))

(defun satan-tools-notes-test--touch (root rel &optional age-seconds)
  "Create REL under ROOT and set its mtime to now minus AGE-SECONDS (default 0)."
  (let* ((path (expand-file-name rel root))
         (parent (file-name-directory path)))
    (when parent (make-directory parent t))
    (with-temp-file path (insert ""))
    (let ((when (time-subtract (current-time) (or age-seconds 0))))
      (set-file-times path when))
    path))

(ert-deftest satan-notes/builds-correct-fd-argv ()
  "fd is invoked with --changed-after Nh, -t f, --print0, --base-directory.
No --exclude: the corpus left `~/notes' in SL-015, so there is no SATAN
subtree to hide; everything under the notes root is the user's.
--absolute-path is required because `--base-directory' makes fd print
`./'-prefixed paths, which the read door refuses as hidden components."
  (satan-tools-notes-test--with-notes-root
    (satan-tools-notes-test--with-exec-stub "" 0
      (satan-tool/notes-recent '(:since-hours 24 :limit 10) nil)
      (let* ((call (car satan-tools-notes-test--exec-calls))
             (program (car call))
             (args (cdr call)))
        (should (equal program satan-tools-notes--fd-program))
        (should (member "--changed-after" args))
        (should (member "24h" args))
        (should (member "-t" args))
        (should (member "f" args))
        (should (member "--print0" args))
        (should (member "--absolute-path" args))
        (should (member "--base-directory" args))
        (should (member satan-tools-notes-root args))
        (should-not (member "--exclude" args))))))

(ert-deftest satan-notes/expands-tilde-base-directory ()
  "A `~'-prefixed root is expanded before fd: `call-process' does no
shell tilde expansion, so a literal \"~/notes\" base-directory reaches
fd as a nonexistent path and notes_recent silently finds nothing
(SL-012 D4 regression, sibling of the @satan scan)."
  (let ((satan-tools-notes-root "~/notes-does-not-exist-xyzzy"))
    (let ((args (satan-tools-notes--build-argv 24)))
      (should (member (expand-file-name "~/notes-does-not-exist-xyzzy") args))
      (should-not (member "~/notes-does-not-exist-xyzzy" args)))))

(ert-deftest satan-notes/parses-output-and-sorts-by-mtime-desc ()
  "Returns files newer-first; relative paths; correct count."
  (satan-tools-notes-test--with-notes-root
    (satan-tools-notes-test--touch satan-tools-notes-root "old.org"    1000)
    (satan-tools-notes-test--touch satan-tools-notes-root "middle.org" 100)
    (satan-tools-notes-test--touch satan-tools-notes-root "newest.org" 1)
    (satan-tools-notes-test--with-exec-stub "old.org\0middle.org\0newest.org\0" 0
      (let* ((res (satan-tool/notes-recent '(:since-hours 24) nil))
             (p (cdr res))
             (files (plist-get p :files)))
        (should (eq (car res) 'ok))
        (should (equal (plist-get p :count) 3))
        (should (equal (mapcar (lambda (f) (plist-get f :path)) files)
                       '("newest.org" "middle.org" "old.org")))))))

(ert-deftest satan-notes/limit-default-and-clamp ()
  "Missing :limit applies default; out-of-range clamps to [1, 200]."
  (satan-tools-notes-test--with-notes-root
    (let* ((paths (cl-loop for i from 1 to 250 collect
                           (format "f%03d.org" i)))
           (stdout (mapconcat #'identity paths "\0")))
      (cl-loop for p in paths
               for age from 1
               do (satan-tools-notes-test--touch satan-tools-notes-root p age))
      (satan-tools-notes-test--with-exec-stub (concat stdout "\0") 0
        (let ((default-res (satan-tool/notes-recent '(:since-hours 24) nil))
              (hi-res (satan-tool/notes-recent '(:since-hours 24 :limit 9999) nil))
              (lo-res (satan-tool/notes-recent '(:since-hours 24 :limit 0) nil)))
          (should (equal (plist-get (cdr default-res) :limit)
                         satan-tools-notes-default-limit))
          (should (equal (plist-get (cdr hi-res) :limit)
                         satan-tools-notes--limit-max))
          (should (equal (plist-get (cdr lo-res) :limit) 1))
          (should (equal (length (plist-get (cdr hi-res) :files))
                         satan-tools-notes--limit-max)))))))

(ert-deftest satan-notes/since-hours-default-and-clamp ()
  "Missing :since-hours uses default; out-of-range clamps to [1, 720]."
  (satan-tools-notes-test--with-notes-root
    (cl-flet ((argv-has-hours (hours)
                (let* ((call (car satan-tools-notes-test--exec-calls))
                       (args (cdr call)))
                  (member (format "%dh" hours) args))))
      (satan-tools-notes-test--with-exec-stub "" 0
        (satan-tool/notes-recent nil nil)
        (should (argv-has-hours satan-tools-notes-default-hours)))
      (satan-tools-notes-test--with-exec-stub "" 0
        (satan-tool/notes-recent '(:since-hours 99999) nil)
        (should (argv-has-hours satan-tools-notes--hours-max)))
      (satan-tools-notes-test--with-exec-stub "" 0
        (satan-tool/notes-recent '(:since-hours 0) nil)
        (should (argv-has-hours 1))))))

(ert-deftest satan-notes/parses-denote-filename-metadata ()
  "Denote-style filename → :title spaces + :tags list; plain → :title nil."
  (satan-tools-notes-test--with-notes-root
    (satan-tools-notes-test--touch satan-tools-notes-root
                                      "20260520T011750--actually-learn-git-deeply__fundamentals_git_tech.org"
                                      1)
    (satan-tools-notes-test--touch satan-tools-notes-root "protocol.org" 2)
    (satan-tools-notes-test--with-exec-stub
        "20260520T011750--actually-learn-git-deeply__fundamentals_git_tech.org\0protocol.org\0"
        0
      (let* ((res (satan-tool/notes-recent '(:since-hours 24) nil))
             (files (plist-get (cdr res) :files))
             (denote (cl-find-if (lambda (f)
                                   (string-match-p "actually-learn"
                                                   (plist-get f :path)))
                                 files))
             (plain (cl-find-if (lambda (f)
                                  (equal (plist-get f :path) "protocol.org"))
                                files)))
        (should (eq (car res) 'ok))
        (should (equal (plist-get denote :title) "actually learn git deeply"))
        (should (equal (plist-get denote :tags) '("fundamentals" "git" "tech")))
        (should (equal (plist-get denote :ext) "org"))
        (should (null (plist-get plain :title)))
        (should (null (plist-get plain :tags)))
        (should (equal (plist-get plain :ext) "org"))))))

(ert-deftest satan-notes/fd-failure-returns-error ()
  "Non-zero fd exit → (error . \"fd failed: ...\")."
  (satan-tools-notes-test--with-notes-root
    (satan-tools-notes-test--with-exec-stub "" 1
      (let ((res (satan-tool/notes-recent '(:since-hours 24) nil)))
        (should (eq (car res) 'error))
        (should (string-match-p "fd failed" (cdr res)))))))

(ert-deftest satan-notes/empty-stdout-empty-files ()
  "fd returns nothing → ok with :count 0 and :files '()."
  (satan-tools-notes-test--with-notes-root
    (satan-tools-notes-test--with-exec-stub "" 0
      (let* ((res (satan-tool/notes-recent '(:since-hours 24) nil))
             (p (cdr res)))
        (should (eq (car res) 'ok))
        (should (equal (plist-get p :count) 0))
        (should (equal (plist-get p :files) '()))))))

;; ---------- registry ----------

(ert-deftest satan-notes/registry-exposes-read-and-grep ()
  "IT-001: both notes body surfaces are registered; `notes_recent' keeps its
own registered name and now routes through `satan-tool/notes-recent'."
  (should (satan-tool-lookup "notes_read"))
  (should (satan-tool-lookup "notes_grep"))
  (should (eq (plist-get (satan-tool-lookup "notes_recent") :handler)
              'satan-tool/notes-recent))
  (should (eq (plist-get (satan-tool-lookup "notes_read") :risk) 'read))
  (should (eq (plist-get (satan-tool-lookup "notes_grep") :risk) 'read)))

;; ---------- notes_read ----------

(ert-deftest satan-notes/read-returns-body-and-metadata ()
  "Body, :bytes/:total-bytes, and denote metadata round-trip."
  (satan-tools-notes-test--with-notes-root
    (let ((name "20260520T011750--actually-learn-git-deeply__fundamentals_git_tech.org")
          (body "#+title: x\nbody line\n"))
      (satan-tools-notes-test--touch satan-tools-notes-root name)
      (with-temp-file (expand-file-name name satan-tools-notes-root) (insert body))
      (let* ((res (satan-tool/notes-read (list :path name) nil))
             (p (cdr res)))
        (should (eq (car res) 'ok))
        (should (equal (plist-get p :scope) "notes_read"))
        (should (equal (plist-get p :path) name))
        (should (equal (plist-get p :body) body))
        (should (equal (plist-get p :title) "actually learn git deeply"))
        (should (equal (plist-get p :tags) '("fundamentals" "git" "tech")))
        (should (equal (plist-get p :ext) "org"))
        (should (equal (plist-get p :bytes) (string-bytes body)))
        (should (equal (plist-get p :total-bytes) (string-bytes body)))
        (should (equal (plist-get p :truncated) nil))
        (should (stringp (plist-get p :mtime)))
        ;; `:_sort' is an Emacs time object: notes_recent's sorting key, never
        ;; part of the result.  The wire layer can only render it as a
        ;; meaningless array, so it must not survive the handler.
        (should-not (plist-member p :_sort))))))

(ert-deftest satan-notes/recent-paths-round-trip-through-read ()
  "Every :path notes_recent returns is one notes_read accepts.
The unit stubs used to emit bare names, which is not what fd prints: with
`--base-directory' fd emits `./'-prefixed paths, and `--resolve' refuses a
leading-dot component — so the round trip failed live while the suite stayed
green.  The stub here emits what fd emits (absolute, via --absolute-path)."
  (satan-tools-notes-test--with-notes-root
    (let ((rel "journal/2026-09-25--protocol.org"))
      (satan-tools-notes-test--touch satan-tools-notes-root rel)
      (satan-tools-notes-test--with-exec-stub
          (concat (expand-file-name rel satan-tools-notes-root) "\0") 0
        (let* ((recent (satan-tool/notes-recent '(:since-hours 24) nil))
               (path (plist-get (car (plist-get (cdr recent) :files)) :path))
               (read (satan-tool/notes-read (list :path path) nil)))
          (should (equal path rel))
          (should (eq (car read) 'ok))
          (should (equal (plist-get (cdr read) :path) rel)))))))

(ert-deftest satan-notes/read-titles-only-date-prefixed-names ()
  "A plain name yields :title nil — the reused parser's actual behaviour."
  (satan-tools-notes-test--with-notes-root
    (satan-tools-notes-test--touch satan-tools-notes-root "protocol.org")
    (let* ((res (satan-tool/notes-read '(:path "protocol.org") nil))
           (p (cdr res)))
      (should (eq (car res) 'ok))
      (should (equal (plist-get p :body) ""))
      (should (null (plist-get p :title)))
      (should (null (plist-get p :tags)))
      (should (equal (plist-get p :ext) "org")))))

(ert-deftest satan-notes/read-accepts-nested-and-plain-relative-paths ()
  (satan-tools-notes-test--with-notes-root
    (satan-tools-notes-test--touch satan-tools-notes-root "journal/protocol.org")
    (satan-tools-notes-test--touch satan-tools-notes-root "top.md")
    (should (eq (car (satan-tool/notes-read '(:path "journal/protocol.org") nil)) 'ok))
    (should (eq (car (satan-tool/notes-read '(:path "top.md") nil)) 'ok))))

(ert-deftest satan-notes/read-refuses-paths-escaping-the-root ()
  "Absolute paths, `..' components, empty and wrong-type paths are refused."
  (satan-tools-notes-test--with-notes-root
    (dolist (bad (list "/etc/passwd" "../secrets" "journal/../../etc/passwd"
                       ".." "" 42))
      (let ((res (satan-tool/notes-read (list :path bad) nil)))
        (should (eq (car res) 'error))))))

(ert-deftest satan-notes/read-refuses-a-symlink-escaping-the-root ()
  "A symlink inside the root pointing outside it is the only case that
exercises truename containment: a string check alone would let it through."
  (satan-tools-notes-test--with-notes-root
    (let* ((outside (make-temp-file "satan-outside-" nil ".org"))
           (link (expand-file-name "escape.org" satan-tools-notes-root)))
      (unwind-protect
          (progn
            (with-temp-file outside (insert "not yours\n"))
            (make-symbolic-link outside link)
            (let ((res (satan-tool/notes-read '(:path "escape.org") nil)))
              (should (eq (car res) 'error))
              (should (string-match-p "escapes notes root" (cdr res)))))
        (delete-file link)
        (delete-file outside)))))

(ert-deftest satan-notes/read-refuses-the-root-and-a-directory ()
  "The root is not covered by containment (a directory is inside itself):
it is refused as a non-file, and `.` as hidden material."
  (satan-tools-notes-test--with-notes-root
    (make-directory (expand-file-name "adir" satan-tools-notes-root) t)
    (let ((dir (satan-tool/notes-read '(:path "adir") nil))
          (dot (satan-tool/notes-read '(:path ".") nil))
          (slash (satan-tool/notes-read '(:path "adir/") nil)))
      (should (eq (car dir) 'error))
      (should (string-match-p "not a file" (cdr dir)))
      (should (eq (car dot) 'error))
      (should (string-match-p "hidden" (cdr dot)))
      (should (eq (car slash) 'error)))))

(ert-deftest satan-notes/read-refuses-non-note-and-hidden-paths ()
  "DEC-032: only .org/.md/.txt, never a hidden component."
  (satan-tools-notes-test--with-notes-root
    (dolist (name (list "script.sh" "data.json" "noext" ".env"))
      (satan-tools-notes-test--touch satan-tools-notes-root name))
    (satan-tools-notes-test--touch satan-tools-notes-root ".dir/note.org")
    (dolist (name (list "script.sh" "data.json" "noext" ".env" ".dir/note.org"))
      (let ((res (satan-tool/notes-read (list :path name) nil)))
        (should (eq (car res) 'error))))
    ;; and the case-insensitive acceptance of a real extension
    (satan-tools-notes-test--touch satan-tools-notes-root "SHOUT.ORG")
    (should (eq (car (satan-tool/notes-read '(:path "SHOUT.ORG") nil)) 'ok))))

(ert-deftest satan-notes/read-errors-on-missing-file ()
  (satan-tools-notes-test--with-notes-root
    (let ((res (satan-tool/notes-read '(:path "nope.org") nil)))
      (should (eq (car res) 'error))
      (should (string-match-p "not found" (cdr res))))))

(ert-deftest satan-notes/read-truncates-at-cap ()
  "A byte cap that flags itself, and reports how much is not being seen."
  (satan-tools-notes-test--with-notes-root
    (let ((satan-tools-notes-read-max-bytes 10))
      (satan-tools-notes-test--touch satan-tools-notes-root "big.org")
      (with-temp-file (expand-file-name "big.org" satan-tools-notes-root)
        (insert "0123456789abcdefghij"))
      (let* ((res (satan-tool/notes-read '(:path "big.org") nil))
             (p (cdr res)))
        (should (eq (car res) 'ok))
        (should (equal (plist-get p :body) "0123456789"))
        (should (equal (plist-get p :bytes) 10))
        (should (equal (plist-get p :total-bytes) 20))
        (should (eq (plist-get p :truncated) t))))))

(ert-deftest satan-notes/read-errors-when-notes-root-is-absent ()
  "An unreachable corpus is named as such, not reported as a path escape."
  (let ((satan-tools-notes-root "/nonexistent-satan-notes-root-xyzzy"))
    (let ((res (satan-tool/notes-read '(:path "note.org") nil)))
      (should (eq (car res) 'error))
      (should (string-match-p "notes root not found" (cdr res))))))

;; ---------- notes_grep ----------

(ert-deftest satan-notes/grep-parses-matches-into-relative-paths ()
  "Globs are derived from the extension list, the search is literal and
case-insensitive, and paths come back relative to the root."
  (satan-tools-notes-test--with-notes-root
    (let ((root (expand-file-name satan-tools-notes-root)))
      (satan-tools-notes-test--with-exec-stub
          (concat root "/journal/a.org:3:first hit\n"
                  root "/protocol.org:12:second hit\n")
          0
        (let* ((res (satan-tool/notes-grep '(:query "hit") nil))
               (p (cdr res))
               (matches (plist-get p :matches)))
          (should (eq (car res) 'ok))
          (should (equal (plist-get p :scope) "notes_grep"))
          (should (equal (plist-get p :query) "hit"))
          (should (equal (plist-get p :count) 2))
          (should (equal (plist-get p :truncated) nil))
          (should (equal (mapcar (lambda (m) (plist-get m :path)) matches)
                         '("journal/a.org" "protocol.org")))
          (should (equal (plist-get (car matches) :line) 3))
          (should (equal (plist-get (car matches) :text) "first hit"))
          (let* ((call (car satan-tools-notes-test--exec-calls))
                 (args (cdr call)))
            (should (equal (car call) satan-tools-notes--rg-program))
            (should (member "--ignore-case" args))
            (should (member "--fixed-strings" args))
            (should (member "--max-columns-preview" args))
            (should-not (member "--max-count" args))
            ;; the root is handed to rg in directory form, which is also the
            ;; prefix `--relativize' strips
            (should (member (file-name-as-directory root) args))
            ;; one --glob per openable extension, derived not restated
            (dolist (ext satan-tools-notes--openable-extensions)
              (should (member (concat "*." ext) args)))))))))

(ert-deftest satan-notes/grep-does-not-cap-matches-per-file ()
  "15 hits in one file are 15 matches: there is no silent per-file cap."
  (satan-tools-notes-test--with-notes-root
    (let* ((root (expand-file-name satan-tools-notes-root))
           (lines (mapconcat (lambda (i)
                               (format "%s/one.org:%d:hit %d" root i i))
                             (number-sequence 1 15) "\n")))
      (satan-tools-notes-test--with-exec-stub (concat lines "\n") 0
        (let* ((res (satan-tool/notes-grep '(:query "hit" :limit 200) nil))
               (p (cdr res)))
          (should (eq (car res) 'ok))
          (should (equal (plist-get p :count) 15))
          (should (equal (plist-get p :truncated) nil)))))))

(ert-deftest satan-notes/grep-no-matches-is-ok ()
  "rg exits 1 on no matches — an empty result, not a failure."
  (satan-tools-notes-test--with-notes-root
    (satan-tools-notes-test--with-exec-stub "" 1
      (let* ((res (satan-tool/notes-grep '(:query "zzz") nil))
             (p (cdr res)))
        (should (eq (car res) 'ok))
        (should (equal (plist-get p :count) 0))
        (should (equal (plist-get p :matches) '()))))))

(ert-deftest satan-notes/grep-errors-on-rg-failure ()
  (satan-tools-notes-test--with-notes-root
    (satan-tools-notes-test--with-exec-stub "" 2
      (let ((res (satan-tool/notes-grep '(:query "x") nil)))
        (should (eq (car res) 'error))
        (should (string-match-p "rg failed" (cdr res)))))))

(ert-deftest satan-notes/grep-errors-when-rg-is-absent ()
  "DEC-030: an unavailable probe is an error with the module's own message,
never an empty result."
  (satan-tools-notes-test--with-notes-root
    (satan-tools-notes-test--with-exec-stub "" 1
      (let ((satan-tools-notes-test--absent-programs '("rg")))
        (let ((res (satan-tool/notes-grep '(:query "x") nil)))
          (should (eq (car res) 'error))
          (should (string-match-p "not found on PATH" (cdr res))))))))

(ert-deftest satan-notes/grep-errors-when-notes-root-is-absent ()
  (let ((satan-tools-notes-root "/nonexistent-satan-notes-root-xyzzy"))
    (satan-tools-notes-test--with-exec-stub "" 0
      (let ((res (satan-tool/notes-grep '(:query "x") nil)))
        (should (eq (car res) 'error))
        (should (string-match-p "notes root not found" (cdr res)))))))

(ert-deftest satan-notes/grep-caps-total-matches ()
  (satan-tools-notes-test--with-notes-root
    (let* ((root (expand-file-name satan-tools-notes-root))
           (lines (mapconcat (lambda (i) (format "%s/f.org:%d:hit %d" root i i))
                             (number-sequence 1 60) "\n")))
      (satan-tools-notes-test--with-exec-stub (concat lines "\n") 0
        (let* ((res (satan-tool/notes-grep '(:query "hit" :limit 200) nil))
               (p (cdr res)))
          (should (eq (car res) 'ok))
          (should (equal (plist-get p :count) satan-tools-notes--grep-max))
          (should (eq (plist-get p :truncated) t)))))))

(ert-deftest satan-notes/grep-requires-a-query ()
  (satan-tools-notes-test--with-notes-root
    (should (eq (car (satan-tool/notes-grep nil nil)) 'error))
    (should (eq (car (satan-tool/notes-grep '(:query "") nil)) 'error))
    (should (eq (car (satan-tool/notes-grep '(:query 42) nil)) 'error))))

(provide 'satan-tools-notes-test)
;;; satan-tools-notes-test.el ends here
