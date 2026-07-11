;;; satan-memory.el --- SATAN memory substrate aggregator -*- lexical-binding: t; -*-

;; Single entry point for the canonical-handle memory substrate.  Pulls
;; in the five `satan-memory-*' submodules + the two tool modules
;; (`satan-tools-memory', `satan-tools-bough') and exposes a small
;; `satan-memory-*' interactive surface for inspecting the store from
;; Emacs.  See `~/.emacs.d/satan/memory.design.md' §11.

(require 'cl-lib)
(require 'satan-memory-grammar)
(require 'satan-memory-canon)
(require 'satan-memory-evidence)
(require 'satan-memory-store)
(require 'satan-memory-migrate)
(require 'satan-tools-bough)
(require 'satan-tools-memory)

(defun satan-memory--recent-rows (limit)
  "Return recent trace rows or signal on store error."
  (pcase (satan-memory-store-recent :limit limit)
    (`(ok . ,rows) rows)
    (`(error . ,msg) (error "recent failed: %s" msg))))

(defun satan-memory--read-trace-id (prompt &optional limit)
  "Read a trace id via `completing-read' over recent traces.
LIMIT bounds the candidate pool (default 50).  Falls back to plain
`read-string' when no recent traces exist."
  (let* ((rows (satan-memory--recent-rows (or limit 50)))
         (by-id (make-hash-table :test 'equal))
         (cands (mapcar (lambda (r)
                          (let ((id (plist-get r :trace_id)))
                            (puthash id r by-id)
                            id))
                        rows)))
    (if (null cands)
        (read-string prompt)
      (let* ((annotate
              (lambda (id)
                (when-let* ((row (gethash id by-id)))
                  (format "  %-18s  %s  %s"
                          (plist-get row :kind)
                          (plist-get row :observed_end_at)
                          (plist-get row :payload)))))
             (completion-extra-properties
              (list :annotation-function annotate)))
        (completing-read prompt cands nil nil nil nil (car cands))))))

(defconst satan-memory-list--payload-preview-width 120
  "Column width for the PAYLOAD preview in `satan-memory-list'.
The store returns full payloads; this only caps the single-line
table display.  Use `satan-memory-show' for the full body.")

(defun satan-memory-list (&optional limit)
  "List the LIMIT most recent traces (default 20) into `*satan-memory*'.
With a prefix arg, use its numeric value as LIMIT.  Payload is
shown as a single-line preview; `satan-memory-show' on the row
yields the full text."
  (interactive (list (if current-prefix-arg
                         (prefix-numeric-value current-prefix-arg)
                       20)))
  (let ((rows (satan-memory--recent-rows limit))
        (buf (get-buffer-create "*satan-memory*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (special-mode)
        (insert (format "recent: %d\n\n" (length rows)))
        (if (null rows)
            (insert "(no traces)\n")
          (insert (format "%-36s  %-18s  %-20s  %s\n"
                          "TRACE-ID" "KIND" "OBSERVED" "PAYLOAD"))
          (dolist (row rows)
            (insert (format "%-36s  %-18s  %-20s  %s\n"
                            (plist-get row :trace_id)
                            (plist-get row :kind)
                            (plist-get row :observed_end_at)
                            (truncate-string-to-width
                             (or (plist-get row :payload) "")
                             satan-memory-list--payload-preview-width
                             nil nil "…")))))))
    (pop-to-buffer buf)))

(defun satan-memory-resonate (handles)
  "Resonate against HANDLES (whitespace-separated minibuffer input).
Pop a `*satan-memory*' buffer listing the top matches as
TRACE-ID  SCORE  MATCHED-HANDLES."
  (interactive (list (split-string (read-string "Cue handles: "))))
  (pcase (satan-memory-store-resonate :cue-handles handles)
    (`(ok . ,rows)
     (let ((buf (get-buffer-create "*satan-memory*")))
       (with-current-buffer buf
         (let ((inhibit-read-only t))
           (erase-buffer)
           (special-mode)
           (insert (format "resonate: %s\n\n" (string-join handles " ")))
           (if (null rows)
               (insert "(no matches)\n")
             (dolist (row rows)
               (insert (format "%s  %.3f  %s\n"
                               (plist-get row :trace_id)
                               (plist-get row :score)
                               (string-join (plist-get row :matched_handles)
                                            " ")))))))
       (pop-to-buffer buf)))
    (`(error . ,msg) (error "resonate failed: %s" msg))))

(defun satan-memory-show (trace-id)
  "Pretty-print the trace identified by TRACE-ID into `*satan-memory*'.
Interactively, completes against the most recent traces."
  (interactive (list (satan-memory--read-trace-id "Trace id: ")))
  (pcase (satan-memory-store-show trace-id)
    (`(ok . nil) (message "no trace: %s" trace-id))
    (`(ok . ,row)
     (let ((buf (get-buffer-create "*satan-memory*")))
       (with-current-buffer buf
         (let ((inhibit-read-only t))
           (erase-buffer)
           (special-mode)
           (insert (pp-to-string row))))
       (pop-to-buffer buf)))
    (`(error . ,msg) (error "show failed: %s" msg))))

(defun satan-memory-status ()
  "Report substrate status: grammar version + migration applied/pending."
  (interactive)
  (let* ((rows (satan-memory-migrate-status))
         (by-status (lambda (s) (cl-count-if (lambda (r)
                                               (eq (plist-get r :status) s))
                                             rows))))
    (message
     "memory: db=%s grammar=v%d migrations=%d applied, %d pending, %d tampered, %d missing"
     satan-memory-store-database
     satan-memory-grammar-current-version
     (funcall by-status 'applied)
     (funcall by-status 'pending)
     (funcall by-status 'tampered)
     (funcall by-status 'missing))))

(provide 'satan-memory)
;;; satan-memory.el ends here
