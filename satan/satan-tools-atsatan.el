;;; satan-tools-atsatan.el --- @satan scan + done tool handlers -*- lexical-binding: t; -*-

;; Scans ~/notes/ for @satan references and returns excerpts with
;; context (`notes_at_satan_scan'); marks a directive done by replacing
;; the @satan token with @satan-was-here on its line and appending a
;; quoted block containing run-id + summary (`notes_at_satan_done').
;;
;; Render shape (org files):
;;
;;   @satan-was-here <preserved trailing text>
;;   #+BEGIN_QUOTE satan <run-id>[,<tag>]
;;   <body>
;;   #+END_QUOTE
;;
;; Render shape (markdown files): a `> ' blockquote in place of the org
;; quote block, same header + body lines.
;;
;; The optional `<tag>' is the part of the `comment' arg before the
;; first colon; the body is the remainder. A comment with no colon
;; renders header-only (run-id) plus the whole comment as body.
;;
;; Risk model:
;;   - notes_at_satan_scan : risk read; no capability required.
;;   - notes_at_satan_done : risk low;  requires 'write-notes capability.

(require 'cl-lib)
(require 'subr-x)
(require 'json)
(require 'satan-custom)
(require 'satan-tools)
(require 'satan-intervention)      ; manual-outcome writer (T1.5b PR 4)
(require 'satan-audit)              ; audit-reopen (T1.5b PR 4)
(require 'satan-observer-classify) ; --maturity-state (T1.5b PR 4)

;; Broker is soft — `satan-broker-locate-run-dir' / `satan-runs-dir'
;; are available inside the live emacs daemon; requiring `satan-broker'
;; here pulls a heavy dep chain (denote / org-tools) into ert batch runs.
(declare-function satan-broker-locate-run-dir "satan-broker")

(defcustom satan-tools-atsatan-root
  satan-notes-root
  "Root directory the @satan scan searches under."
  :type 'directory :group 'satan)

(defcustom satan-tools-atsatan-default-context-lines 3
  "Default lines of context above and below each @satan match."
  :type 'integer :group 'satan)

(defconst satan-tools-atsatan--context-max 20
  "Hard upper bound on context lines; clamped without error.")

(defconst satan-tools-atsatan--results-max 200
  "Hard upper bound on results returned in a single scan.")

(defconst satan-tools-atsatan--exclude-globs
  '("!**/satan/**")
  "Glob exclusions passed to rg as repeated --glob flags.
`!satan/**' alone does not exclude when rg traverses an absolute root
— rg matches globs against the full path. `!**/satan/**' excludes
any `satan/' subtree regardless of depth.")

(defconst satan-tools-atsatan--default-path-glob "*.{org,md}"
  "Default rg glob for files to scan.")

(defconst satan-tools-atsatan--mark "@satan"
  "Substring matching an active @satan directive.")

(defconst satan-tools-atsatan--intervention-mark-re
  "@satan-intervention-\\(?:harmful\\|contradicted\\)"
  "Regex matching an active @satan-intervention-{harmful|contradicted}
directive prefix (T1.5b PR 4, outcome-semantics §7.2).  Distinct from
the bare `@satan' mark so the rewriter replaces the longer prefix
atomically instead of corrupting `@satan-intervention-harmful' into
`@satan-was-here-intervention-harmful'.")

(defconst satan-tools-atsatan--claimed-re
  "@satan-\\(?:was-here\\|done\\)\\b"
  "Regex marking a claimed @satan line; excluded from scan results.
Lines bearing this marker were processed by a prior run and are
followed by a quoted summary block.  The `@satan-done' alternative
is the legacy claim token used before the rename to
`@satan-was-here'; kept here so historical claims in existing notes
stay filtered.")

(defconst satan-tools-atsatan--headline-re
  "^\\(\\*+\\|#+\\) "
  "Org-or-markdown heading line; walked backward from each match.")

(defvar satan-tools-atsatan--rg-program "rg"
  "Name (or absolute path) of the ripgrep binary. Overridable for tests.")

(defvar satan-tools-atsatan--id-index (make-hash-table :test 'equal)
  "Maps :id → (FILE . LINE) within a single Emacs session.
Populated by the scan handler so the done handler does not need to
re-scan to resolve an id.")

(defun satan-tools-atsatan--clamp (raw default min max)
  (cond ((null raw) default)
        ((< raw min) min)
        ((> raw max) max)
        (t raw)))

(defun satan-tools-atsatan--hash (file line)
  "Stable id for a (FILE . LINE) pair within a single scan cycle.
Hash shifts if lines above the match are inserted/deleted, so callers
must round-trip the id within one scan-then-done cycle."
  (concat "M-" (substring (secure-hash 'md5 (format "%s:%d" file line)) 0 12)))

(defun satan-tools-atsatan--remember (matches)
  "Store FILE/LINE for each match's id in the session index."
  (dolist (m matches)
    (puthash (plist-get m :id)
             (cons (plist-get m :file) (plist-get m :line))
             satan-tools-atsatan--id-index)))

(defun satan-tools-atsatan--split-comment (comment)
  "Split COMMENT into (TAG . BODY) on the first colon.
TAG is the trimmed substring before `:'; BODY is the trimmed remainder.
A comment with no colon yields (nil . trimmed-COMMENT).  An empty
or all-whitespace COMMENT yields (nil . nil).  Newlines in either
half collapse to single spaces."
  (let ((c (and comment
                (replace-regexp-in-string "[\n\r]+" " " comment))))
    (cond
     ((or (null c) (string-empty-p (string-trim c)))
      (cons nil nil))
     ((string-match "\\`\\([^:]+\\):\\(.*\\)\\'" c)
      (let ((tag  (string-trim (match-string 1 c)))
            (body (string-trim (match-string 2 c))))
        (cons (if (string-empty-p tag) nil tag)
              (if (string-empty-p body) nil body))))
     (t (cons nil (string-trim c))))))

(defun satan-tools-atsatan--render-block (file run-id comment)
  "Return the claim block for FILE as a list of strings (one per line).
RUN-ID identifies the producing tick; COMMENT is the model's summary,
split into TAG/BODY by `satan-tools-atsatan--split-comment'.
Org files render an `#+BEGIN_QUOTE'/`#+END_QUOTE' pair; markdown files
render a `> '-prefixed blockquote."
  (let* ((ext   (downcase (or (file-name-extension file) "")))
         (md    (equal ext "md"))
         (split (satan-tools-atsatan--split-comment comment))
         (tag   (car split))
         (body  (cdr split))
         (header (concat "satan " (or run-id "")
                         (if tag (concat "," tag) ""))))
    (if md
        (append (list (concat "> " header))
                (and body (list (concat "> " body))))
      (append (list (concat "#+BEGIN_QUOTE " header))
              (and body (list body))
              (list "#+END_QUOTE")))))

(defun satan-tools-atsatan--rg-argv (max-results path-glob)
  (let ((argv (list "--json" "-n" "--fixed-strings"
                    "--max-count" (number-to-string max-results)
                    "--glob" path-glob)))
    (dolist (g satan-tools-atsatan--exclude-globs)
      (setq argv (append argv (list "--glob" g))))
    ;; `call-process' performs no shell tilde expansion, so a literal
    ;; "~/notes" root would reach rg as a nonexistent path.  Expand here
    ;; (the sole call-process boundary) so absolute match paths flow
    ;; through enrich/done downstream.
    (append argv
            (list satan-tools-atsatan--mark
                  (expand-file-name satan-tools-atsatan-root)))))

(defun satan-tools-atsatan--run-rg (argv)
  "Invoke rg with ARGV. Returns (:exit N :stdout STR :stderr STR)."
  (let ((stdout-buf (generate-new-buffer " *satan-atsatan-rg-out*"))
        (stderr-file (make-temp-file "satan-atsatan-rg-err-")))
    (unwind-protect
        (let ((exit (apply #'call-process
                           satan-tools-atsatan--rg-program nil
                           (list stdout-buf stderr-file) nil argv)))
          (list :exit exit
                :stdout (with-current-buffer stdout-buf (buffer-string))
                :stderr (with-temp-buffer
                          (when (file-readable-p stderr-file)
                            (insert-file-contents stderr-file))
                          (buffer-string))))
      (when (buffer-live-p stdout-buf) (kill-buffer stdout-buf))
      (when (file-exists-p stderr-file) (delete-file stderr-file)))))

(defun satan-tools-atsatan--parse-matches (stdout)
  "Parse rg --json STDOUT into a list of (:file :line :content) plists.
Skips non-match records and lines bearing the claimed marker."
  (let (out)
    (dolist (raw (split-string stdout "\n" t))
      (let* ((rec (ignore-errors
                    (json-parse-string raw :object-type 'plist
                                       :array-type 'list
                                       :null-object nil)))
             (type (and rec (plist-get rec :type)))
             (data (and rec (plist-get rec :data))))
        (when (and (equal type "match") data)
          (let* ((path (plist-get (plist-get data :path) :text))
                 (line (plist-get data :line_number))
                 (text (plist-get (plist-get data :lines) :text))
                 (content (and text (string-trim-right text))))
            (when (and path line content
                       (not (string-match-p satan-tools-atsatan--claimed-re
                                            content)))
              (push (list :file path :line line :content content)
                    out))))))
    (nreverse out)))

(defun satan-tools-atsatan--enrich (matches context-lines)
  "Add :context, :headline, :mtime, :id to each match plist.
Opens each unique file once; reads lines into a vector for slicing."
  (let ((cache (make-hash-table :test 'equal)))
    (mapcar
     (lambda (m)
       (let* ((file  (plist-get m :file))
              (line  (plist-get m :line))
              (lines (or (gethash file cache)
                         (puthash file
                                  (with-temp-buffer
                                    (let ((coding-system-for-read 'utf-8))
                                      (insert-file-contents file))
                                    (vconcat (split-string (buffer-string) "\n")))
                                  cache)))
              (n     (length lines))
              (idx   (1- line))
              (lo    (max 0 (- idx context-lines)))
              (hi    (min (1- n) (+ idx context-lines)))
              (window (cl-loop for i from lo to hi
                               collect (aref lines i)))
              (headline (cl-loop for i from (1- idx) downto 0
                                 for ln = (aref lines i)
                                 when (string-match-p
                                       satan-tools-atsatan--headline-re ln)
                                 return ln))
              (mtime (format-time-string
                      "%Y-%m-%dT%H:%M:%S%z"
                      (file-attribute-modification-time
                       (file-attributes file)))))
         (append m
                 (list :context (mapconcat #'identity window "\n")
                       :headline headline
                       :mtime mtime
                       :id (satan-tools-atsatan--hash file line)))))
     matches)))

(defun satan-tools-atsatan--rewrite-line (file line run-id comment)
  "Claim the @satan directive on LINE of FILE for RUN-ID with COMMENT.
Replaces the first `@satan' on the line with `@satan-was-here',
preserving any text on either side, and inserts the rendered claim
block (see `satan-tools-atsatan--render-block') immediately below.
Block lines inherit the original line's leading whitespace so list
items stay aligned.

Optimistic re-read: if the line no longer contains a bare `@satan' (or
already contains `@satan-was-here'), return :status \"already-done\"
without writing."
  (let ((coding-system-for-read 'utf-8)
        (coding-system-for-write 'utf-8))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (forward-line (1- line))
      (let* ((line-start (point))
             (line-end   (line-end-position))
             (current    (buffer-substring-no-properties line-start line-end))
             (id         (satan-tools-atsatan--hash file line)))
        (cond
         ((string-match-p satan-tools-atsatan--claimed-re current)
          (cons 'ok (list :match-id id :status "already-done")))
         ((not (or (string-match-p
                    satan-tools-atsatan--intervention-mark-re current)
                   (string-match-p (regexp-quote satan-tools-atsatan--mark)
                                   current)))
          (cons 'ok (list :match-id id :status "already-done")))
         (t
          ;; Detect the longest-matching active mark first so
          ;; `@satan-intervention-harmful' is replaced atomically; only
          ;; fall back to the bare `@satan' when no intervention prefix
          ;; sits on the line.  Older versions matched `@satan' alone
          ;; and corrupted intervention directives into
          ;; `@satan-was-here-intervention-harmful'.
          (let* ((mark-info
                  (cond
                   ((string-match
                     satan-tools-atsatan--intervention-mark-re current)
                    (cons (match-beginning 0)
                          (- (match-end 0) (match-beginning 0))))
                   (t
                    (let* ((m satan-tools-atsatan--mark)
                           (i (string-match (regexp-quote m) current)))
                      (cons i (length m))))))
                 (idx     (car mark-info))
                 (mlen    (cdr mark-info))
                 (replaced (concat (substring current 0 idx)
                                   "@satan-was-here"
                                   (substring current (+ idx mlen))))
                 (indent  (if (string-match "\\`\\([ \t]*\\)" current)
                              (match-string 1 current) ""))
                 (block   (satan-tools-atsatan--render-block
                           file run-id comment))
                 (block-text (mapconcat (lambda (l) (concat indent l))
                                        block "\n")))
            (delete-region line-start line-end)
            (goto-char line-start)
            (insert replaced "\n" block-text)
            (write-region (point-min) (point-max) file nil 'silent)
            (cons 'ok (list :match-id id :status "done")))))))))

(defun satan-tool/notes-at-satan-scan (args _ctx)
  "Implements notes_at_satan_scan. Returns (ok PLIST) | (error STR)."
  (let* ((ctx-lines (satan-tools-atsatan--clamp
                     (plist-get args :context-lines)
                     satan-tools-atsatan-default-context-lines
                     0 satan-tools-atsatan--context-max))
         (max-res   (satan-tools-atsatan--clamp
                     (plist-get args :max-results)
                     30 1 satan-tools-atsatan--results-max))
         (glob      (or (plist-get args :path-glob)
                        satan-tools-atsatan--default-path-glob))
         (argv      (satan-tools-atsatan--rg-argv max-res glob))
         (run       (satan-tools-atsatan--run-rg argv))
         (exit      (plist-get run :exit)))
    (cond
     ;; rg exits 1 when no matches; that is success-with-empty for us.
     ((not (memql exit '(0 1)))
      (cons 'error (format "rg failed: exit=%s %s"
                           exit (string-trim (plist-get run :stderr)))))
     (t
      (let* ((raw     (satan-tools-atsatan--parse-matches
                       (plist-get run :stdout)))
             (capped  (if (> (length raw) max-res)
                          (cl-subseq raw 0 max-res)
                        raw))
             (truncated (> (length raw) max-res))
             (enriched (satan-tools-atsatan--enrich capped ctx-lines)))
        (satan-tools-atsatan--remember enriched)
        (cons 'ok
              (list :scope "notes_at_satan_scan"
                    :root satan-tools-atsatan-root
                    :context-lines ctx-lines
                    :max-results max-res
                    :count (length enriched)
                    :truncated truncated
                    :matches enriched)))))))

(defun satan-tools-atsatan--patch-job-comment (job-id existing)
  "Compose the comment string when :patch-job=JOB-ID is set.
EXISTING is the model-supplied :comment (or nil).  Returns the
final tagged comment passed to the renderer."
  (let ((base (format "patch-job: queued %s" job-id)))
    (if (and existing
             (not (string-empty-p (string-trim existing))))
        (concat base "\n" (string-trim existing))
      base)))

(defun satan-tool/notes-at-satan-done (args ctx)
  "Implements notes_at_satan_done. Returns (ok PLIST) | (error STR).
Refused unless TOOL-CTX `:capabilities' includes `write-notes'.
Idempotent: claiming an already-done line returns :status \"already-done\".

When ARGS contains `:patch-job', the on-disk block is prefixed with a
`patch-job: queued <id>' tag; subsequent scans skip the line as
already-claimed (per `@satan-was-here').  The line is *not*
auto-rewritten when the patch later completes — the patch-ready inbox
item is the canonical user-facing surface for the result."
  (let* ((id      (plist-get args :match-id))
         (comment (plist-get args :comment))
         (patch-job (plist-get args :patch-job))
         (effective-comment
          (if patch-job
              (satan-tools-atsatan--patch-job-comment patch-job comment)
            comment))
         (caps    (plist-get ctx :capabilities))
         (run-id  (plist-get ctx :id))
         (pair    (gethash id satan-tools-atsatan--id-index)))
    (cond
     ((not (memq 'write-notes caps))
      (cons 'error "mode lacks capability write-notes"))
     ((not (stringp id))
      (cons 'error "match-id must be string"))
     ((null pair)
      (cons 'error (format "unknown match-id: %s (no prior scan in this session)" id)))
     ((not (file-exists-p (car pair)))
      (cons 'error (format "file no longer exists: %s" (car pair))))
     (t
      (let* ((file (car pair))
             (line (cdr pair)))
        (satan-tools-atsatan--rewrite-line file line run-id effective-comment))))))

;; ---------------------------------------------------------------------
;; T1.5b PR 4 — @satan-intervention-{harmful|contradicted} directives.
;; Grammar (outcome-semantics §7.2):
;;
;;   @satan-intervention-{harmful|contradicted}: \
;;       iv_id=<id> reason="<freeform>" [conf=low|medium|high] \
;;       [evidence=<path>:<line>]
;;
;; The scanner already returns these lines because `--mark' is the
;; substring `@satan' (so `@satan-intervention-*' matches) and
;; `--claimed-re' only filters `@satan-{was-here,done}'.  The
;; `notes_at_satan_intervention_done' handler parses the line, routes
;; through `satan-intervention-write-manual-outcome', and reuses
;; `--rewrite-line' to stamp the directive consumed (now mark-aware).
;; ---------------------------------------------------------------------

(defun satan-tools-atsatan--parse-intervention-kv (s)
  "Parse a space-separated `key=value' (or `key=\"value\"') stream.
Returns an alist of string→string.  Signals `user-error' on malformed
input.  Used internally by `--parse-intervention-directive'."
  (let ((pos 0) (n (length s)) (acc '()))
    (while (< pos n)
      (while (and (< pos n) (memq (aref s pos) '(?\s ?\t)))
        (cl-incf pos))
      (when (< pos n)
        (cond
         ((and (string-match "\\([a-z_]+\\)=" s pos)
               (= (match-beginning 0) pos))
          (let ((key (match-string 1 s)))
            (setq pos (match-end 0))
            (cond
             ((and (< pos n) (eq (aref s pos) ?\"))
              (let ((end (string-search "\"" s (1+ pos))))
                (unless end
                  (user-error "atsatan intervention directive: unterminated quoted value"))
                (push (cons key (substring s (1+ pos) end)) acc)
                (setq pos (1+ end))))
             (t
              (let ((end (or (string-match "[ \t]" s pos) n)))
                (push (cons key (substring s pos end)) acc)
                (setq pos end))))))
         (t
          (user-error "atsatan intervention directive: malformed token at %d: %s" pos s)))))
    (nreverse acc)))

(defun satan-tools-atsatan--parse-intervention-directive (line)
  "Parse LINE as an `@satan-intervention-*' directive (§7.2 grammar).
Returns `(ok PLIST)' with `:classification :iv-id :reason :conf
:evidence' (evidence may be nil; conf defaults to `\"low\"' per §4),
or `(error MSG)' on failure."
  (cond
   ((not (string-match
          "@satan-intervention-\\(harmful\\|contradicted\\):\\(.*\\)\\'"
          line))
    (cons 'error "not an @satan-intervention-{harmful|contradicted} directive"))
   (t
    (let* ((cls (match-string 1 line))
           (tail (match-string 2 line))
           (kv (condition-case err
                   (satan-tools-atsatan--parse-intervention-kv tail)
                 (user-error (cons :err (error-message-string err))))))
      (cond
       ((and (consp kv) (eq (car kv) :err))
        (cons 'error (cdr kv)))
       (t
        (let ((iv-id (cdr (assoc "iv_id" kv)))
              (reason (cdr (assoc "reason" kv)))
              (conf (or (cdr (assoc "conf" kv)) "low"))
              (evidence (cdr (assoc "evidence" kv))))
          (cond
           ((or (null iv-id) (string-empty-p iv-id))
            (cons 'error "directive missing iv_id="))
           ((null reason)
            (cons 'error "directive missing reason="))
           ((not (member conf '("low" "medium" "high")))
            (cons 'error (format "invalid conf=%S (expected low|medium|high)" conf)))
           (t (cons 'ok (list :classification cls
                              :iv-id iv-id
                              :reason reason
                              :conf conf
                              :evidence evidence)))))))))))

(defun satan-tools-atsatan--read-line (file line)
  "Read LINE (1-based) of FILE as a string; return nil on error."
  (condition-case _err
      (with-temp-buffer
        (let ((coding-system-for-read 'utf-8))
          (insert-file-contents file))
        (goto-char (point-min))
        (forward-line (1- line))
        (buffer-substring-no-properties (point) (line-end-position)))
    (error nil)))

(defun satan-tools-atsatan--intervention-ctx (run-id audit now)
  "Build a tool-ctx for the manual-outcome writer (parallels the
interactive command's `mark--build-ctx').  AUDIT is the reopened
handle for the iv's run-dir."
  (list :id run-id
        :mode-name "manual-mark"
        :time-now now
        :audit audit
        :capabilities '()))

(defun satan-tools-atsatan--intervention-run-id-of (iv-id)
  "Extract the run-id prefix from `<run-id>.iv<NNN>'."
  (cond
   ((not (stringp iv-id)) nil)
   ((string-match "\\`\\(.+\\)\\.iv[0-9]+\\'" iv-id)
    (match-string 1 iv-id))
   (t nil)))

(defun satan-tools-atsatan--iv-next-revisit-at (intervention)
  "Return ISO8601 string for INTERVENTION's window-close (§6.2)."
  (let* ((ts (plist-get intervention :ts))
         (mins (or (plist-get intervention :outcome_window_minutes) 0))
         (close (time-add (date-to-time ts)
                          (seconds-to-time (* 60 mins)))))
    (format-time-string "%Y-%m-%dT%H:%M:%S%z" close)))

(defun satan-tools-atsatan--iv-maturity-string (intervention now)
  "Return §3 maturity string for INTERVENTION at NOW (ISO8601)."
  (substring (symbol-name
              (satan-observer--maturity-state intervention now))
             1))

(defun satan-tools-atsatan--intervention-rewrite-comment (cls comment)
  "Build the on-disk claim block tag for a consumed intervention
directive.  CLS is the classification (\"harmful\"/\"contradicted\");
COMMENT is the model-supplied free comment (optional).  The result is
always `iv-<CLS>: <body>' so the tag/body splitter sees a tag (carried
into the QUOTE header) and the body lands on its own line."
  (let ((trim (and comment (string-trim comment))))
    (format "iv-%s: %s"
            cls
            (if (and trim (not (string-empty-p trim))) trim ""))))

(defun satan-tools-atsatan--intervention-do-write (parsed now)
  "Half-2 of the directive handler: write the manual outcome.
PARSED is the directive plist; NOW is the audit-boundary ISO timestamp.
Returns (ok . PLIST) carrying `:audit-event' and the parsed shape,
or (error . STR) on lookup / run-dir failure."
  (let* ((iv-id (plist-get parsed :iv-id))
         (cls (plist-get parsed :classification))
         (conf (plist-get parsed :conf))
         (reason (plist-get parsed :reason))
         (evidence (plist-get parsed :evidence))
         (iv-run-id (satan-tools-atsatan--intervention-run-id-of iv-id))
         (lookup (and iv-run-id (satan-intervention-lookup iv-id)))
         (iv (and lookup (plist-get lookup :intervention)))
         (run-dir (and iv-run-id
                       (fboundp 'satan-broker-locate-run-dir)
                       (satan-broker-locate-run-dir iv-run-id))))
    (cond
     ((null iv-run-id)
      (cons 'error (format "directive iv_id=%S malformed" iv-id)))
     ((null iv)
      (cons 'error (format "no intervention %s in projection" iv-id)))
     ((null run-dir)
      (cons 'error (format "no run-dir on disk for %s" iv-run-id)))
     (t
      (let* ((audit (satan-audit-reopen run-dir))
             (mark-ctx (satan-tools-atsatan--intervention-ctx
                        iv-run-id audit now))
             (maturity (satan-tools-atsatan--iv-maturity-string iv now))
             (revisit (satan-tools-atsatan--iv-next-revisit-at iv))
             (event (satan-intervention-write-manual-outcome
                     :ctx mark-ctx
                     :intervention-id iv-id
                     :classification cls
                     :confidence conf
                     :reason reason
                     :evidence-pointer evidence
                     :marked-by "notes-directive"
                     :maturity maturity
                     :next-revisit-at revisit
                     :classified-at now)))
        (cons 'ok (list :intervention-id iv-id
                        :classification cls
                        :audit-event event)))))))

(defun satan-tool/notes-at-satan-intervention-done (args ctx)
  "Implements `notes_at_satan_intervention_done'.
ARGS plist: `:match-id' (from prior scan) and optional `:comment'
(rendered into the on-disk claim block, like `notes_at_satan_done').
Reads the matched line, parses the §7.2 directive, routes through
`satan-intervention-write-manual-outcome' with `:marked-by
\"notes-directive\"', then stamps the directive consumed via the
mark-aware `--rewrite-line'.

CTX requires capability `write-notes' (same as `notes_at_satan_done').
The outcome audit event is written into the iv's *original* run-dir
(via `satan-audit-reopen'), not the consuming tick's run, so
intervention.outcome_* events stay attached to the intervention's
authoring run for projection rebuild."
  (let* ((id (plist-get args :match-id))
         (comment (plist-get args :comment))
         (caps (plist-get ctx :capabilities))
         (consuming-run-id (plist-get ctx :id))
         (now (or (plist-get ctx :time-now)
                  (format-time-string "%Y-%m-%dT%H:%M:%S%z")))
         (pair (gethash id satan-tools-atsatan--id-index)))
    (cond
     ((not (memq 'write-notes caps))
      (cons 'error "mode lacks capability write-notes"))
     ((not (stringp id))
      (cons 'error "match-id must be string"))
     ((null pair)
      (cons 'error
            (format "unknown match-id: %s (no prior scan in this session)" id)))
     ((not (file-exists-p (car pair)))
      (cons 'error (format "file no longer exists: %s" (car pair))))
     (t
      (let* ((file (car pair))
             (line (cdr pair))
             (content (satan-tools-atsatan--read-line file line)))
        (cond
         ((null content)
          (cons 'error (format "could not read %s:%d" file line)))
         (t
          (pcase (satan-tools-atsatan--parse-intervention-directive content)
            (`(error . ,msg) (cons 'error msg))
            (`(ok . ,parsed)
             (pcase (satan-tools-atsatan--intervention-do-write parsed now)
               (`(error . ,msg) (cons 'error msg))
               (`(ok . ,write-plist)
                (let* ((cls (plist-get write-plist :classification))
                       (tag (satan-tools-atsatan--intervention-rewrite-comment
                             cls comment))
                       (rewrite-result
                        (satan-tools-atsatan--rewrite-line
                         file line consuming-run-id tag)))
                  (pcase rewrite-result
                    (`(ok . ,_)
                     (cons 'ok (list :match-id id
                                     :status "done"
                                     :event (plist-get write-plist :audit-event)
                                     :intervention-id
                                     (plist-get write-plist :intervention-id)
                                     :classification cls)))
                    (other other))))))))))))))

(satan-tool-register
 (list :name "notes_at_satan_scan"
       :risk 'read
       :args-schema '(context-lines (:type integer :required nil)
                      max-results   (:type integer :required nil)
                      path-glob     (:type string  :required nil))
       :handler 'satan-tool/notes-at-satan-scan))

(satan-tool-register
 (list :name "notes_at_satan_done"
       :risk 'low
       :args-schema '(match-id  (:type string :required t)
                      comment   (:type string :required nil)
                      patch-job (:type string :required nil))
       :handler 'satan-tool/notes-at-satan-done))

(satan-tool-register
 (list :name "notes_at_satan_intervention_done"
       :risk 'low
       :args-schema '(match-id (:type string :required t)
                      comment  (:type string :required nil))
       :handler 'satan-tool/notes-at-satan-intervention-done))

;; The `tick-agent' mode that drives these @satan tools is registered in
;; satan-tick.el, beside `tick-pulse' and `satan-tick-pool' — all
;; tick modes in one place.  The tool *handlers* live here; the mode
;; *spec* lives there.

(provide 'satan-tools-atsatan)
;;; satan-tools-atsatan.el ends here
