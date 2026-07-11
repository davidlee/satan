;;; satan-tools-notes-test.el --- ert tests for satan-tools-notes -*- lexical-binding: t; -*-

;; Run from CLI:
;;   emacs --batch \
;;     -L ~/.emacs.d/core -L ~/.emacs.d/satan -L ~/.emacs.d/satan/test \
;;     -l satan-tools-notes-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'satan-tools-notes)

(defvar satan-tools-notes-test--fd-calls nil
  "List of (PROGRAM ARGS) recorded by `satan-tools-notes-test--with-fd-stub'.")

(defmacro satan-tools-notes-test--with-notes-root (&rest body)
  "Bind `satan-tools-notes-root' to a temp dir for BODY."
  (declare (indent 0))
  `(let* ((dir (make-temp-file "satan-notes-" t))
          (satan-tools-notes-root dir))
     (unwind-protect (progn ,@body)
       (delete-directory dir t))))

(defmacro satan-tools-notes-test--with-fd-stub (stdout exit-code &rest body)
  "Stub `call-process' so that calls to `satan-tools-notes--fd-program'
return EXIT-CODE and write STDOUT to the capture buffer.  Records each call
into `satan-tools-notes-test--fd-calls'."
  (declare (indent 2))
  `(let ((satan-tools-notes-test--fd-calls nil))
     (cl-letf (((symbol-function 'call-process)
                (lambda (program &optional _infile destination _display &rest args)
                  (push (cons program args) satan-tools-notes-test--fd-calls)
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
  "fd is invoked with --changed-after Nh, -t f, --print0, --base-directory, --exclude satan."
  (satan-tools-notes-test--with-notes-root
    (satan-tools-notes-test--with-fd-stub "" 0
      (satan-tool/notes-read '(:since-hours 24 :limit 10) nil)
      (let* ((call (car satan-tools-notes-test--fd-calls))
             (program (car call))
             (args (cdr call)))
        (should (equal program satan-tools-notes--fd-program))
        (should (member "--changed-after" args))
        (should (member "24h" args))
        (should (member "-t" args))
        (should (member "f" args))
        (should (member "--print0" args))
        (should (member "--base-directory" args))
        (should (member satan-tools-notes-root args))
        (should (member "--exclude" args))
        (should (member "satan" args))))))

(ert-deftest satan-notes/parses-output-and-sorts-by-mtime-desc ()
  "Returns files newer-first; relative paths; correct count."
  (satan-tools-notes-test--with-notes-root
    (satan-tools-notes-test--touch satan-tools-notes-root "old.org"    1000)
    (satan-tools-notes-test--touch satan-tools-notes-root "middle.org" 100)
    (satan-tools-notes-test--touch satan-tools-notes-root "newest.org" 1)
    (satan-tools-notes-test--with-fd-stub "old.org\0middle.org\0newest.org\0" 0
      (let* ((res (satan-tool/notes-read '(:since-hours 24) nil))
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
      (satan-tools-notes-test--with-fd-stub (concat stdout "\0") 0
        (let ((default-res (satan-tool/notes-read '(:since-hours 24) nil))
              (hi-res (satan-tool/notes-read '(:since-hours 24 :limit 9999) nil))
              (lo-res (satan-tool/notes-read '(:since-hours 24 :limit 0) nil)))
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
                (let* ((call (car satan-tools-notes-test--fd-calls))
                       (args (cdr call)))
                  (member (format "%dh" hours) args))))
      (satan-tools-notes-test--with-fd-stub "" 0
        (satan-tool/notes-read nil nil)
        (should (argv-has-hours satan-tools-notes-default-hours)))
      (satan-tools-notes-test--with-fd-stub "" 0
        (satan-tool/notes-read '(:since-hours 99999) nil)
        (should (argv-has-hours satan-tools-notes--hours-max)))
      (satan-tools-notes-test--with-fd-stub "" 0
        (satan-tool/notes-read '(:since-hours 0) nil)
        (should (argv-has-hours 1))))))

(ert-deftest satan-notes/parses-denote-filename-metadata ()
  "Denote-style filename → :title spaces + :tags list; plain → :title nil."
  (satan-tools-notes-test--with-notes-root
    (satan-tools-notes-test--touch satan-tools-notes-root
                                      "20260520T011750--actually-learn-git-deeply__fundamentals_git_tech.org"
                                      1)
    (satan-tools-notes-test--touch satan-tools-notes-root "protocol.org" 2)
    (satan-tools-notes-test--with-fd-stub
        "20260520T011750--actually-learn-git-deeply__fundamentals_git_tech.org\0protocol.org\0"
        0
      (let* ((res (satan-tool/notes-read '(:since-hours 24) nil))
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
    (satan-tools-notes-test--with-fd-stub "" 1
      (let ((res (satan-tool/notes-read '(:since-hours 24) nil)))
        (should (eq (car res) 'error))
        (should (string-match-p "fd failed" (cdr res)))))))

(ert-deftest satan-notes/empty-stdout-empty-files ()
  "fd returns nothing → ok with :count 0 and :files '()."
  (satan-tools-notes-test--with-notes-root
    (satan-tools-notes-test--with-fd-stub "" 0
      (let* ((res (satan-tool/notes-read '(:since-hours 24) nil))
             (p (cdr res)))
        (should (eq (car res) 'ok))
        (should (equal (plist-get p :count) 0))
        (should (equal (plist-get p :files) '()))))))

(provide 'satan-tools-notes-test)
;;; satan-tools-notes-test.el ends here
