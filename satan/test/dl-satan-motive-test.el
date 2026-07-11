;;; dl-satan-motive-test.el --- Phase 3 motive ert -*- lexical-binding: t; -*-

;; Phase 3 of perceptual-design.md.  Covers:
;;
;;   A7  motive_replace rejects payloads breaching ≤3 motives or
;;       ≤10 rumination lines with a structured error naming the bound.
;;   A8  footer parser accepts :cue: :cooldown_s: :worked_count:
;;       :last_intervention_at:; required :cue: missing → dormant;
;;       :ceiling: rejected (not a v0 field).
;;   A9  :worked_count: is informational — two motives differing only
;;       in :worked_count: produce the same capsule ordering.

(require 'ert)
(require 'cl-lib)
(require 'dl-satan-motive)

;; ---------------------------------------------------------------------
;; Fixtures
;; ---------------------------------------------------------------------

(defconst dl-satan-motive-test--well-formed
  "* test: docs-after-error
  Docs after terminal error often substitute orientation for contact.
  :cue: project:emacs.d surface_transition:terminal->browser domain_kind:docs
  :cooldown_s: 1800
  :worked_count: 0
  :last_intervention_at: 2026-05-21T14:02Z

* test: bough-status-drift
  When bough status changes accumulate without user attention.
  :cue: bough_event:status_changed app:firefox
  :cooldown_s: 3600
  :worked_count: 4

* ruminations
  - 2026-05-22  docs-after-error often artifactless when project is emacs.d
  - 2026-05-19  patch jobs accepted more when directive cites file path
"
  "Minimal valid motives.org fixture: 2 active motives + 2 ruminations.")

(defconst dl-satan-motive-test--well-formed-cwd
  "* test: docs-after-error
  Docs after terminal error often substitute orientation for contact.
  :cue: project:emacs.d surface_transition:terminal->browser domain_kind:docs
  :cooldown_s: 1800
  :worked_count: 0
  :last_intervention_at: 2026-05-21T14:02Z
  :project_cwd: ~/.emacs.d

* test: bough-status-drift
  When bough status changes accumulate without user attention.
  :cue: bough_event:status_changed app:firefox
  :cooldown_s: 3600
  :worked_count: 4

* ruminations
  - 2026-05-22  docs-after-error often artifactless when project is emacs.d
  - 2026-05-19  patch jobs accepted more when directive cites file path
"
  "Like `dl-satan-motive-test--well-formed', but docs-after-error carries
a `:project_cwd:' footer.  The §S5 P2 `:git_commit_observed' predicate
is repo-scoped and refuses to fire without a motive `:project_cwd', so
end-to-end observer tests that expect a positive git verdict use this
variant.")

(defconst dl-satan-motive-test--ceiling
  "* test: pestered
  This motive uses the forbidden v0 ceiling field.
  :cue: app:firefox
  :cooldown_s: 1800
  :ceiling: 5
"
  "Fixture exercising the §S3 deferred :ceiling: rejection (A8).")

(defconst dl-satan-motive-test--malformed-cue
  "* test: bad
  Cue token is not a canonical handle.
  :cue: not-a-valid-handle
  :cooldown_s: 1800
"
  "Fixture: `:cue:' contains an entry that fails the canon regex.")

(defconst dl-satan-motive-test--ctx-only-cue
  "* test: too-generic
  Cue contains only ctx-derived handles — the §S2 noise floor applies.
  :cue: project:emacs.d mode:motd day:2026-05-22
  :cooldown_s: 1800
"
  "Fixture: well-formed handles but none in the admit set.")

(defconst dl-satan-motive-test--with-project-cwd
  "* test: emacs-config-work
  Active editing of the emacs config.
  :cue: project:emacs.d app:emacs
  :cooldown_s: 1800
  :project_cwd: ~/.emacs.d
"
  "Fixture: well-formed motive carrying the Phase-5 `:project_cwd:'
footer field.  The observer needs an absolute cwd to scope its
positive-signal predicate; declaring it in the footer avoids any
reverse-lookup from the canonical `project:slug' handle.")

(defconst dl-satan-motive-test--four-actives
  "* test: a
  :cue: app:firefox
  :cooldown_s: 1800
* test: b
  :cue: app:firefox
  :cooldown_s: 1800
* test: c
  :cue: app:firefox
  :cooldown_s: 1800
* test: d
  :cue: app:firefox
  :cooldown_s: 1800
"
  "Fixture exercising the 3-active cap (§S3 / A7).")

(defun dl-satan-motive-test--n-ruminations (n)
  "Return a fixture string carrying N rumination lines."
  (concat "* test: ok\n  :cue: app:firefox\n  :cooldown_s: 1800\n"
          "* ruminations\n"
          (mapconcat (lambda (i)
                       (format "  - 2026-05-%02d  line %d" (1+ i) i))
                     (number-sequence 0 (1- n))
                     "\n")
          "\n"))

;; ---------------------------------------------------------------------
;; A8 — parser shape
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-motive/parse-accepts-all-footer-fields ()
  (let* ((parsed (dl-satan-motive-parse dl-satan-motive-test--well-formed))
         (motives (plist-get parsed :motives))
         (first (car motives)))
    (should (= 2 (length motives)))
    (should (equal "docs-after-error" (plist-get first :id)))
    (should (equal '("project:emacs.d"
                     "surface_transition:terminal->browser"
                     "domain_kind:docs")
                   (plist-get first :cue)))
    (should (= 1800 (plist-get first :cooldown_s)))
    (should (= 0    (plist-get first :worked_count)))
    (should (equal "2026-05-21T14:02Z"
                   (plist-get first :last_intervention_at)))
    (should (not (plist-get first :dormant)))))

(ert-deftest dl-satan-motive/parse-extracts-ruminations ()
  (let* ((parsed (dl-satan-motive-parse dl-satan-motive-test--well-formed))
         (rum (plist-get parsed :ruminations)))
    (should (= 2 (length rum)))
    (should (equal (car rum)
                   "2026-05-22  docs-after-error often artifactless when project is emacs.d"))))

(ert-deftest dl-satan-motive/parse-rejects-ceiling-field ()
  "A8 — :ceiling: is not a v0 field; parse flags it as a forbidden
error so the write-side guard can refuse the replacement.  The motive
itself is still returned (file-tolerated) for diagnostic rendering."
  (let* ((parsed (dl-satan-motive-parse dl-satan-motive-test--ceiling))
         (errors (plist-get parsed :errors)))
    (should (= 1 (length (plist-get parsed :motives))))
    (should (= 1 (length errors)))
    (should (eq :forbidden-field (plist-get (car errors) :kind)))
    (should (equal "pestered" (plist-get (car errors) :motive)))))

(ert-deftest dl-satan-motive/parse-marks-missing-cue-dormant ()
  "A8 — a motive without a `:cue:' is dormant (file-tolerated,
capsule-invisible, observer-skipped)."
  (let* ((text "* test: no-cue\n  Prose only.\n  :cooldown_s: 1800\n")
         (parsed (dl-satan-motive-parse text))
         (m (car (plist-get parsed :motives))))
    (should (plist-get m :dormant))
    (should (eq :missing-cue (plist-get m :dormant_reason)))))

(ert-deftest dl-satan-motive/parse-marks-malformed-cue-dormant ()
  (let* ((parsed (dl-satan-motive-parse dl-satan-motive-test--malformed-cue))
         (m (car (plist-get parsed :motives))))
    (should (plist-get m :dormant))
    (should (eq :malformed-cue (plist-get m :dormant_reason)))))

(ert-deftest dl-satan-motive/parse-marks-ctx-only-cue-dormant ()
  "§S3 — a cue with only ctx-derived handles fails admission (same
rationale as the §S2 resonance gate).  Without a sensor-observed
handle the motive triggers on every tick — defeats cooldown."
  (let* ((parsed (dl-satan-motive-parse dl-satan-motive-test--ctx-only-cue))
         (m (car (plist-get parsed :motives))))
    (should (plist-get m :dormant))
    (should (eq :no-sensor-handle (plist-get m :dormant_reason)))))

(ert-deftest dl-satan-motive/parse-missing-text-returns-empty ()
  "Silent self-suppression — missing/empty file is a valid state."
  (let ((parsed (dl-satan-motive-parse "")))
    (should (null (plist-get parsed :motives)))
    (should (null (plist-get parsed :ruminations)))
    (should (null (plist-get parsed :errors)))))

(ert-deftest dl-satan-motive/read-missing-file-returns-empty ()
  (let* ((tmp (make-temp-file "satan-motive-missing-"))
         (_ (delete-file tmp))
         (parsed (dl-satan-motive-read tmp)))
    (should (null (plist-get parsed :motives)))))

;; ---------------------------------------------------------------------
;; Phase 5.0 — :project_cwd: footer field
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-motive/parse-extracts-project-cwd ()
  "Phase 5.0 — `:project_cwd:' is parsed onto the motive plist as an
absolute path.  The observer's positive-signal predicate (§S5) uses
it to scope edit-detection to files under the motive's project; the
predicate cannot fire path-scoped sub-predicates without it."
  (let* ((parsed (dl-satan-motive-parse
                  dl-satan-motive-test--with-project-cwd))
         (m (car (plist-get parsed :motives))))
    (should (equal (expand-file-name "~/.emacs.d")
                   (plist-get m :project_cwd)))
    (should-not (plist-get m :dormant))))

(ert-deftest dl-satan-motive/parse-absent-project-cwd-is-nil ()
  "Motives that don't declare `:project_cwd:' parse with the slot
explicitly nil.  Such motives are still correlatable by handle
overlap; only the path-scoped sub-predicates (edits + git in the
motive's cwd) are skipped for them."
  (let* ((parsed (dl-satan-motive-parse
                  dl-satan-motive-test--well-formed))
         (m (car (plist-get parsed :motives))))
    (should (null (plist-get m :project_cwd)))))

(ert-deftest dl-satan-motive/parse-empty-project-cwd-is-nil ()
  "An empty `:project_cwd:' value is treated as absent (mirrors the
existing handling of `:last_intervention_at:').  Prevents an empty
string from being passed to file-name predicates as `/'."
  (let* ((text "* test: x\n  :cue: app:firefox\n  :cooldown_s: 1800\n  :project_cwd: \n")
         (m (car (plist-get (dl-satan-motive-parse text) :motives))))
    (should (null (plist-get m :project_cwd)))))

(ert-deftest dl-satan-motive/write-accepts-project-cwd ()
  "Phase 5.0 — the write-side guard accepts the new field."
  (should (null (dl-satan-motive-validate-for-write
                 dl-satan-motive-test--with-project-cwd))))

(ert-deftest dl-satan-motive/render-block-omits-project-cwd ()
  "`:project_cwd:' is observer-only metadata — capsule renderer does
not surface it to the model (avoids leaking host paths into prompts
and keeps the cooldown_s/worked_count line stable)."
  (let* ((framing '(("motive_block_header" . "# Motive")))
         (block (dl-satan-motive-render-block
                 framing
                 (dl-satan-motive-parse
                  dl-satan-motive-test--with-project-cwd))))
    (should block)
    (should-not (cl-some (lambda (l)
                           (string-match-p "project_cwd" l))
                         block))
    (should-not (cl-some (lambda (l)
                           (string-match-p (regexp-quote
                                            (expand-file-name "~/.emacs.d"))
                                           l))
                         block))))

;; ---------------------------------------------------------------------
;; A9 — worked_count is informational
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-motive/worked-count-does-not-reorder ()
  "A9 — two motives that differ only in `:worked_count:' must yield
the same capsule ordering (file order is the only ordering)."
  (let* ((framing '(("motive_block_header" . "# Motive")))
         (low "* test: alpha
  :cue: app:firefox
  :cooldown_s: 1800
  :worked_count: 0

* test: beta
  :cue: app:firefox
  :cooldown_s: 1800
  :worked_count: 99
")
         (high "* test: alpha
  :cue: app:firefox
  :cooldown_s: 1800
  :worked_count: 99

* test: beta
  :cue: app:firefox
  :cooldown_s: 1800
  :worked_count: 0
")
         (block-low (dl-satan-motive-render-block
                     framing (dl-satan-motive-parse low)))
         (block-high (dl-satan-motive-render-block
                      framing (dl-satan-motive-parse high)))
         (heads-low  (cl-remove-if-not
                      (lambda (l) (string-prefix-p "## " l))
                      block-low))
         (heads-high (cl-remove-if-not
                      (lambda (l) (string-prefix-p "## " l))
                      block-high)))
    (should (equal heads-low '("## alpha" "## beta")))
    (should (equal heads-high '("## alpha" "## beta")))))

;; ---------------------------------------------------------------------
;; Render
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-motive/render-block-shape ()
  (let* ((framing '(("motive_block_header" . "# Motive")))
         (block (dl-satan-motive-render-block
                 framing
                 (dl-satan-motive-parse dl-satan-motive-test--well-formed))))
    (should (equal (car block) "# Motive"))
    (should (member "## docs-after-error" block))
    (should (cl-some (lambda (l)
                       (string-match-p
                        "^  cue: project:emacs.d surface_transition:terminal->browser domain_kind:docs$"
                        l))
                     block))
    (should (cl-some (lambda (l)
                       (string-match-p
                        "^  cooldown_s: 1800  worked_count: 0  last_intervention_at: 2026-05-21T14:02Z$"
                        l))
                     block))))

(ert-deftest dl-satan-motive/render-block-omits-dormant ()
  "Dormant motives never render — §S3 says they are file-tolerated
but capsule-invisible."
  (let* ((framing '(("motive_block_header" . "# Motive")))
         (text (concat dl-satan-motive-test--well-formed
                       dl-satan-motive-test--malformed-cue))
         (block (dl-satan-motive-render-block
                 framing (dl-satan-motive-parse text)))
         (heads (cl-remove-if-not
                 (lambda (l) (string-prefix-p "## " l))
                 block)))
    (should (equal heads '("## docs-after-error" "## bough-status-drift")))
    (should-not (member "## bad" block))))

(ert-deftest dl-satan-motive/render-block-omits-when-no-active ()
  "Block self-suppresses with no active motives."
  (let* ((framing '(("motive_block_header" . "# Motive")))
         (block (dl-satan-motive-render-block
                 framing
                 (dl-satan-motive-parse
                  dl-satan-motive-test--malformed-cue))))
    (should (null block))))

(ert-deftest dl-satan-motive/render-block-without-framing-key-yields-nil ()
  "Mind owns the header text; absent key suppresses the section."
  (let* ((framing '(("percept_block_header" . "# Percept")))
         (parsed (dl-satan-motive-parse dl-satan-motive-test--well-formed)))
    (should (null (dl-satan-motive-render-block framing parsed)))))

;; ---------------------------------------------------------------------
;; Render — cooldown floor (Phase 6, §S4)
;; ---------------------------------------------------------------------

(defconst dl-satan-motive-test--cooldown-fixture
  "* test: docs-after-error
  Docs after terminal error often substitute orientation for contact.
  :cue: project:emacs.d surface_transition:terminal->browser domain_kind:docs
  :cooldown_s: 1800
  :worked_count: 0
  :last_intervention_at: 2026-05-23T10:00:00+1000
"
  "Single-motive fixture with `:cooldown_s: 1800' and a fixed
`:last_intervention_at:'.  Tests vary NOW relative to this baseline.")

(ert-deftest dl-satan-motive/render-block-cooling-down-annotates-header ()
  "§S4 — within cooldown, the motive's `## id' header gains a
`[cooling-down (Nm remaining)]' tag while prose / cue / footer stay
intact.  Baseline last_intervention_at + 12m → 18m remaining of 30m."
  (let* ((framing '(("motive_block_header" . "# Motive")))
         (parsed (dl-satan-motive-parse dl-satan-motive-test--cooldown-fixture))
         (now    "2026-05-23T10:12:00+1000")
         (block  (dl-satan-motive-render-block framing parsed now)))
    (should (cl-some (lambda (l)
                       (string-match-p
                        "^## docs-after-error  \\[cooling-down (18m remaining)\\]$"
                        l))
                     block))
    (should (member
             "  cue: project:emacs.d surface_transition:terminal->browser domain_kind:docs"
             block))
    (should (cl-some (lambda (l)
                       (string-match-p
                        "^  cooldown_s: 1800  worked_count: 0  last_intervention_at: 2026-05-23T10:00:00\\+1000$"
                        l))
                     block))))

(ert-deftest dl-satan-motive/render-block-cooldown-elapsed-renders-actionable ()
  "§S4 — once `(now - last_intervention_at) >= cooldown_s', the motive
renders actionable (no annotation, bare `## id' header)."
  (let* ((framing '(("motive_block_header" . "# Motive")))
         (parsed (dl-satan-motive-parse dl-satan-motive-test--cooldown-fixture))
         (now    "2026-05-23T10:31:00+1000")
         (block  (dl-satan-motive-render-block framing parsed now)))
    (should (member "## docs-after-error" block))
    (should-not (cl-some (lambda (l)
                           (string-match-p "cooling-down" l))
                         block))))

(ert-deftest dl-satan-motive/render-block-no-last-intervention-renders-actionable ()
  "A motive that has never fired has no floor to enforce — even with
NOW supplied, the header is bare."
  (let* ((framing '(("motive_block_header" . "# Motive")))
         (text   "* test: never-fired
  Has not yet correlated to any intervention.
  :cue: project:emacs.d surface_transition:terminal->browser
  :cooldown_s: 1800
  :worked_count: 0
")
         (parsed (dl-satan-motive-parse text))
         (now    "2026-05-23T10:12:00+1000")
         (block  (dl-satan-motive-render-block framing parsed now)))
    (should (member "## never-fired" block))
    (should-not (cl-some (lambda (l)
                           (string-match-p "cooling-down" l))
                         block))))

(ert-deftest dl-satan-motive/render-block-no-cooldown-renders-actionable ()
  "Without `:cooldown_s:' the floor is unconfigured — the motive
remains actionable regardless of NOW or `:last_intervention_at:'."
  (let* ((framing '(("motive_block_header" . "# Motive")))
         (text   "* test: floor-less
  Author has not declared a cooldown.
  :cue: project:emacs.d surface_transition:terminal->browser
  :worked_count: 0
  :last_intervention_at: 2026-05-23T10:00:00+1000
")
         (parsed (dl-satan-motive-parse text))
         (now    "2026-05-23T10:12:00+1000")
         (block  (dl-satan-motive-render-block framing parsed now)))
    (should (member "## floor-less" block))
    (should-not (cl-some (lambda (l)
                           (string-match-p "cooling-down" l))
                         block))))

;; ---------------------------------------------------------------------
;; A7 — write-side bounds
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-motive/write-rejects-too-many-actives ()
  (let ((err (dl-satan-motive-validate-for-write
              dl-satan-motive-test--four-actives)))
    (should (eq :too-many-active (plist-get err :bound)))
    (should (= 3 (plist-get err :limit)))
    (should (= 4 (plist-get err :got)))
    (should (string-match-p "too many active motives: limit 3, got 4"
                            (dl-satan-motive-format-write-error err)))))

(ert-deftest dl-satan-motive/write-rejects-too-many-ruminations ()
  (let* ((text (dl-satan-motive-test--n-ruminations 11))
         (err (dl-satan-motive-validate-for-write text)))
    (should (eq :too-many-ruminations (plist-get err :bound)))
    (should (= 10 (plist-get err :limit)))
    (should (= 11 (plist-get err :got)))))

(ert-deftest dl-satan-motive/write-rejects-ceiling-field ()
  (let ((err (dl-satan-motive-validate-for-write
              dl-satan-motive-test--ceiling)))
    (should (eq :forbidden-field (plist-get err :bound)))
    (should (equal "pestered" (plist-get err :motive)))
    (should (equal "ceiling" (plist-get err :field)))
    (should (string-match-p "forbidden field"
                            (dl-satan-motive-format-write-error err)))))

(ert-deftest dl-satan-motive/write-rejects-malformed-cue ()
  "A8 — a motive declaring a cue must declare a *valid* cue.
Missing cue → dormant on read but accepted on write (the author
might be staging work).  Malformed cue → write rejected so the
author cannot ship garbage handles to the substrate."
  (let ((err (dl-satan-motive-validate-for-write
              dl-satan-motive-test--malformed-cue)))
    (should (eq :invalid-cue (plist-get err :bound)))
    (should (equal "bad" (plist-get err :motive)))
    (should (eq :malformed-cue (plist-get err :reason)))))

(ert-deftest dl-satan-motive/write-rejects-ctx-only-cue ()
  "Cue without a sensor-observed handle is rejected on write —
otherwise the motive would silently degrade to dormant on read and
the author would not see why."
  (let ((err (dl-satan-motive-validate-for-write
              dl-satan-motive-test--ctx-only-cue)))
    (should (eq :invalid-cue (plist-get err :bound)))
    (should (eq :no-sensor-handle (plist-get err :reason)))))

(ert-deftest dl-satan-motive/write-accepts-well-formed ()
  (should (null (dl-satan-motive-validate-for-write
                 dl-satan-motive-test--well-formed))))

(ert-deftest dl-satan-motive/write-accepts-exactly-three-actives ()
  "Boundary: 3 actives + 10 ruminations is the limit, not over it."
  (let* ((three "* test: a\n  :cue: app:firefox\n  :cooldown_s: 1800\n* test: b\n  :cue: app:firefox\n  :cooldown_s: 1800\n* test: c\n  :cue: app:firefox\n  :cooldown_s: 1800\n")
         (ten (dl-satan-motive-test--n-ruminations 10)))
    (should (null (dl-satan-motive-validate-for-write three)))
    (should (null (dl-satan-motive-validate-for-write ten)))))

(ert-deftest dl-satan-motive/write-accepts-missing-cue ()
  "A motive without a cue at all is a draft — author staging work.
The write path tolerates it; the read path renders it dormant."
  (let ((text "* test: drafting\n  Prose only.\n  :cooldown_s: 1800\n"))
    (should (null (dl-satan-motive-validate-for-write text)))))

;; ---------------------------------------------------------------------
;; A7 precedence — first breach in `dl-satan-motive-bound-precedence' wins
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-motive/bound-precedence-shape ()
  "Document-visible precedence constant exists with the expected
order — forbidden-field > count caps > invalid-cue (A7)."
  (should (equal dl-satan-motive-bound-precedence
                 '(:forbidden-field :too-many-active
                   :too-many-ruminations :invalid-cue))))

(ert-deftest dl-satan-motive/write-precedence-forbidden-beats-count ()
  "Payload that uses `:ceiling:' *and* has too many actives must
report forbidden-field first — the author can't slip a v0-deferred
field through a fix-the-count edit."
  (let* ((bad (concat "* test: a\n  :cue: app:firefox\n  :ceiling: 5\n"
                      "* test: b\n  :cue: app:firefox\n  :cooldown_s: 1800\n"
                      "* test: c\n  :cue: app:firefox\n  :cooldown_s: 1800\n"
                      "* test: d\n  :cue: app:firefox\n  :cooldown_s: 1800\n"))
         (err (dl-satan-motive-validate-for-write bad)))
    (should (eq :forbidden-field (plist-get err :bound)))))

(ert-deftest dl-satan-motive/write-precedence-count-beats-invalid-cue ()
  "Payload with 4 well-formed actives *and* a separate motive
declaring a malformed cue reports the count breach first — author
trims before tightening cues.  (A motive with a malformed cue is
itself dormant so it does not contribute to the active count; the
collision arises when too-many valid actives sit beside a bad-cue
draft.)"
  (let* ((bad (concat "* test: a\n  :cue: app:firefox\n  :cooldown_s: 1800\n"
                      "* test: b\n  :cue: app:firefox\n  :cooldown_s: 1800\n"
                      "* test: c\n  :cue: app:firefox\n  :cooldown_s: 1800\n"
                      "* test: d\n  :cue: app:firefox\n  :cooldown_s: 1800\n"
                      "* test: bad-draft\n  :cue: not-a-valid-handle\n  :cooldown_s: 1800\n"))
         (err (dl-satan-motive-validate-for-write bad)))
    (should (eq :too-many-active (plist-get err :bound)))))

(ert-deftest dl-satan-motive/write-precedence-active-beats-ruminations ()
  "When both count caps trip, active-cap reports first."
  (let* ((bad (concat (mapconcat
                       (lambda (id)
                         (format "* test: %s\n  :cue: app:firefox\n  :cooldown_s: 1800\n"
                                 id))
                       '("a" "b" "c" "d") "")
                      "* ruminations\n"
                      (mapconcat
                       (lambda (i)
                         (format "  - 2026-05-%02d  line %d" (1+ i) i))
                       (number-sequence 0 10) "\n")
                      "\n"))
         (err (dl-satan-motive-validate-for-write bad)))
    (should (eq :too-many-active (plist-get err :bound)))))

(ert-deftest dl-satan-motive/write-invalid-cue-reports-first-bad-motive ()
  "Iteration order is file order — `cl-some' reports the first
breaching motive, not an arbitrary one."
  (let* ((bad (concat
               "* test: clean\n  :cue: app:firefox\n  :cooldown_s: 1800\n"
               "* test: first-bad\n  :cue: not-canonical\n  :cooldown_s: 1800\n"
               "* test: second-bad\n  :cue: also-bad\n  :cooldown_s: 1800\n"))
         (err (dl-satan-motive-validate-for-write bad)))
    (should (eq :invalid-cue (plist-get err :bound)))
    (should (equal "first-bad" (plist-get err :motive)))))

;; ---------------------------------------------------------------------
;; A7 prose surface — every bound formats with its name in the message
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-motive/format-error-names-every-bound ()
  "The model-facing error string surfaces the bound name (A7).
Round-trip every precedence entry through a synthetic plist and
assert the formatter mentions it."
  (let ((cases
         '((:forbidden-field
            (:bound :forbidden-field :motive "x" :field "ceiling")
            "forbidden field")
           (:too-many-active
            (:bound :too-many-active :limit 3 :got 4)
            "too many active motives")
           (:too-many-ruminations
            (:bound :too-many-ruminations :limit 10 :got 11)
            "too many rumination lines")
           (:invalid-cue
            (:bound :invalid-cue :motive "x" :reason :malformed-cue)
            "invalid :cue:"))))
    (dolist (case cases)
      (let ((bound (nth 0 case))
            (err (nth 1 case))
            (needle (nth 2 case)))
        (should (string-match-p
                 (regexp-quote needle)
                 (dl-satan-motive-format-write-error err)))
        (ignore bound)))))

;; ---------------------------------------------------------------------
;; Capsule integration (Phase 3.3) — block lands between resonance and today
;; ---------------------------------------------------------------------

(require 'dl-satan-context)

(defmacro dl-satan-motive-test--with-framing (tmp-sym &rest body)
  "Bind TMP-SYM to a tmp dir; seed scaffold + framing (with motive
key) + a motd prompt; rebind the framing/scaffold defcustoms for
BODY's dynamic extent.  Mirrors the resonance-test framing fixture
so the two block tests use parallel scaffolding."
  (declare (indent 1))
  `(let* ((,tmp-sym (make-temp-file "satan-motive-cap-" t))
          (dl-satan-system-scaffold-file
           (expand-file-name "system/scaffold.txt" ,tmp-sym))
          (dl-satan-system-framing-file
           (expand-file-name "system/framing.txt" ,tmp-sym)))
     (unwind-protect
         (progn
           (make-directory (expand-file-name "prompts" ,tmp-sym))
           (make-directory (expand-file-name "system" ,tmp-sym))
           (with-temp-file dl-satan-system-scaffold-file (insert "SCAFFOLD"))
           (with-temp-file dl-satan-system-framing-file
             (insert "now=# Now\n"
                     "percept_block_header=# Percept\n"
                     "resonance_block_header=# Resonance\n"
                     "motive_block_header=# Motive\n"
                     "today=# Today (raw)\n"
                     "sources=# Source files\n"
                     "recent_runs=# Recent SATAN runs\n"))
           (with-temp-file (expand-file-name "prompts/motd.txt" ,tmp-sym)
             (insert "PROMPT"))
           ,@body)
       (delete-directory ,tmp-sym t))))

(ert-deftest dl-satan-motive/capsule-renders-motive-between-resonance-and-today ()
  "Phase 3.3 — when PREPARE carries a `:motive' with ≥1 active motive,
the rendered prompt contains a `# Motive' block.  Placement is
between `# Resonance' and `# Today (raw)' per §S1 sequence."
  (dl-satan-motive-test--with-framing tmp
    (let* ((spec (list :name "motd"
                       :prompt-file
                       (expand-file-name "prompts/motd.txt" tmp)))
           (prepare (list :run_id "rid-x"
                          :time_now "2026-05-22T10:00:00+10:00"
                          :percept '(:handles ("app:firefox"))
                          :resonance
                          (list :status 'ok
                                :cue '("app:firefox")
                                :matches
                                '((:trace_id "20260518T120000-aaa"
                                   :score 11.2
                                   :matched_handles ("app:firefox"))))
                          :motive
                          (dl-satan-motive-parse
                           dl-satan-motive-test--well-formed)))
           (bundle (dl-satan-context-motd spec prepare))
           (prompt (plist-get bundle :prompt))
           (idx-resonance (string-match "^# Resonance$" prompt))
           (idx-motive (string-match "^# Motive$" prompt))
           (idx-today (or (string-match "^# Today (raw)$" prompt)
                          most-positive-fixnum)))
      (should idx-resonance)
      (should idx-motive)
      (should (< idx-resonance idx-motive))
      (should (< idx-motive idx-today))
      (should (string-match-p "^## docs-after-error$" prompt)))))

(ert-deftest dl-satan-motive/capsule-omits-motive-when-empty ()
  "§S3 silent self-suppression — empty motive parse (e.g. missing
file) → no `# Motive' header."
  (dl-satan-motive-test--with-framing tmp
    (let* ((spec (list :name "motd"
                       :prompt-file
                       (expand-file-name "prompts/motd.txt" tmp)))
           (prepare (list :run_id "rid-y"
                          :time_now "2026-05-22T10:00:00+10:00"
                          :motive '(:motives nil :ruminations nil
                                    :errors nil)))
           (bundle (dl-satan-context-motd spec prepare))
           (prompt (plist-get bundle :prompt)))
      (should-not (string-match-p "^# Motive$" prompt)))))

(ert-deftest dl-satan-motive/capsule-omits-when-only-dormant ()
  "A file containing only dormant motives renders no actionable
block.  Matches the §S3 file-tolerated / capsule-invisible split."
  (dl-satan-motive-test--with-framing tmp
    (let* ((spec (list :name "motd"
                       :prompt-file
                       (expand-file-name "prompts/motd.txt" tmp)))
           (prepare (list :run_id "rid-z"
                          :time_now "2026-05-22T10:00:00+10:00"
                          :motive
                          (dl-satan-motive-parse
                           dl-satan-motive-test--malformed-cue)))
           (bundle (dl-satan-context-motd spec prepare))
           (prompt (plist-get bundle :prompt)))
      (should-not (string-match-p "^# Motive$" prompt)))))

;; ---------------------------------------------------------------------
;; with-prepare mirror (Phase 3.3) — :motive joins :percept and :resonance
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-motive/with-prepare-mirrors-motive-slot ()
  (let* ((parsed (dl-satan-motive-parse
                  dl-satan-motive-test--well-formed))
         (prepare (list :run_id "rid"
                        :time_now "2026-05-22T10:00:00+10:00"
                        :percept '(:handles ("app:firefox"))
                        :resonance '(:status no-match)
                        :motive parsed))
         (bundle (dl-satan-context--with-prepare '() prepare)))
    (should (equal parsed (plist-get bundle :motive)))
    (should (equal "rid" (plist-get bundle :run_id)))
    (should (equal "2026-05-22T10:00:00+10:00"
                   (plist-get bundle :time_now)))))

;; ---------------------------------------------------------------------
;; Phase 5.5 — footer rewriter
;; ---------------------------------------------------------------------

(defmacro dl-satan-motive-test--with-tmp-file (var text &rest body)
  "Bind VAR to a temp file containing TEXT; clean up after BODY."
  (declare (indent 2))
  `(let* ((,var (make-temp-file "satan-motive-touch-" nil ".org"))
          (coding-system-for-write 'utf-8))
     (unwind-protect
         (progn
           (with-temp-file ,var (insert ,text))
           ,@body)
       (when (file-exists-p ,var) (delete-file ,var))
       (when (file-exists-p (concat ,var ".tmp"))
         (delete-file (concat ,var ".tmp"))))))

(defun dl-satan-motive-test--read (path)
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8))
      (insert-file-contents path))
    (buffer-string)))

(ert-deftest dl-satan-motive/touch-footer-replaces-worked-count-in-place ()
  "Existing `:worked_count:' line is replaced; indentation preserved."
  (dl-satan-motive-test--with-tmp-file path
      dl-satan-motive-test--well-formed
    (should (dl-satan-motive-touch-footer
             "docs-after-error" 7 "2026-05-22T10:30:00+1000" path))
    (let ((out (dl-satan-motive-test--read path)))
      (should (string-match-p "  :worked_count: 7\n" out))
      (should-not (string-match-p ":worked_count: 0" out))
      ;; Indentation preserved (`  ' two-space prefix on existing line).
      (should (string-match-p "\n  :worked_count: 7\n" out)))))

(ert-deftest dl-satan-motive/touch-footer-replaces-last-intervention-at ()
  "Existing `:last_intervention_at:' line gets the new ISO."
  (dl-satan-motive-test--with-tmp-file path
      dl-satan-motive-test--well-formed
    (dl-satan-motive-touch-footer
     "docs-after-error" 1 "2026-05-22T10:30:00+1000" path)
    (let ((out (dl-satan-motive-test--read path)))
      (should (string-match-p
               "  :last_intervention_at: 2026-05-22T10:30:00\\+1000\n"
               out))
      (should-not (string-match-p "2026-05-21T14:02Z" out)))))

(ert-deftest dl-satan-motive/touch-footer-appends-missing-fields ()
  "Motive lacking both fields gets them inserted after the last
existing footer line."
  (dl-satan-motive-test--with-tmp-file path
      dl-satan-motive-test--well-formed
    ;; bough-status-drift has no :worked_count: 4 line above, actually
    ;; check the fixture — it has worked_count but no last_intervention_at.
    (dl-satan-motive-touch-footer
     "bough-status-drift" 5 "2026-05-22T10:30:00+1000" path)
    (let ((out (dl-satan-motive-test--read path)))
      (should (string-match-p ":worked_count: 5" out))
      (should (string-match-p
               ":last_intervention_at: 2026-05-22T10:30:00\\+1000"
               out))
      ;; Inserted last_intervention_at should land after the existing
      ;; worked_count line within the same section, not in
      ;; docs-after-error's section.
      (should (string-match-p
               (concat ":worked_count: 5\n"
                       ":last_intervention_at: 2026-05-22T10:30:00\\+1000")
               out)))))

(ert-deftest dl-satan-motive/touch-footer-preserves-prose-and-ruminations ()
  "Prose, ruminations, and ordering must round-trip verbatim."
  (dl-satan-motive-test--with-tmp-file path
      dl-satan-motive-test--well-formed
    (dl-satan-motive-touch-footer
     "docs-after-error" 9 "2026-05-22T10:30:00+1000" path)
    (let ((out (dl-satan-motive-test--read path)))
      ;; Prose lines verbatim.
      (should (string-match-p
               "Docs after terminal error often substitute orientation for contact\\."
               out))
      (should (string-match-p
               "When bough status changes accumulate without user attention\\."
               out))
      ;; Ruminations verbatim.
      (should (string-match-p
               "- 2026-05-22  docs-after-error often artifactless when project is emacs\\.d"
               out))
      ;; Sibling motive's footer untouched.
      (should (string-match-p ":cooldown_s: 3600\n  :worked_count: 4\n"
                              out)))))

(ert-deftest dl-satan-motive/touch-footer-only-mutates-target-section ()
  "An update on docs-after-error must not touch bough-status-drift's
worked_count, even though both sections have one."
  (dl-satan-motive-test--with-tmp-file path
      dl-satan-motive-test--well-formed
    (dl-satan-motive-touch-footer
     "docs-after-error" 42 "2026-05-22T10:30:00+1000" path)
    (let ((out (dl-satan-motive-test--read path)))
      (should (string-match-p ":worked_count: 42" out))
      ;; Sibling unchanged.
      (should (string-match-p ":worked_count: 4\n" out))
      (should-not (string-match-p ":worked_count: 4 *2026" out)))))

(ert-deftest dl-satan-motive/touch-footer-unknown-id-returns-nil ()
  "Unknown motive id yields nil and leaves the file untouched."
  (dl-satan-motive-test--with-tmp-file path
      dl-satan-motive-test--well-formed
    (let ((before (dl-satan-motive-test--read path)))
      (should-not (dl-satan-motive-touch-footer
                   "nonexistent-motive" 1 "2026-05-22T10:30:00+1000" path))
      (should (equal before (dl-satan-motive-test--read path))))))

(ert-deftest dl-satan-motive/touch-footer-missing-file-returns-nil ()
  "Missing file is a valid state; rewriter is silent."
  (let ((path "/tmp/satan-motive-test-does-not-exist.org"))
    (when (file-exists-p path) (delete-file path))
    (should-not (dl-satan-motive-touch-footer
                 "anything" 1 "2026-05-22T10:30:00+1000" path))))

(ert-deftest dl-satan-motive/touch-footer-roundtrips-through-parse ()
  "After touch-footer, `dl-satan-motive-parse' on the file yields the
expected updated values."
  (dl-satan-motive-test--with-tmp-file path
      dl-satan-motive-test--well-formed
    (dl-satan-motive-touch-footer
     "docs-after-error" 11 "2026-05-22T10:30:00+1000" path)
    (let* ((parsed (dl-satan-motive-parse (dl-satan-motive-test--read path)))
           (target (cl-find "docs-after-error"
                            (plist-get parsed :motives)
                            :key (lambda (m) (plist-get m :id))
                            :test #'equal))
           (sibling (cl-find "bough-status-drift"
                             (plist-get parsed :motives)
                             :key (lambda (m) (plist-get m :id))
                             :test #'equal)))
      (should (= 11 (plist-get target :worked_count)))
      (should (equal "2026-05-22T10:30:00+1000"
                     (plist-get target :last_intervention_at)))
      (should (= 4 (plist-get sibling :worked_count))))))

(ert-deftest dl-satan-motive/touch-footer-no-trailing-newline-handled ()
  "Files without a trailing newline still rewrite cleanly — common
on hand-edited org files."
  (dl-satan-motive-test--with-tmp-file path
      (substring dl-satan-motive-test--well-formed 0
                 (1- (length dl-satan-motive-test--well-formed)))
    (should (dl-satan-motive-touch-footer
             "docs-after-error" 3 "2026-05-22T10:30:00+1000" path))
    (let ((parsed (dl-satan-motive-parse
                   (dl-satan-motive-test--read path))))
      (should (= 3 (plist-get (car (plist-get parsed :motives))
                              :worked_count))))))

(provide 'dl-satan-motive-test)
;;; dl-satan-motive-test.el ends here
