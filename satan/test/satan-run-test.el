;;; satan-run-test.el --- ert tests for satan-run -*- lexical-binding: t; -*-

;;; Commentary:
;; SL-013 PHASE-01 — characterisation of the surface PHASE-02 and PHASE-03
;; move.  `satan-run.el' shipped without a test file; the clones in
;; `satan-broker.el' are byte-identical to it modulo docstrings (design
;; §2.2), so a green suite cannot detect a surviving fork.  This file plus
;; the phase exit greps are the whole guard the collapse has.
;;
;; Covered: run-id minting and its optional TIME argument; both
;; `satan-run-dir-for-id' layouts (bucketed, and the legacy flat fallback);
;; the ten v0 keys of the run_ctx constructor; `satan-run-tool-ctx' reading
;; the *frozen* :time_now rather than minting a fresh one; and both
;; defcustoms deriving from `satan-notes-root'.
;;
;; TRAP, RESOLVED IN PHASE-02 (EVD-001, design §10).  `cl-defstruct
;; satan-run' generates the accessor `satan-run-prepare', over which
;; satan-run.el once defined a defun of the same name.  The accessor installs
;; a `compiler-macro' property that `defun' does not remove, so every
;; *syntactic* call in loaded source inlined to the slot read — interpreted
;; and byte-compiled alike — and PHASE-01 had to reach the constructor as
;; `(funcall 'satan-run-prepare MODE)' to characterise it at all.
;;
;; PHASE-02 renamed the defun to `satan-run-new-ctx', so `satan-run-prepare'
;; now has exactly one meaning (the accessor) and the constructor can be
;; called syntactically.  The `funcall' escape hatch was never stable anyway:
;; which definition won the function cell depended on load order, and any
;; module defining its own `cl-defstruct satan-run' after satan-run.el loaded
;; put the accessor back on top.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'cl-macs)                      ; cl-letf, in the tool-ctx spy
(require 'satan-run)

(defconst satan-run-test--id-re
  "\\`[0-9]\\{8\\}T[0-9]\\{6\\}-tick-[0-9a-f]\\{6\\}\\'"
  "Match a minted run-id for mode `tick': YYYYMMDDTHHMMSS-tick-<6 hex>.")

;; ── Run ID minting ──────────────────────────────────────────────────────────

(ert-deftest satan-run/mint-id-format ()
  "Ids are `YYYYMMDDTHHMMSS-<mode>-<6 hex>', unique per call."
  (should (string-match-p satan-run-test--id-re (satan-run-mint-id "tick")))
  ;; The mode name is embedded verbatim, hyphens and all.
  (should (string-match-p "-tick-pulse-" (satan-run-mint-id "tick-pulse")))
  ;; Exactly six hex digits — pins the `%06x'.
  (let ((suffix (car (last (split-string (satan-run-mint-id "tick") "-")))))
    (should (= (length suffix) 6)))
  ;; The random suffix distinguishes ids minted in the same second.
  (should-not (equal (satan-run-mint-id "tick") (satan-run-mint-id "tick"))))

(ert-deftest satan-run/mint-id-honours-time-argument ()
  "The optional TIME argument stamps the id, in place of `current-time'."
  (let* ((fixed (encode-time (list 30 15 22 31 5 2026 nil -1 nil)))
         (stamp (format-time-string "%Y%m%dT%H%M%S" fixed))
         (id    (satan-run-mint-id "tick" fixed)))
    (should (string-prefix-p (concat stamp "-tick-") id))
    ;; Same TIME, same 15-char stamp — only the random suffix moves.
    (should (equal (substring (satan-run-mint-id "tick" fixed) 0 15)
                   (substring id 0 15)))
    ;; An hour apart stamps differently.
    (should-not (equal (substring (satan-run-mint-id "tick" (time-add fixed 3600))
                                  0 15)
                       (substring id 0 15)))
    ;; And the argument is genuinely consulted, not ignored in favour of now.
    (should-not (equal (substring (satan-run-mint-id "tick") 0 15)
                       (substring id 0 15)))))

;; ── Run directory resolution ────────────────────────────────────────────────

(ert-deftest satan-run/dir-for-id-buckets-by-date ()
  "A minted id resolves under its `<runs>/<YYYY-MM-DD>/' bucket."
  (let ((id "20260520T163446-tick-pulse-5e8018"))
    (should (equal (satan-run-dir-for-id id "/runs")
                   (expand-file-name (concat "2026-05-20/" id) "/runs")))
    ;; RUNS-DIR is optional; `satan-runs-dir' is the default base.
    (let ((satan-runs-dir "/default-runs"))
      (should (equal (satan-run-dir-for-id id)
                     (expand-file-name (concat "2026-05-20/" id)
                                       "/default-runs"))))))

(ert-deftest satan-run/dir-for-id-falls-back-to-flat-layout ()
  "An id with no parsable date prefix resolves flat under the base."
  (should (equal (satan-run-dir-for-id "garbage" "/runs")
                 (expand-file-name "garbage" "/runs")))
  ;; Bucket-shaped but not `T'-terminated: still flat.
  (should (equal (satan-run-dir-for-id "2026-05-20-foo" "/runs")
                 (expand-file-name "2026-05-20-foo" "/runs")))
  ;; The bucket parser underneath is total over junk and nil.
  (should (equal (satan-run--date-bucket "20260520T163446-tick-5e8018")
                 "2026-05-20"))
  (should (null (satan-run--date-bucket "garbage")))
  (should (null (satan-run--date-bucket nil))))

(ert-deftest satan-run/failed-suffix-is-dot-failed ()
  "The suffix marking a run directory whose status is not `done'."
  (should (equal satan-run--failed-suffix ".FAILED")))

;; ── run_ctx constructor ─────────────────────────────────────────────────────

(ert-deftest satan-run/new-ctx-returns-ten-v0-keys ()
  "The v0 run_ctx shape: ten keys, in order, six of them placeholders.

Called syntactically: PHASE-02's rename left `satan-run-new-ctx' with no
struct accessor shadowing it, which is what EVD-001's trap cost us."
  (let* ((ctx  (satan-run-new-ctx '(:name "tick")))
         (keys (cl-loop for (k _v) on ctx by #'cddr collect k)))
    (should (equal keys '(:run_id :mode_name :time_now :start_time
                          :evidence :percept :sensor_status :pre_spawn
                          :motive :observer)))
    ;; Ten pairs and no more — the shape MCP's session prepare must match.
    (should (= (length ctx) 20))
    (dolist (k '(:evidence :percept :sensor_status :pre_spawn :motive :observer))
      (should (null (plist-get ctx k))))
    (should (equal (plist-get ctx :mode_name) "tick"))
    (should (string-match-p satan-run-test--id-re (plist-get ctx :run_id)))
    ;; :time_now is frozen off :start_time, not stamped independently.
    (should (equal (plist-get ctx :time_now)
                   (format-time-string satan-run--iso-time-format
                                       (plist-get ctx :start_time))))))

(ert-deftest satan-run/prepare-is-the-accessor-not-a-constructor ()
  "`satan-run-prepare' reads the slot; it never mints a run (design I2).

The regression guard for EVD-001.  While a defun of this name shadowed
the struct accessor, which one answered depended on load order and on
whether the caller went through `funcall' — so a caller could silently
get a fresh run-id and an unfrozen time instead of the run's own.  Any
module re-declaring `cl-defstruct satan-run' would flip it back."
  (let ((run (make-satan-run :prepare '(:run_id "frozen-rid"))))
    ;; Through `funcall', which is the path that reached the old defun.
    (should (equal (funcall 'satan-run-prepare run) '(:run_id "frozen-rid")))
    (should (equal (satan-run-prepare run) '(:run_id "frozen-rid"))))
  (should (fboundp 'satan-run-new-ctx)))

;; ── Tool context ────────────────────────────────────────────────────────────

(ert-deftest satan-run/tool-ctx-reads-frozen-time-now ()
  "tool-ctx reads the run's frozen `:time_now'; it never stamps a fresh one.

The observable the accessor/defun collision would have corrupted: a
constructor call here would return a new run-id and an unfrozen time."
  (let* ((mode    '(:name "morning" :capabilities (:read t)))
         (prepare (list :run_id "rid" :time_now "2026-01-01T00:00:00+0000"
                        :start_time (current-time)
                        :evidence nil :percept nil :sensor_status nil
                        :pre_spawn nil :motive nil :observer nil))
         (run-ctx (make-satan-run :id "rid" :mode mode :dir "/tmp/x"
                                  :audit 'AUDIT :prepare prepare))
         (satan-hippocampus-dir "/hippo")
         (called  nil))
    (cl-letf (((symbol-function 'format-time-string)
               (lambda (&rest args) (setq called args) "NEVER")))
      (let ((tool-ctx (satan-run-tool-ctx run-ctx)))
        (should (null called))
        (should (equal (cl-loop for (k _v) on tool-ctx by #'cddr collect k)
                       '(:id :mode-name :capabilities :run-dir :hippocampus-dir
                         :run-started-at :time-now :audit :percept-handles)))
        (should (equal (plist-get tool-ctx :time-now)
                       "2026-01-01T00:00:00+0000"))
        (should (equal (plist-get tool-ctx :run-started-at)
                       "2026-01-01T00:00:00+0000"))
        (should (equal (plist-get tool-ctx :id) "rid"))
        (should (equal (plist-get tool-ctx :mode-name) "morning"))
        (should (equal (plist-get tool-ctx :capabilities) '(:read t)))
        (should (equal (plist-get tool-ctx :run-dir) "/tmp/x"))
        (should (equal (plist-get tool-ctx :hippocampus-dir) "/hippo"))
        (should (eq (plist-get tool-ctx :audit) 'AUDIT))
        (should (null (plist-get tool-ctx :percept-handles)))))))

(ert-deftest satan-run/tool-ctx-surfaces-percept-handles ()
  "Percept handles reach handlers when the run carries a percept."
  (let ((run-ctx (make-satan-run
                  :id "rid" :mode '(:name "tick")
                  :prepare (list :time_now "2026-01-01T00:00:00+0000"
                                 :percept '(:handles ("h1" "h2"))))))
    (should (equal (plist-get (satan-run-tool-ctx run-ctx) :percept-handles)
                   '("h1" "h2")))))

;; ── Directories ─────────────────────────────────────────────────────────────

(ert-deftest satan-run/dirs-split-by-ownership ()
  "The two run directories derive from different roots, by ownership.
Run bundles are discardable runtime state and derive from `satan-state-root';
hippocampus is SATAN-authored, versioned content and derives from
`satan-corpus-root' (SL-015 design D3).  Neither is a literal: re-evaluating
the standard values under a rebound root moves each with its own root only."
  (should (equal satan-runs-dir (satan-state-path "runs")))
  (should (equal satan-hippocampus-dir (satan-corpus-path "hippocampus")))
  (let ((satan-state-root "/tmp/sr")
        (satan-corpus-root "/tmp/cr"))
    (should (equal (eval (car (get 'satan-runs-dir 'standard-value)) t)
                   "/tmp/sr/runs"))
    (should (equal (eval (car (get 'satan-hippocampus-dir 'standard-value)) t)
                   "/tmp/cr/hippocampus"))))

;; ── Run directory layout cluster (moved from satan-broker.el, PHASE-03) ────

(ert-deftest satan-run/id-from-leaf-strips-failed-suffix ()
  "Strips the trailing `.FAILED' suffix (if any) from a leaf dir name."
  (should (equal (satan-run--id-from-leaf
                  "20260520T163446-tick-pulse-5e8018.FAILED")
                 "20260520T163446-tick-pulse-5e8018"))
  (should (equal (satan-run--id-from-leaf
                  "20260520T163446-tick-pulse-5e8018")
                 "20260520T163446-tick-pulse-5e8018")))

(ert-deftest satan-run/list-dirs-walks-both-layouts ()
  "Enumerator returns paths for legacy flat and bucketed runs, plus FAILED."
  (let ((root (make-temp-file "satan-runs-list-" t)))
    (unwind-protect
        (let ((legacy   (expand-file-name "20260519T100000-x-aaaaaa" root))
              (legacy-f (expand-file-name "20260519T110000-x-bbbbbb.FAILED" root))
              (bucket   (expand-file-name "2026-05-20" root))
              (bucketed (expand-file-name
                         "2026-05-20/20260520T120000-x-cccccc" root))
              (bucketed-f (expand-file-name
                           "2026-05-20/20260520T130000-x-dddddd.FAILED" root))
              (noise    (expand-file-name "not-a-run-dir" root))
              (noise-bucket-child
               (expand-file-name "2026-05-20/scratch" root)))
          (dolist (d (list legacy legacy-f bucket bucketed bucketed-f
                           noise noise-bucket-child))
            (make-directory d t))
          (let ((got (satan-run-list-dirs root)))
            (should (member legacy got))
            (should (member legacy-f got))
            (should (member bucketed got))
            (should (member bucketed-f got))
            (should-not (member noise got))
            (should-not (member noise-bucket-child got))
            (should-not (cl-find-if (lambda (p)
                                      (equal (file-name-nondirectory p)
                                             "2026-05-20"))
                                    got))))
      (delete-directory root t))))

(ert-deftest satan-run/locate-dir-finds-failed-and-buckets ()
  "Locator falls back through bucketed, bucketed-FAILED, legacy, legacy-FAILED."
  (let ((root (make-temp-file "satan-runs-locate-" t)))
    (unwind-protect
        (progn
          (let ((d (expand-file-name "2026-05-20/20260520T100000-x-aaaaaa"
                                     root)))
            (make-directory d t)
            (should (equal (satan-run-locate-dir
                            "20260520T100000-x-aaaaaa" root)
                           d)))
          (let ((d (expand-file-name
                    "2026-05-20/20260520T110000-x-bbbbbb.FAILED" root)))
            (make-directory d t)
            (should (equal (satan-run-locate-dir
                            "20260520T110000-x-bbbbbb" root)
                           d)))
          (let ((d (expand-file-name "20260520T120000-x-cccccc" root)))
            (make-directory d t)
            (should (equal (satan-run-locate-dir
                            "20260520T120000-x-cccccc" root)
                           d)))
          (should (null (satan-run-locate-dir
                         "20260520T999999-nope-zzzzzz" root))))
      (delete-directory root t))))

(ert-deftest satan-run/dirs-for-date-matches-bucket-and-legacy ()
  "Filters `list-dirs' to a single date, honouring both layouts."
  (let ((root (make-temp-file "satan-runs-for-date-" t)))
    (unwind-protect
        (let ((bucketed (expand-file-name
                          "2026-05-20/20260520T120000-x-cccccc" root))
              (other-bucket (expand-file-name
                              "2026-05-21/20260521T010000-x-eeeeee" root))
              (legacy (expand-file-name "20260520T090000-x-aaaaaa" root))
              (legacy-other-day (expand-file-name
                                 "20260521T090000-x-ffffff" root)))
          (dolist (d (list bucketed other-bucket legacy legacy-other-day))
            (make-directory d t))
          (let ((got (satan-run-dirs-for-date root "20260520T")))
            (should (member bucketed got))
            (should (member legacy got))
            (should-not (member other-bucket got))
            (should-not (member legacy-other-day got))))
      (delete-directory root t))))

(provide 'satan-run-test)
;;; satan-run-test.el ends here
