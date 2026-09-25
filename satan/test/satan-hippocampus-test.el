;;; satan-hippocampus-test.el --- hippocampus data + capsule block -*- lexical-binding: t; -*-

;; `satan-hippocampus` owns the hippocampus as data: listing named org
;; files and rendering a titles-only block into the context capsule.
;; The tool handlers (`satan-tools-hippocampus`) delegate listing here,
;; and `satan-context--render-prompt` consumes the block.
;;
;; All tests are filesystem-only (no DB) so they always run.

(require 'ert)
(require 'cl-lib)
(require 'satan-hippocampus)

(defmacro satan-hippocampus-test--with-dir (files &rest body)
  "Bind `satan-hippocampus-dir' to a temp dir holding FILES.
FILES is a list of org basenames to create, in creation order."
  (declare (indent 1))
  `(let* ((dir (make-temp-file "satan-hippocampus-" t))
          (satan-hippocampus-dir dir))
     (unwind-protect
         (progn
           (dolist (f ,files)
             (with-temp-file (expand-file-name f dir) (insert "body")))
           ,@body)
       (delete-directory dir t))))

(defconst satan-hippocampus-test--a
  "20260601T000000--alpha__satan_hippocampus.org")
(defconst satan-hippocampus-test--b
  "20260602T000000--bravo__satan_hippocampus.org")
(defconst satan-hippocampus-test--c
  "20260603T000000--charlie__satan_hippocampus.org")

(ert-deftest satan-hippocampus/entries/empty-when-dir-absent ()
  (let ((satan-hippocampus-dir "/tmp/satan-hippocampus-does-not-exist-XYZ"))
    (should (null (satan-hippocampus-entries)))))

(ert-deftest satan-hippocampus/entries/newest-first-with-titles ()
  (satan-hippocampus-test--with-dir (list satan-hippocampus-test--a
                                         satan-hippocampus-test--b)
    (let ((entries (satan-hippocampus-entries)))
      (should (= 2 (length entries)))
      (should (equal "bravo" (plist-get (car entries) :title)))
      (should (equal "alpha" (plist-get (cadr entries) :title))))))

(ert-deftest satan-hippocampus/render-block/nil-without-header ()
  (satan-hippocampus-test--with-dir (list satan-hippocampus-test--a)
    (should (null (satan-hippocampus-render-block
                   '(("now" . "# Now")) (satan-hippocampus-entries))))))

(ert-deftest satan-hippocampus/render-block/nil-when-no-entries ()
  (let ((framing '(("hippocampus_block_header" . "# Hippocampus"))))
    (should (null (satan-hippocampus-render-block framing nil)))
    (should (null (satan-hippocampus-render-block framing '())))))

(ert-deftest satan-hippocampus/render-block/titles-newest-first ()
  (satan-hippocampus-test--with-dir (list satan-hippocampus-test--a
                                         satan-hippocampus-test--b)
    (let* ((framing '(("hippocampus_block_header" . "# Hippocampus")))
           (block (satan-hippocampus-render-block
                   framing (satan-hippocampus-entries))))
      (should (equal "# Hippocampus" (car block)))
      (should (= 3 (length block)))
      (should (equal "- [2026-06-02] bravo" (cadr block)))
      (should (equal "- [2026-06-01] alpha" (caddr block))))))

(ert-deftest satan-hippocampus/render-block/caps-at-limit ()
  (satan-hippocampus-test--with-dir (list satan-hippocampus-test--a
                                         satan-hippocampus-test--b
                                         satan-hippocampus-test--c)
    (let* ((framing '(("hippocampus_block_header" . "# Hippocampus")))
           (block (satan-hippocampus-render-block
                   framing (satan-hippocampus-entries) 2)))
      ;; header + 2 capped entries, newest kept
      (should (= 3 (length block)))
      (should (equal "- [2026-06-03] charlie" (cadr block)))
      (should (equal "- [2026-06-02] bravo" (caddr block))))))

(provide 'satan-hippocampus-test)
;;; satan-hippocampus-test.el ends here
