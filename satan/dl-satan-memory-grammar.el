;;; dl-satan-memory-grammar.el --- closed-world grammar + v1 seed -*- lexical-binding: t; -*-

;; In-process mirror of grammar v1 as persisted in `satan_memory':
;; namespaces (open/closed world), closed-world enum values, alias map,
;; and namespace default weights.  Mirrors `memory.design.md' §2 verbatim.
;;
;; The substrate canonicalizer (step 5) consumes these constants.  A
;; sync test (`test/dl-satan-memory-grammar-test.el') verifies that the
;; elisp side and the DB side cannot drift without one of them being
;; updated — when grammar bumps to v2, the elisp side must change
;; *and* a migration must land before this test goes green again.

(require 'cl-lib)

(defconst dl-satan-memory-grammar-current-version 1
  "Latest grammar version known to elisp.  Must equal the most recent
row in `satan_memory.grammar_versions'.")

(defconst dl-satan-memory-grammar-namespaces
  '((app                 . open)
    (surface             . closed)
    (project             . open)
    (repo                . open)
    (domain              . open)
    (domain_kind         . closed)
    (file_kind           . closed)
    (event               . closed)
    (surface_transition  . closed)
    (event_transition    . closed)
    (domain_transition   . closed)
    (artifact            . closed)
    (phase               . closed)
    (intervention        . closed)
    (outcome             . closed)
    (topic               . open)
    (bough_kind          . closed)
    (bough_status        . closed)
    (bough_event         . closed)
    (bough_node          . open)
    (bough_project       . open)
    (workspace           . open)
    (queue               . open)
    (week                . open)
    (day                 . open)
    (mode                . closed))
  "Alist (NAMESPACE . WORLD).  WORLD is `closed' or `open'.  Mirrors §2.1.")

(defconst dl-satan-memory-grammar-closed-values
  '((surface
     . ("browser" "editor" "terminal" "desktop" "chat"))
    (domain_kind
     . ("docs" "learning" "reference" "social" "search"
        "tooling" "repo_hosting" "unknown"))
    (file_kind
     . ("org" "source" "config" "data" "binary" "doc" "unknown"))
    (event
     . ("command_error" "command_ok" "idle_begin" "idle_end"
        "desktop_switch" "tab_open" "tab_close" "window_focus_change"))
    (surface_transition
     . ("terminal->browser" "editor->browser"
        "browser->editor" "idle->editor"))
    (event_transition
     . ("command_error->browser" "command_error->docs"))
    (domain_transition
     . ("docs->editor"))
    (artifact
     . ("none" "file_edit" "commit" "note"
        "bough_status_change" "bough_task_created" "bough_annotation"))
    (phase
     . ("orientation" "execution" "recovery" "post_failure" "review"))
    (intervention
     . ("ask" "accuse" "delay" "dim" "pin" "quarantine" "surface"
        "withhold" "summon" "annotate" "reward"))
    (outcome
     . ("unknown" "returned_to_editing" "continued_drift"
        "produced_artifact" "abandoned_context" "bough_progress"))
    (bough_kind
     . ("task" "group" "project" "note"))
    (bough_status
     . ("todo" "active" "done" "dropped"))
    (bough_event
     . ("created" "status_changed" "annotated" "described"
        "moved" "linked" "archived"))
    (mode
     . ("morning" "motd" "tick-pulse" "self-edit-mech" "self-edit-mind")))
  "Alist (NAMESPACE . VALUES) for closed-world namespaces.  Mirrors §2.2.")

(defconst dl-satan-memory-grammar-aliases
  '(("reference"     . "domain_kind:docs")
    ("manual"        . "domain_kind:docs")
    ("documentation" . "domain_kind:docs")
    ("tutorial"      . "domain_kind:learning")
    ("guide"         . "domain_kind:learning")
    ("howto"         . "domain_kind:learning"))
  "Alist (ALIAS . CANONICAL-HANDLE) for grammar v1.  Mirrors §2.3.")

(defconst dl-satan-memory-grammar-default-weights
  '((project            . 1)
    (surface            . 1)
    (app                . 1)
    (mode               . 1)
    (domain_kind        . 2)
    (file_kind          . 1)
    (event              . 2)
    (surface_transition . 3)
    (event_transition   . 3)
    (domain_transition  . 2)
    (artifact           . 3)
    (phase              . 2)
    (intervention       . 2)
    (outcome            . 3)
    (topic              . 1)
    (bough_kind         . 1)
    (bough_status       . 2)
    (bough_event        . 2)
    (bough_project      . 1)
    (bough_node         . 0)
    (workspace          . 1)
    (queue              . 1)
    (day                . 1)
    (week               . 1))
  "Alist (NAMESPACE . WEIGHT) — namespace default weights for v1.
Mirrors §2.4.  `bough_node = 0' is intentional (admit for audit; never
dominate scoring).")

(defun dl-satan-memory-grammar--ns-symbol (ns)
  (if (symbolp ns) ns (intern ns)))

(defun dl-satan-memory-grammar-namespace-world (ns)
  "Return `closed' or `open' for NS (symbol or string), or nil."
  (cdr (assq (dl-satan-memory-grammar--ns-symbol ns)
             dl-satan-memory-grammar-namespaces)))

(defun dl-satan-memory-grammar-closed-values (ns)
  "Return list of legal values for closed-world NS, or nil."
  (cdr (assq (dl-satan-memory-grammar--ns-symbol ns)
             dl-satan-memory-grammar-closed-values)))

(defun dl-satan-memory-grammar-alias-target (alias)
  "Return canonical handle string for ALIAS, or nil."
  (cdr (assoc alias dl-satan-memory-grammar-aliases)))

(defun dl-satan-memory-grammar-default-weight (ns)
  "Return default weight for NS (symbol or string), or nil."
  (cdr (assq (dl-satan-memory-grammar--ns-symbol ns)
             dl-satan-memory-grammar-default-weights)))

(defun dl-satan-memory-grammar-valid-value-p (ns value)
  "Return non-nil if VALUE is admissible for NS.
For closed-world NS, VALUE must be in the enum.  For open-world NS,
any non-empty string is admissible (slug normalization happens
upstream in the canonicalizer)."
  (let ((world (dl-satan-memory-grammar-namespace-world ns)))
    (pcase world
      ('closed (and (stringp value)
                    (member value (dl-satan-memory-grammar-closed-values ns))
                    t))
      ('open   (and (stringp value) (> (length value) 0)))
      (_ nil))))

(provide 'dl-satan-memory-grammar)
;;; dl-satan-memory-grammar.el ends here
