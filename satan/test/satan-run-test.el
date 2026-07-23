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
;; TRAP (EVD-001, design §10).  `cl-defstruct satan-run' generates the
;; accessor `satan-run-prepare'; satan-run.el:77 then defines a defun over
;; that same symbol.  The accessor installs a `compiler-macro' property that
;; `defun' does not remove, so every *syntactic* call in loaded source
;; inlines to the slot read — interpreted and byte-compiled alike.  Only
;; `funcall' / `apply' / `eval' reach the defun.  The constructor is
;; therefore reached below as `(funcall 'satan-run-prepare MODE)'; a
;; syntactic call would silently test the accessor instead.

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

Reached through `funcall'.  A syntactic call would inline the struct
accessor of the same name (EVD-001) and characterise the wrong function."
  (let* ((ctx  (funcall 'satan-run-prepare '(:name "tick")))
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

(ert-deftest satan-run/dirs-default-under-notes-root ()
  "Both run directories derive from `satan-notes-root', not from literals."
  (should (equal satan-runs-dir
                 (expand-file-name "satan/runs" satan-notes-root)))
  (should (equal satan-hippocampus-dir
                 (expand-file-name "satan/hippocampus" satan-notes-root)))
  ;; Re-evaluating the standard values under a different root moves both:
  ;; the defaults are derivations, not paths frozen at load.
  (let ((satan-notes-root "/tmp/nr"))
    (should (equal (eval (car (get 'satan-runs-dir 'standard-value)) t)
                   "/tmp/nr/satan/runs"))
    (should (equal (eval (car (get 'satan-hippocampus-dir 'standard-value)) t)
                   "/tmp/nr/satan/hippocampus"))))

(provide 'satan-run-test)
;;; satan-run-test.el ends here
