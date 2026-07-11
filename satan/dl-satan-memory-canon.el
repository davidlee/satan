;;; dl-satan-memory-canon.el --- canonicalizer (PURE) -*- lexical-binding: t; -*-

;; Pure function `dl-satan-memory-canon-canonicalize':
;;
;;   (evidence_window hints ctx) -> (handles handle_sources rejected)
;;
;; Given a structural evidence-window snapshot (built by the broker in
;; step 6), a typed hint plist (LLM-supplied; optional), and a small
;; runtime context, return the canonical handles + per-handle source
;; provenance + a list of rejected closed-world hint values.  Mirrors
;; `memory.design.md' §3.
;;
;; PURITY BOUNDARY (§3.5): every rule below is a pure function over
;; (evidence hints ctx).  This file may NOT call any of:
;;   shell-command, call-process, insert-file-contents, url-retrieve,
;;   current-time, current-time-string,
;;   bough invocations of any kind.
;; The grep-lint test in test/dl-satan-memory-canon-test.el enforces
;; this by reading every form and refusing forbidden symbols.

(require 'cl-lib)
(require 'subr-x)
(require 'dl-satan-memory-grammar)

;; ---------------------------------------------------------------------
;; Configuration
;; ---------------------------------------------------------------------

(defconst dl-satan-memory-canon--trace-kinds
  '("observation" "intervention" "prediction" "outcome")
  "Allowed values for `hints.kind' (trace-level field, not a handle).")

(defconst dl-satan-memory-canon--valences
  '("positive" "negative" "neutral" "mixed" "unknown"))

(defconst dl-satan-memory-canon--max-topic-count 5
  "Cap on `hints.topic' entries after slug normalization (§3.1, hints).")

(defconst dl-satan-memory-canon--origin-priority
  '((observed . 0) (derived . 1) (ctx . 2) (hint . 3))
  "Lower value wins when the same handle is emitted by multiple rules.")

(defconst dl-satan-memory-canon--app-to-surface
  '(("firefox"               . "browser")
    ("Firefox"               . "browser")
    ("Chromium"              . "browser")
    ("chromium"              . "browser")
    ("emacs"                 . "editor")
    ("Emacs"                 . "editor")
    ("Code"                  . "editor")
    ("alacritty"             . "terminal")
    ("Alacritty"             . "terminal")
    ("wezterm"               . "terminal")
    ("kitty"                 . "terminal")
    ("foot"                  . "terminal")
    ("ghostty"               . "terminal")
    ("com.mitchellh.ghostty" . "terminal")
    ("Slack"                 . "chat")
    ("slack"                 . "chat")
    ("Discord"               . "chat")
    ("Telegram"              . "chat")
    ("Element"               . "chat"))
  "App id → surface mapping.  Unrecognized apps fall through to `desktop'.")

(defconst dl-satan-memory-canon--domain-to-kind
  '(("github.com"           . "repo_hosting")
    ("gitlab.com"           . "repo_hosting")
    ("codeberg.org"         . "repo_hosting")
    ("news.ycombinator.com" . "social")
    ("lobste.rs"            . "social")
    ("twitter.com"          . "social")
    ("x.com"                . "social")
    ("reddit.com"           . "social")
    ("stackoverflow.com"    . "reference")
    ("stackexchange.com"    . "reference")
    ("en.wikipedia.org"     . "reference")
    ("google.com"           . "search")
    ("duckduckgo.com"       . "search")
    ("kagi.com"             . "search")
    ("docs.rs"              . "docs")
    ("doc.rust-lang.org"    . "docs")
    ("docs.python.org"      . "docs")
    ("nodejs.org"           . "docs")
    ("developer.mozilla.org" . "docs"))
  "Domain → domain_kind classification.  First match by literal equality.")

(defconst dl-satan-memory-canon--extension-to-file-kind
  '(("org" . "org")
    ("el"  . "source") ("rs" . "source") ("py" . "source") ("ts" . "source")
    ("tsx" . "source") ("js" . "source") ("jsx" . "source") ("go" . "source")
    ("c"   . "source") ("cpp" . "source") ("h" . "source") ("hpp" . "source")
    ("rb"  . "source") ("clj" . "source") ("sh" . "source") ("bash" . "source")
    ("sql" . "source") ("nix" . "source") ("lua" . "source")
    ("md"  . "doc")   ("rst" . "doc") ("txt" . "doc") ("adoc" . "doc")
    ("json" . "data") ("yaml" . "data") ("yml" . "data") ("toml" . "data")
    ("csv"  . "data") ("xml" . "data")
    ("conf" . "config") ("cfg" . "config") ("ini" . "config") ("env" . "config"))
  "File extension → file_kind mapping (closed-world).")

;; ---------------------------------------------------------------------
;; Rule registry
;; ---------------------------------------------------------------------

(defvar dl-satan-memory-canon--rules nil
  "Ordered list of (RULE-ID . FUNCTION).  Each FUNCTION takes
  (evidence hints ctx) and returns a list of emission plists.")

(defun dl-satan-memory-canon--register-rule (id fn)
  "Register or replace rule ID with handler FN.  Idempotent on reload."
  (setq dl-satan-memory-canon--rules
        (append (cl-remove id dl-satan-memory-canon--rules :key #'car)
                (list (cons id fn)))))

(defmacro dl-satan-memory-canon-defrule (id args docstring &rest body)
  "Define a canonicalizer rule named ID.
ARGS is `(EVIDENCE HINTS CTX)'.  BODY must return a list of emission
plists, each of the form
  (:handle STR :origin SYM :evidence-pointer STR
   :hint-field STR-OR-NIL :confidence FLOAT)
The dispatcher attaches `:rule-id' and `:grammar-version'."
  (declare (indent 2) (doc-string 3))
  (let ((fn-sym (intern (format "dl-satan-memory-canon--rule/%s" id))))
    `(progn
       (defun ,fn-sym ,args ,docstring ,@body)
       (dl-satan-memory-canon--register-rule ',id #',fn-sym))))

;; ---------------------------------------------------------------------
;; Pure helpers
;; ---------------------------------------------------------------------

(defun dl-satan-memory-canon--slugify (s)
  "Lowercase, replace non-alphanumeric with `-', trim hyphens, return
or nil for the empty result."
  (when (stringp s)
    (let* ((s (downcase s))
           (s (replace-regexp-in-string "[^a-z0-9]+" "-" s))
           (s (replace-regexp-in-string "\\`-+\\|-+\\'" "" s)))
      (and (not (string-empty-p s)) s))))

(defun dl-satan-memory-canon--app-surface (app-id)
  "Return the closed-world `surface' value for APP-ID, or `desktop'."
  (or (cdr (assoc app-id dl-satan-memory-canon--app-to-surface))
      "desktop"))

(defun dl-satan-memory-canon--domain-kind (domain)
  "Return the closed-world domain_kind for DOMAIN, or nil if unmapped."
  (cdr (assoc domain dl-satan-memory-canon--domain-to-kind)))

(defun dl-satan-memory-canon--file-extension (path)
  "Return the (lowercase) extension of PATH, or nil."
  (when (and (stringp path) (string-match "\\.\\([^./]+\\)\\'" path))
    (downcase (match-string 1 path))))

(defun dl-satan-memory-canon--file-kind (path)
  (cdr (assoc (dl-satan-memory-canon--file-extension path)
              dl-satan-memory-canon--extension-to-file-kind)))

(defun dl-satan-memory-canon--emit (handle origin pointer &optional hint-field confidence)
  "Build an emission plist."
  (list :handle handle
        :origin origin
        :evidence-pointer pointer
        :hint-field hint-field
        :confidence (or confidence 1.0)))

;; ---------------------------------------------------------------------
;; Hint normalization
;; ---------------------------------------------------------------------

(defun dl-satan-memory-canon--suggest-closed (ns input)
  "Return up to 5 closed-world values for NS whose names contain INPUT
or share a prefix with it.  Used to build the rejected suggestions list."
  (let* ((all (dl-satan-memory-grammar-closed-values ns))
         (lower (and (stringp input) (downcase input)))
         (scored
          (mapcar
           (lambda (v)
             (cons (cond
                    ((null lower) 99)
                    ((equal v lower) 0)
                    ((string-prefix-p lower v) 1)
                    ((string-match-p (regexp-quote lower) v) 2)
                    (t 3))
                   v))
           all)))
    (mapcar #'cdr
            (cl-subseq (sort scored (lambda (a b) (< (car a) (car b))))
                       0 (min 5 (length scored))))))

(defun dl-satan-memory-canon-normalize-hints (hints)
  "Pure.  Return (:normalized PLIST :rejected LIST).
Closed-world hint fields (kind, phase, valence) are validated against
the grammar; alias resolution applies to phase.  Open-world fields
(topic, focal_app) are slug-normalized.  `topic' is deduplicated and
capped at `dl-satan-memory-canon--max-topic-count'."
  (let ((norm nil)
        (rejected nil))
    ;; kind
    (let ((k (plist-get hints :kind)))
      (cond
       ((null k) (setq norm (plist-put norm :kind "observation")))
       ((member k dl-satan-memory-canon--trace-kinds)
        (setq norm (plist-put norm :kind k)))
       (t (push (list :field 'kind :value k
                      :suggestions dl-satan-memory-canon--trace-kinds)
                rejected))))
    ;; phase (alias-resolved, then closed-world)
    (let* ((p (plist-get hints :phase))
           (alias (and p (dl-satan-memory-grammar-alias-target p)))
           (resolved (cond
                      ((null p) nil)
                      ((and alias (string-prefix-p "phase:" alias))
                       (substring alias (length "phase:")))
                      (t p))))
      (cond
       ((null resolved) nil)
       ((dl-satan-memory-grammar-valid-value-p 'phase resolved)
        (setq norm (plist-put norm :phase resolved)))
       (t (push (list :field 'phase :value p
                      :suggestions (dl-satan-memory-canon--suggest-closed 'phase p))
                rejected))))
    ;; valence
    (let ((v (plist-get hints :valence)))
      (cond
       ((null v) nil)
       ((member v dl-satan-memory-canon--valences)
        (setq norm (plist-put norm :valence v)))
       (t (push (list :field 'valence :value v
                      :suggestions dl-satan-memory-canon--valences)
                rejected))))
    ;; topic (open-world, slugified, deduped, capped)
    (let* ((raw (plist-get hints :topic))
           (slugs (delq nil (mapcar #'dl-satan-memory-canon--slugify
                                    (and (listp raw) raw))))
           (deduped (cl-remove-duplicates slugs :test #'equal))
           (capped (cl-subseq deduped 0
                              (min (length deduped)
                                   dl-satan-memory-canon--max-topic-count))))
      (when capped
        (setq norm (plist-put norm :topic capped))))
    ;; focal_app (open-world)
    (let* ((raw (plist-get hints :focal_app))
           (slug (dl-satan-memory-canon--slugify raw)))
      (when slug
        (setq norm (plist-put norm :focal_app slug))))
    ;; focal_bough_nanoid (validated shape; not slugified)
    (let ((nano (plist-get hints :focal_bough_nanoid)))
      (cond
       ((null nano) nil)
       ((and (stringp nano) (string-match-p "\\`[A-Za-z0-9_-]+\\'" nano))
        (setq norm (plist-put norm :focal_bough_nanoid nano)))
       (t (push (list :field 'focal_bough_nanoid :value nano
                      :suggestions nil)
                rejected))))
    ;; outcome_for (trace_id pass-through; not validated here)
    (let ((oc (plist-get hints :outcome_for)))
      (when oc (setq norm (plist-put norm :outcome_for oc))))
    (list :normalized norm :rejected (nreverse rejected))))

;; ---------------------------------------------------------------------
;; Rules
;; ---------------------------------------------------------------------

(dl-satan-memory-canon-defrule panopticon.current.app (ev _hints _ctx)
  "From `current_window.app_id': emit `app:<id>' (observed) and the
derived `surface:<value>'."
  (let* ((cw (plist-get ev :current_window))
         (app-id (and cw (plist-get cw :app_id))))
    (when app-id
      (let* ((slug (dl-satan-memory-canon--slugify app-id))
             (surface (dl-satan-memory-canon--app-surface app-id)))
        (delq
         nil
         (list
          (and slug
               (dl-satan-memory-canon--emit
                (concat "app:" slug) 'observed "/current_window/app_id"))
          (and surface
               (dl-satan-memory-canon--emit
                (concat "surface:" surface) 'derived "/current_window/app_id"))))))))

(dl-satan-memory-canon-defrule panopticon.surface_transition (ev _hints _ctx)
  "Walk `focus_segments' pairs; emit `surface_transition:<from>-><to>'
for any pair whose derived surface value differs.  Only emit
transitions that exist in the closed-world enum."
  (let* ((segs (plist-get ev :focus_segments))
         (pairs (cl-loop for (a b) on segs
                         when (and a b) collect (cons a b)))
         emissions
         (idx 0))
    (dolist (p pairs)
      (let* ((from (dl-satan-memory-canon--app-surface
                    (plist-get (car p) :app_id)))
             (to   (dl-satan-memory-canon--app-surface
                    (plist-get (cdr p) :app_id))))
        (when (and from to (not (equal from to)))
          (let ((handle (format "surface_transition:%s->%s" from to)))
            (when (dl-satan-memory-grammar-valid-value-p
                   'surface_transition (format "%s->%s" from to))
              (push (dl-satan-memory-canon--emit
                     handle 'derived
                     (format "/focus_segments/%d..%d" idx (1+ idx)))
                    emissions)))))
      (setq idx (1+ idx)))
    (nreverse emissions)))

(dl-satan-memory-canon-defrule panopticon.event_transition (_ev _hints _ctx)
  "Inert in v1 (per design §3.3 and §10.8: panopticon does not observe
terminal exit codes; the closed-world entries are admitted for future
emitters).  Returns no emissions."
  nil)

(dl-satan-memory-canon-defrule panopticon.domain_transition (ev _hints _ctx)
  "Walk `browser_segments' pairs; emit `domain_transition:<from>-><to>'
when the domain_kind values differ and the pair is in the closed-world
enum (v1 ships only `docs->editor', which is informally a cross-surface
transition; concrete domain→domain transitions can land later)."
  (let ((segs (plist-get ev :browser_segments))
        emissions
        (idx 0))
    (cl-loop for (a b) on segs
             when (and a b)
             do (let* ((from (dl-satan-memory-canon--domain-kind
                              (plist-get a :domain)))
                       (to   (dl-satan-memory-canon--domain-kind
                              (plist-get b :domain))))
                  (when (and from to (not (equal from to)))
                    (let ((value (format "%s->%s" from to)))
                      (when (dl-satan-memory-grammar-valid-value-p
                             'domain_transition value)
                        (push (dl-satan-memory-canon--emit
                               (concat "domain_transition:" value)
                               'derived
                               (format "/browser_segments/%d..%d" idx (1+ idx)))
                              emissions)))))
             do (setq idx (1+ idx)))
    (nreverse emissions)))

(dl-satan-memory-canon-defrule panopticon.docs_visit (ev _hints _ctx)
  "Emit `domain_kind:docs' once if any browser segment lands in the docs
allowlist within the window."
  (let ((segs (plist-get ev :browser_segments))
        (idx 0)
        match-idx)
    (while (and segs (null match-idx))
      (when (equal "docs"
                   (dl-satan-memory-canon--domain-kind
                    (plist-get (car segs) :domain)))
        (setq match-idx idx))
      (setq segs (cdr segs)
            idx (1+ idx)))
    (when match-idx
      (list (dl-satan-memory-canon--emit
             "domain_kind:docs" 'observed
             (format "/browser_segments/%d" match-idx))))))

(dl-satan-memory-canon-defrule panopticon.content (ev _hints _ctx)
  "From `:content_recent' captures: emit `content_domain:<d>' per unique
domain.  Deduped within the rule so busy reading a single domain yields
one handle, not N.  Metadata only — page bodies are NOT in the evidence
window and are NOT written to the memory store (DEC-2)."
  (let ((captures (plist-get ev :content_recent)))
    (when captures
      (let ((domains (cl-delete-duplicates
                      (delq nil (mapcar (lambda (c) (plist-get c :domain)) captures))
                      :test #'string=)))
        (mapcar (lambda (domain)
                  (dl-satan-memory-canon--emit
                   (concat "content_domain:" domain) 'observed
                   "/content_recent"))
                domains)))))

(dl-satan-memory-canon-defrule bough.recent_status_change (ev _hints _ctx)
  "If any `bough_recent' entry is a status_changed event, emit
`bough_event:status_changed' and `artifact:bough_status_change' once."
  (let ((recent (plist-get ev :bough_recent))
        (idx 0)
        match-idx)
    (while (and recent (null match-idx))
      (when (equal "status_changed" (plist-get (car recent) :event))
        (setq match-idx idx))
      (setq recent (cdr recent)
            idx (1+ idx)))
    (when match-idx
      (let ((ptr (format "/bough_recent/%d" match-idx)))
        (list
         (dl-satan-memory-canon--emit
          "bough_event:status_changed" 'observed ptr)
         (dl-satan-memory-canon--emit
          "artifact:bough_status_change" 'derived ptr))))))

(dl-satan-memory-canon-defrule bough.active_focus (ev hints _ctx)
  "When `hints.focal_bough_nanoid' is supplied AND the same nanoid is
present in `bough_active', emit `bough_node:<nanoid>' and (if the
node carries `project_nanoid') `bough_project:<nanoid>'."
  (let* ((focus (plist-get hints :focal_bough_nanoid))
         (active (plist-get ev :bough_active)))
    (when (and focus active)
      (let* ((match (cl-find focus active
                             :key (lambda (n) (plist-get n :nanoid))
                             :test #'equal))
             (idx (and match (cl-position match active)))
             (proj (and match (plist-get match :project_nanoid))))
        (when match
          (let ((ptr (format "/bough_active/%d" idx)))
            (delq
             nil
             (list (dl-satan-memory-canon--emit
                    (concat "bough_node:" focus) 'observed ptr
                    "focal_bough_nanoid")
                   (and proj
                        (dl-satan-memory-canon--emit
                         (concat "bough_project:" proj) 'derived ptr))))))))))

(dl-satan-memory-canon-defrule cwd.project (ev _hints _ctx)
  "Derive a project slug from `git_state.remote' (last path segment) or
`fs_state.cwd' (last directory).  Open-world; slugified."
  (let* ((git (plist-get ev :git_state))
         (fs  (plist-get ev :fs_state))
         (remote (and git (plist-get git :remote)))
         (cwd    (and fs  (plist-get fs  :cwd)))
         (slug (cond
                (remote
                 (let* ((tail (car (last (split-string remote "/")))))
                   (and tail
                        (dl-satan-memory-canon--slugify
                         (replace-regexp-in-string "\\.git\\'" "" tail)))))
                (cwd
                 (dl-satan-memory-canon--slugify
                  (car (last (split-string (directory-file-name cwd) "/"))))))))
    (when slug
      (list (dl-satan-memory-canon--emit
             (concat "project:" slug)
             (if remote 'observed 'derived)
             (if remote "/git_state/remote" "/fs_state/cwd"))))))

(dl-satan-memory-canon-defrule vcs.recent_commit (ev _hints _ctx)
  "Emit `project:<slug>' for each repo with a commit in `:git_commits'.
The git-activity feed (sourced by the global post-commit hook) is
pwd-independent, so emissions are `observed'; `--merge' dedupes against
`cwd.project', keeping the higher-priority origin.  Slug derives from a
row's `:slug', else its `:remote' tail (`.git' stripped), else its
`:repo' basename.  Open-world `project' namespace — no grammar bump.
Deduped within the rule so a busy repo yields one handle."
  (let ((idx -1) seen acc)
    (dolist (row (plist-get ev :git_commits) (nreverse acc))
      (setq idx (1+ idx))
      (let* ((remote (plist-get row :remote))
             (repo (plist-get row :repo))
             (raw (cond
                   ((let ((s (plist-get row :slug)))
                      (and (stringp s) (not (string-empty-p s)) s)))
                   ((and (stringp remote) (not (string-empty-p remote)))
                    (replace-regexp-in-string
                     "\\.git\\'" "" (car (last (split-string remote "/")))))
                   ((stringp repo)
                    (car (last (split-string (directory-file-name repo) "/"))))))
             (slug (and raw (dl-satan-memory-canon--slugify raw))))
        (when (and slug (not (member slug seen)))
          (push slug seen)
          (push (dl-satan-memory-canon--emit
                 (concat "project:" slug) 'observed
                 (format "/git_commits/%d/slug" idx))
                acc))))))

(dl-satan-memory-canon-defrule cwd.file_kind (ev _hints _ctx)
  "Map the first recently-edited file's extension to a closed-world
file_kind.  Falls back to the cwd's apparent extension (rare)."
  (let* ((fs (plist-get ev :fs_state))
         (files (and fs (plist-get fs :recent_files)))
         (first (car files))
         (kind  (or (dl-satan-memory-canon--file-kind first)
                    (dl-satan-memory-canon--file-kind
                     (and fs (plist-get fs :cwd))))))
    (when (and kind (dl-satan-memory-grammar-valid-value-p 'file_kind kind))
      (list (dl-satan-memory-canon--emit
             (concat "file_kind:" kind) 'observed
             (if first "/fs_state/recent_files/0" "/fs_state/cwd"))))))

(dl-satan-memory-canon-defrule ctx.mode (_ev _hints ctx)
  "Emit `mode:<mode_name>' if the mode name is a closed-world value."
  (let ((mode (plist-get ctx :mode_name)))
    (when (and mode (dl-satan-memory-grammar-valid-value-p 'mode mode))
      (list (dl-satan-memory-canon--emit
             (concat "mode:" mode) 'ctx "/ctx/mode_name")))))

(dl-satan-memory-canon-defrule time.day_week (_ev _hints ctx)
  "From `ctx.time_now' (ISO8601 string): emit `day:YYYY-MM-DD' and
`week:YYYY-Www'.  Both are open-world; values stable across runs."
  (let ((tn (plist-get ctx :time_now)))
    (when (and (stringp tn)
               (string-match-p
                "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}T" tn))
      (let* ((parsed (date-to-time tn))
             (day  (format-time-string "%Y-%m-%d" parsed))
             (week (format-time-string "%G-W%V" parsed)))
        (list
         (dl-satan-memory-canon--emit
          (concat "day:" day) 'ctx "/ctx/time_now")
         (dl-satan-memory-canon--emit
          (concat "week:" week) 'ctx "/ctx/time_now"))))))

(dl-satan-memory-canon-defrule hint.topic (_ev hints _ctx)
  "Emit one `topic:<slug>' per normalized hint topic.  Hints have
already been slugified, deduped, and capped upstream."
  (let ((topics (plist-get hints :topic)))
    (cl-loop for slug in topics
             collect (dl-satan-memory-canon--emit
                      (concat "topic:" slug) 'hint
                      "/hints/topic" "topic"))))

(dl-satan-memory-canon-defrule hint.phase (_ev hints _ctx)
  "Emit `phase:<value>' from the validated hint phase."
  (let ((phase (plist-get hints :phase)))
    (when phase
      (list (dl-satan-memory-canon--emit
             (concat "phase:" phase) 'hint "/hints/phase" "phase")))))

(dl-satan-memory-canon-defrule hint.focal_app (_ev hints _ctx)
  "When hints.focal_app is supplied and current_window did not already
contribute the same app, emit `app:<slug>' from the hint side."
  (let ((focal (plist-get hints :focal_app)))
    (when focal
      (list (dl-satan-memory-canon--emit
             (concat "app:" focal) 'hint "/hints/focal_app" "focal_app")))))

;; ---------------------------------------------------------------------
;; Dispatch
;; ---------------------------------------------------------------------

(defun dl-satan-memory-canon--origin-rank (origin)
  (or (cdr (assq origin dl-satan-memory-canon--origin-priority)) 99))

(defun dl-satan-memory-canon--merge (emissions grammar-version)
  "Dedupe EMISSIONS by `:handle', keep the highest-priority origin
(observed > derived > ctx > hint).  Return (HANDLES SOURCES-ALIST)."
  (let ((table (make-hash-table :test 'equal)))
    (dolist (e emissions)
      (let* ((h (plist-get e :handle))
             (prev (gethash h table)))
        (when (or (null prev)
                  (< (dl-satan-memory-canon--origin-rank
                      (plist-get e :origin))
                     (dl-satan-memory-canon--origin-rank
                      (plist-get prev :origin))))
          (puthash h e table))))
    (let (handles sources)
      (maphash
       (lambda (h e)
         (push h handles)
         (push (cons h
                     (list :rule_id (symbol-name (plist-get e :rule-id))
                           :origin (symbol-name (plist-get e :origin))
                           :evidence_pointer (plist-get e :evidence-pointer)
                           :hint_field (plist-get e :hint-field)
                           :confidence (plist-get e :confidence)
                           :grammar_version grammar-version))
               sources))
       table)
      (list (sort handles #'string<) (nreverse sources)))))

(defun dl-satan-memory-canon--validate-emission (rule-id e)
  "Reject malformed emissions early — better than failing inside the
DB CHECK constraint."
  (let ((h (plist-get e :handle)))
    (cond
     ((not (stringp h))
      (error "rule %s emitted non-string handle: %S" rule-id h))
     ((not (string-match-p
            "\\`[a-z][a-z0-9_]*:[A-Za-z0-9][A-Za-z0-9_.+>-]*\\'" h))
      (error "rule %s emitted malformed handle: %s" rule-id h))
     (t e))))

(defun dl-satan-memory-canon-canonicalize (evidence normalized-hints ctx)
  "Pure.  Dispatch every registered rule over (EVIDENCE NORMALIZED-HINTS CTX).
Return a plist `(:handles LIST :handle_sources ALIST :rejected LIST)'.
REJECTED here is always nil — hint rejection is the job of
`dl-satan-memory-canon-normalize-hints'.  Callers using
`dl-satan-memory-canon-canonicalize-from-raw' get rejections merged."
  (let* ((gv (or (plist-get ctx :current_grammar_version)
                 dl-satan-memory-grammar-current-version))
         (all-emissions
          (cl-loop for (rule-id . fn) in dl-satan-memory-canon--rules
                   for raw = (funcall fn evidence normalized-hints ctx)
                   append (mapcar
                           (lambda (e)
                             (dl-satan-memory-canon--validate-emission
                              rule-id
                              (plist-put (copy-sequence e) :rule-id rule-id)))
                           raw)))
         (merged (dl-satan-memory-canon--merge all-emissions gv)))
    (list :handles (car merged)
          :handle_sources (cadr merged)
          :rejected nil)))

(defun dl-satan-memory-canon-canonicalize-from-raw (evidence raw-hints ctx)
  "Convenience wrapper: normalize RAW-HINTS, dispatch rules, merge
rejected lists.  Returns
  (:handles LIST :handle_sources ALIST :rejected LIST :normalized PLIST)
where `:normalized' is the closed/open-world hint scalars produced
by `dl-satan-memory-canon-normalize-hints' (kind, phase, valence,
topic, focal_app, focal_bough_nanoid, outcome_for).  Callers that
need `kind' or `valence' read them off `:normalized' instead of
running the normalize step a second time."
  (let* ((nh (dl-satan-memory-canon-normalize-hints raw-hints))
         (normalized (plist-get nh :normalized))
         (rejected (plist-get nh :rejected))
         (canon (dl-satan-memory-canon-canonicalize
                 evidence normalized ctx)))
    (setq canon (plist-put canon :rejected
                           (append rejected (plist-get canon :rejected))))
    (plist-put canon :normalized normalized)))

(provide 'dl-satan-memory-canon)
;;; dl-satan-memory-canon.el ends here
