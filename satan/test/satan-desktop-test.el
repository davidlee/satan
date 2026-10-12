;;; satan-desktop-test.el --- the raw desktop reader (SL-021) -*- lexical-binding: t; -*-

;; `satan-desktop-at' against raw desktop day files written into a
;; scratch behaviour root by `satan-desktop-fixture'.  Pure: temp dirs
;; only, never the host's behaviour root.  Every test runs under
;; `satan-desktop-fixture-with-root', which pins `satan-desktop--zone'
;; to +10:00, the offset the fixture timestamps carry.

;;; Code:

(require 'ert)
(require 'satan-desktop)
(require 'satan-desktop-fixture)

;; ── helpers ─────────────────────────────────────────────────────────────────

(defconst satan-desktop-test--day "2026-09-26"
  "The day most cases write: a +10:00 date, so TIMEs below are 2026-09-26.")

(defconst satan-desktop-test--term
  '(:window_id "0000000000000000000000000000a001"
               :app_id "com.mitchellh.ghostty" :pid 1001
               :title "~/dev/alpha" :workspace "emacs" :output "DP-1")
  "A synthetic focused terminal: every state key, in panopticon's order.")

(defconst satan-desktop-test--browser
  '(:window_id "0000000000000000000000000000b002"
               :app_id "firefox" :pid 2002
               :title "Synthetic page" :workspace "web" :output "DP-1")
  "A second synthetic window, to tell two decisions apart.")

(defun satan-desktop-test--ev (ts event &optional state &rest extra)
  "A raw EVENT at TS carrying the STATE plist, then EXTRA fields."
  (apply #'satan-desktop-fixture-event ts event (append state extra)))

(defun satan-desktop-test--window (state ts)
  "The window `satan-desktop-at' returns for STATE decided at TS."
  (append state (list :since ts)))

(defun satan-desktop-test--at-day (events time)
  "`satan-desktop-at' at TIME over EVENTS as the one day file."
  (satan-desktop-fixture-with-root root
    (satan-desktop-fixture-write root satan-desktop-test--day events)
    (satan-desktop-at root time)))

(defun satan-desktop-test--ok-iff-window (result)
  "Assert the reader's invariant on RESULT: \"ok\" iff a window."
  (should (eq (equal "ok" (car result)) (and (cdr result) t))))

;; ── VT-8: the fixture module ────────────────────────────────────────────────

(ert-deftest satan-desktop/fixture-event-is-raw-key-order ()
  "VT-8 — `satan-desktop-fixture-event' builds the envelope first, in
panopticon's order, defaulting the producer to umbriel."
  (should (equal (satan-desktop-fixture-event
                  "2026-09-26T09:00:00.000+10:00" "window_title"
                  :title "t" :workspace "w")
                 '(:v 1 :ts "2026-09-26T09:00:00.000+10:00" :source "desktop"
                      :event "window_title" :producer "umbriel"
                      :title "t" :workspace "w"))))

(ert-deftest satan-desktop/fixture-event-producer-overrides-in-place ()
  "VT-8 — a `:producer' field takes the envelope slot; no duplicate key."
  (should (equal (satan-desktop-fixture-event
                  "2026-09-26T09:00:00+10:00" "window_focus"
                  :workspace "1" :producer "niri")
                 '(:v 1 :ts "2026-09-26T09:00:00+10:00" :source "desktop"
                      :event "window_focus" :producer "niri"
                      :workspace "1"))))

(ert-deftest satan-desktop/fixture-write-lays-out-the-raw-day-file ()
  "VT-8 — `satan-desktop-fixture-write' writes ROOT/raw/desktop-DAY.jsonl,
one line per element, strings verbatim, and overwrites on a second call."
  (satan-desktop-fixture-with-root root
    (let ((path (satan-desktop-fixture-write
                 root "2026-09-26"
                 (list (satan-desktop-fixture-event "T1" "snapshot")
                       "{\"torn"))))
      (should (equal path (expand-file-name "raw/desktop-2026-09-26.jsonl"
                                            root)))
      (should (equal (with-temp-buffer
                       (insert-file-contents path)
                       (buffer-string))
                     (concat "{\"v\":1,\"ts\":\"T1\",\"source\":\"desktop\","
                             "\"event\":\"snapshot\",\"producer\":\"umbriel\"}\n"
                             "{\"torn\n")))
      (satan-desktop-fixture-write root "2026-09-26" '("x"))
      (should (equal (with-temp-buffer
                       (insert-file-contents path)
                       (buffer-string))
                     "x\n")))))

;; ── VT-1: the last state event at or before T ───────────────────────────────

(ert-deftest satan-desktop/at-returns-the-last-state-at-or-before-t ()
  "VT-1 — `satan-desktop-at' answers with the last event at or before T,
not a later one; `:since' is that event's `ts', verbatim."
  (let ((events (list (satan-desktop-test--ev "2026-09-26T09:00:00.120+10:00"
                                              "window_focus"
                                              satan-desktop-test--term)
                      (satan-desktop-test--ev "2026-09-26T09:10:00.450+10:00"
                                              "window_focus"
                                              satan-desktop-test--browser))))
    (should (equal (satan-desktop-test--at-day events
                                               "2026-09-26T09:05:00+10:00")
                   (cons "ok" (satan-desktop-test--window
                               satan-desktop-test--term
                               "2026-09-26T09:00:00.120+10:00"))))
    (should (equal (satan-desktop-test--at-day events
                                               "2026-09-26T09:20:00+10:00")
                   (cons "ok" (satan-desktop-test--window
                               satan-desktop-test--browser
                               "2026-09-26T09:10:00.450+10:00"))))))

(ert-deftest satan-desktop/at-a-title-change-moves-since ()
  "VT-1 — a later `window_title' for the same window moves `:since':
the full state, title included, holds since then."
  (let* ((retitled (plist-put (copy-sequence satan-desktop-test--term)
                              :title "~/dev/beta"))
         (events (list (satan-desktop-test--ev "2026-09-26T09:00:00+10:00"
                                               "window_focus"
                                               satan-desktop-test--term)
                       (satan-desktop-test--ev "2026-09-26T09:03:00+10:00"
                                               "window_title" retitled))))
    (should (equal (satan-desktop-test--at-day events
                                               "2026-09-26T09:05:00+10:00")
                   (cons "ok" (satan-desktop-test--window
                               retitled "2026-09-26T09:03:00+10:00"))))))

(ert-deftest satan-desktop/at-idle-is-not-stale ()
  "VT-1 — an event hours before T still reads ok (DEC-035)."
  (should (equal (car (satan-desktop-test--at-day
                       (list (satan-desktop-test--ev
                              "2026-09-26T01:00:00+10:00" "window_focus"
                              satan-desktop-test--term))
                       "2026-09-26T22:00:00+10:00"))
                 "ok")))

(ert-deftest satan-desktop/at-copies-only-state-keys ()
  "VT-1 — envelope and event-specific fields are not copied: a sway-shaped
`window_title' carrying `old_title' yields only the state keys."
  (let ((result (satan-desktop-test--at-day
                 (list (satan-desktop-test--ev
                        "2026-09-26T09:00:00+10:00" "window_title"
                        satan-desktop-test--term
                        :old_title "~/dev/before" :old_workspace "x"
                        :reason "r" :producer "sway"))
                 "2026-09-26T09:05:00+10:00")))
    (should (equal result (cons "ok" (satan-desktop-test--window
                                      satan-desktop-test--term
                                      "2026-09-26T09:00:00+10:00"))))
    (dolist (key '(:v :ts :source :event :producer
                      :old_title :old_workspace :reason))
      (should-not (plist-member (cdr result) key)))))

(ert-deftest satan-desktop/at-a-json-null-is-not-a-key ()
  "VT-1 — a JSON null decodes to no key, as panopticon omits nulls."
  (should (equal (satan-desktop-test--at-day
                  (list (concat "{\"v\":1,\"ts\":\"2026-09-26T09:00:00+10:00\","
                                "\"source\":\"desktop\",\"event\":\"window_focus\","
                                "\"producer\":\"umbriel\",\"app_id\":\"firefox\","
                                "\"pid\":null}"))
                  "2026-09-26T09:05:00+10:00")
                 '("ok" :app_id "firefox"
                   :since "2026-09-26T09:00:00+10:00"))))

(ert-deftest satan-desktop/at-appending-after-t-changes-nothing ()
  "VT-1 — replayability: events appended after T leave the answer equal."
  (satan-desktop-fixture-with-root root
    (let* ((time "2026-09-26T09:05:00+10:00")
           (first (satan-desktop-test--ev "2026-09-26T09:00:00+10:00"
                                          "window_focus"
                                          satan-desktop-test--term))
           (_ (satan-desktop-fixture-write root satan-desktop-test--day
                                           (list first)))
           (before (satan-desktop-at root time)))
      (satan-desktop-fixture-write
       root satan-desktop-test--day
       (list first
             (satan-desktop-test--ev "2026-09-26T09:06:00+10:00"
                                     "window_focus" satan-desktop-test--browser)
             (satan-desktop-test--ev "2026-09-26T09:07:00+10:00"
                                     "compositor_disconnected" nil
                                     :reason "EOF")))
      (should (equal (car before) "ok"))
      (should (equal (satan-desktop-at root time) before)))))

;; ── the backward walk's edges ───────────────────────────────────────────────

(ert-deftest satan-desktop/at-reads-a-one-line-file ()
  "The walk processes the first line of the file, then stops."
  (should (equal (car (satan-desktop-test--at-day
                       (list (satan-desktop-test--ev
                              "2026-09-26T09:00:00+10:00" "snapshot"
                              satan-desktop-test--term))
                       "2026-09-26T09:05:00+10:00"))
                 "ok")))

(ert-deftest satan-desktop/at-reads-a-file-without-a-final-newline ()
  "The last line counts even when the file does not end in a newline."
  (satan-desktop-fixture-with-root root
    (let ((path (satan-desktop-fixture-write
                 root satan-desktop-test--day
                 (list (satan-desktop-test--ev "2026-09-26T09:00:00+10:00"
                                               "window_focus"
                                               satan-desktop-test--term)))))
      (satan-desktop-fixture-append
       path (json-serialize (satan-desktop-test--ev
                             "2026-09-26T09:01:00+10:00" "window_focus"
                             satan-desktop-test--browser)))
      (should (equal (satan-desktop-at root "2026-09-26T09:05:00+10:00")
                     (cons "ok" (satan-desktop-test--window
                                 satan-desktop-test--browser
                                 "2026-09-26T09:01:00+10:00")))))))

(ert-deftest satan-desktop/at-skips-blank-lines ()
  "Blank lines anywhere are neither events nor garbage."
  (should (equal (car (satan-desktop-test--at-day
                       (list ""
                             (satan-desktop-test--ev
                              "2026-09-26T09:00:00+10:00" "window_focus"
                              satan-desktop-test--term)
                             "" "   ")
                       "2026-09-26T09:05:00+10:00"))
                 "ok")))

;; ── VT-2: lifecycle ─────────────────────────────────────────────────────────

(ert-deftest satan-desktop/at-a-trailing-disconnect-reads-disconnected ()
  "VT-2 — a `compositor_disconnected' after the last state decides
disconnected, with a nil window."
  (let ((result (satan-desktop-test--at-day
                 (list (satan-desktop-test--ev "2026-09-26T09:00:00+10:00"
                                               "window_focus"
                                               satan-desktop-test--term)
                       (satan-desktop-test--ev "2026-09-26T09:01:00+10:00"
                                               "compositor_disconnected" nil
                                               :reason "EOF"))
                 "2026-09-26T09:05:00+10:00")))
    (should (equal result '("disconnected")))
    (satan-desktop-test--ok-iff-window result)))

(ert-deftest satan-desktop/at-reconnect-alone-is-not-a-connection ()
  "VT-2 — `compositor_reconnected' is skipped: after a disconnect it still
reads disconnected, until a `snapshot' carries state."
  (let ((events (list (satan-desktop-test--ev "2026-09-26T09:00:00+10:00"
                                              "window_focus"
                                              satan-desktop-test--term)
                      (satan-desktop-test--ev "2026-09-26T09:01:00+10:00"
                                              "compositor_disconnected" nil
                                              :reason "EOF")
                      (satan-desktop-test--ev "2026-09-26T09:02:00+10:00"
                                              "compositor_reconnected")
                      (satan-desktop-test--ev "2026-09-26T09:03:00+10:00"
                                              "snapshot"
                                              satan-desktop-test--browser))))
    (should (equal (satan-desktop-test--at-day events
                                               "2026-09-26T09:02:30+10:00")
                   '("disconnected")))
    (should (equal (satan-desktop-test--at-day events
                                               "2026-09-26T09:05:00+10:00")
                   (cons "ok" (satan-desktop-test--window
                               satan-desktop-test--browser
                               "2026-09-26T09:03:00+10:00"))))))

(ert-deftest satan-desktop/at-skips-pass-through-events ()
  "VT-2 — sway's `window_new' / `window_close', and unknown events, carry
no focused state and are skipped."
  (should (equal (satan-desktop-test--at-day
                  (list (satan-desktop-test--ev "2026-09-26T09:00:00+10:00"
                                                "window_focus"
                                                satan-desktop-test--term)
                        (satan-desktop-test--ev "2026-09-26T09:01:00+10:00"
                                                "window_new"
                                                satan-desktop-test--browser
                                                :producer "sway")
                        (satan-desktop-test--ev "2026-09-26T09:02:00+10:00"
                                                "window_close"
                                                satan-desktop-test--browser
                                                :producer "sway")
                        (satan-desktop-test--ev "2026-09-26T09:03:00+10:00"
                                                "something_new"))
                  "2026-09-26T09:05:00+10:00")
                 (cons "ok" (satan-desktop-test--window
                             satan-desktop-test--term
                             "2026-09-26T09:00:00+10:00")))))

;; ── VT-3: no focused window ─────────────────────────────────────────────────

(ert-deftest satan-desktop/at-no-focus-keeps-only-the-keys-carried ()
  "VT-3 — a state event without window keys means nothing is focused: it
reads ok, and the window is what it carries plus `:since'."
  (dolist (case
           `((("window_focus" :workspace "emacs" :output "DP-1")
              (:workspace "emacs" :output "DP-1"))
             (("workspace_focus" :workspace "web" :output "DP-2")
              (:workspace "web" :output "DP-2"))
             (("window_focus") nil)
             (("snapshot") nil)))
    (pcase-let* ((`((,event . ,fields) ,state) case)
                 (ts "2026-09-26T09:00:00+10:00")
                 (result (satan-desktop-test--at-day
                          (list (satan-desktop-test--ev
                                 "2026-09-26T08:00:00+10:00" "window_focus"
                                 satan-desktop-test--term)
                                (apply #'satan-desktop-fixture-event
                                       ts event fields))
                          "2026-09-26T09:05:00+10:00")))
      (should (equal result (cons "ok" (satan-desktop-test--window state ts))))
      (satan-desktop-test--ok-iff-window result))))

;; ── VT-6: UTF-8 ─────────────────────────────────────────────────────────────

(ert-deftest satan-desktop/at-a-non-ascii-title-round-trips ()
  "VT-6 — a non-ASCII title (`✳', `π') is written as UTF-8 bytes and
read back `equal'.  The byte check catches a symmetric mangle that a
round trip alone would pass."
  (satan-desktop-fixture-with-root root
    (let* ((title "✳ π — x")
           (path (satan-desktop-fixture-write
                  root satan-desktop-test--day
                  (list (satan-desktop-test--ev
                         "2026-09-26T09:00:00+10:00" "window_title"
                         (list :app_id "firefox" :title title))))))
      (should (equal (plist-get (cdr (satan-desktop-at
                                      root "2026-09-26T09:05:00+10:00"))
                                :title)
                     title))
      (with-temp-buffer
        (set-buffer-multibyte nil)
        (let ((coding-system-for-read 'no-conversion))
          (insert-file-contents path))
        (should (search-forward (encode-coding-string title 'utf-8) nil t))))))

;; ── VT-4: day files, leniency, missing and malformed ────────────────────────

(ert-deftest satan-desktop/at-falls-back-to-the-previous-day ()
  "VT-4 — nothing at or before T in T's day file: yesterday's decides."
  (satan-desktop-fixture-with-root root
    (satan-desktop-fixture-write
     root "2026-09-25"
     (list (satan-desktop-test--ev "2026-09-25T23:50:00+10:00" "window_focus"
                                   satan-desktop-test--term)))
    (satan-desktop-fixture-write
     root "2026-09-26"
     (list (satan-desktop-test--ev "2026-09-26T09:00:00+10:00" "window_focus"
                                   satan-desktop-test--browser)))
    (should (equal (satan-desktop-at root "2026-09-26T00:30:00+10:00")
                   (cons "ok" (satan-desktop-test--window
                               satan-desktop-test--term
                               "2026-09-25T23:50:00+10:00"))))))

(ert-deftest satan-desktop/at-reads-at-most-two-days ()
  "VT-4 — no deciding event in T's day or the day before reads
\"missing\"; a file two days back is never read."
  (satan-desktop-fixture-with-root root
    (should (equal (satan-desktop-at root "2026-09-26T09:00:00+10:00")
                   '("missing")))
    (satan-desktop-fixture-write
     root "2026-09-24"
     (list (satan-desktop-test--ev "2026-09-24T12:00:00+10:00" "window_focus"
                                   satan-desktop-test--term)))
    (should (equal (satan-desktop-at root "2026-09-26T09:00:00+10:00")
                   '("missing")))
    (satan-desktop-fixture-write
     root "2026-09-25"
     (list (satan-desktop-test--ev "2026-09-25T12:00:00+10:00"
                                   "compositor_reconnected")))
    (satan-desktop-fixture-write root "2026-09-26" nil)
    (should (equal (satan-desktop-at root "2026-09-26T09:00:00+10:00")
                   '("missing")))))

(ert-deftest satan-desktop/at-a-torn-last-line-changes-nothing ()
  "VT-4 — a torn trailing line, as a concurrent append leaves it, is
skipped without changing the status."
  (satan-desktop-fixture-with-root root
    (let ((path (satan-desktop-fixture-write
                 root satan-desktop-test--day
                 (list (satan-desktop-test--ev "2026-09-26T09:00:00+10:00"
                                               "window_focus"
                                               satan-desktop-test--term)))))
      (satan-desktop-fixture-append path "{\"v\":1,\"ts\":\"2026-")
      (should (equal (satan-desktop-at root "2026-09-26T09:05:00+10:00")
                     (cons "ok" (satan-desktop-test--window
                                 satan-desktop-test--term
                                 "2026-09-26T09:00:00+10:00")))))))

(ert-deftest satan-desktop/at-garbage-only-reads-malformed ()
  "VT-4 — a non-empty file with no parseable line reads \"malformed\".
Not an object, or a `ts' the strict parser rejects, is not parsed."
  (should (equal (satan-desktop-test--at-day
                  (list "garbage" "[1,2]" "42" "{\"v\":1}"
                        (satan-desktop-test--ev "2026-09-26 09:00:00+10"
                                                "window_focus"
                                                satan-desktop-test--term)
                        "{\"v\":1,\"ts\":\"2026-")
                  "2026-09-26T09:05:00+10:00")
                 '("malformed"))))

(ert-deftest satan-desktop/at-garbage-today-falls-through-to-yesterday ()
  "VT-4 — only an undecided walk reports malformed: garbage today with a
valid yesterday reads ok."
  (satan-desktop-fixture-with-root root
    (satan-desktop-fixture-write root "2026-09-26" '("garbage"))
    (satan-desktop-fixture-write
     root "2026-09-25"
     (list (satan-desktop-test--ev "2026-09-25T20:00:00+10:00" "window_focus"
                                   satan-desktop-test--term)))
    (should (equal (car (satan-desktop-at root "2026-09-26T09:00:00+10:00"))
                   "ok"))))

(ert-deftest satan-desktop/at-lines-all-after-t-read-missing ()
  "VT-4 — parseable lines that all fall after T are missing, not malformed."
  (should (equal (satan-desktop-test--at-day
                  (list (satan-desktop-test--ev "2026-09-26T10:00:00+10:00"
                                                "window_focus"
                                                satan-desktop-test--term))
                  "2026-09-26T09:00:00+10:00")
                 '("missing"))))

;; ── VT-5: instants and zones ────────────────────────────────────────────────

(ert-deftest satan-desktop/at-compares-instants-not-strings ()
  "VT-5 — a `Z' T is compared by instant against +10:00 lines.  As strings,
\"2026-09-25T23:30:00Z\" sorts before every line below; as an instant it
is 09:30 local, after the first."
  (should (equal (satan-desktop-test--at-day
                  (list (satan-desktop-test--ev "2026-09-26T09:00:00.500+10:00"
                                                "window_focus"
                                                satan-desktop-test--term)
                        (satan-desktop-test--ev "2026-09-26T10:00:00+10:00"
                                                "window_focus"
                                                satan-desktop-test--browser))
                  "2026-09-25T23:30:00Z")
                 (cons "ok" (satan-desktop-test--window
                             satan-desktop-test--term
                             "2026-09-26T09:00:00.500+10:00")))))

(ert-deftest satan-desktop/at-picks-the-day-file-in-its-zone ()
  "VT-5 — under `satan-desktop--zone' +10:00, a T of 15:30Z is local
2026-09-26 01:30, so `desktop-2026-09-26.jsonl' is read first.  A decoy
in the UTC date's file would decide differently were it picked."
  (satan-desktop-fixture-with-root root
    (should (equal satan-desktop--zone 36000))
    (satan-desktop-fixture-write
     root "2026-09-25"
     (list (satan-desktop-test--ev "2026-09-25T23:00:00+10:00" "window_focus"
                                   satan-desktop-test--browser)))
    (satan-desktop-fixture-write
     root "2026-09-26"
     (list (satan-desktop-test--ev "2026-09-26T01:00:00+10:00" "window_focus"
                                   satan-desktop-test--term)))
    (should (equal (satan-desktop-at root "2026-09-25T15:30:00Z")
                   (cons "ok" (satan-desktop-test--window
                               satan-desktop-test--term
                               "2026-09-26T01:00:00+10:00"))))))

(ert-deftest satan-desktop/at-an-unparseable-time-signals ()
  "VT-5 — an unparseable TIME is a caller bug, not a status."
  (satan-desktop-fixture-with-root root
    (should-error (satan-desktop-at root "2026-09-26 09:00:00"))
    (should-error (satan-desktop-at root "2026-09-26T09:00:00"))
    (should-error (satan-desktop-at root nil))))

;; ── VT-7: pin against live producer shapes ──────────────────────────────────
;;
;; The lines below mirror the key order and event shapes of panopticon's
;; live `raw/desktop-*.jsonl' (census of 2026-10-05..12: every umbriel
;; shape seen, by key set), with every value sanitised: titles, 32-hex
;; window ids, pids and workspace names are synthetic.  The offset is the
;; live DST one, +11:00, and titles carry raw UTF-8 as the live files do.
;;
;; The niri lines are DERIVED, not copied: live niri logs have rotated
;; out.  They are the umbriel shapes with "producer":"niri", plus the
;; workspace/output-only `window_focus' niri emits whenever focus leaves
;; every window (panopticon `compositor/diff.py' `diff_state', whose
;; `compact' drops the null window keys).
;;
;; If fresh live output disagrees with these lines, panopticon's shape
;; has moved and SATAN's full-state premise (DEC-036) needs rechecking:
;; a stub is a claim about a foreign binary
;; (mem.pattern.satan.stub-must-mirror-real-binary-output).

(defconst satan-desktop-test--pin-day "2026-10-12"
  "The pin lines' local date, in +11:00.")

(defconst satan-desktop-test--pin-lines
  '(;; umbriel
    "{\"v\":1,\"ts\":\"2026-10-12T09:00:00.101+11:00\",\"source\":\"desktop\",\"event\":\"compositor_reconnected\",\"producer\":\"umbriel\"}"
    "{\"v\":1,\"ts\":\"2026-10-12T09:00:01.202+11:00\",\"source\":\"desktop\",\"event\":\"snapshot\",\"producer\":\"umbriel\"}"
    "{\"v\":1,\"ts\":\"2026-10-12T09:01:00.303+11:00\",\"source\":\"desktop\",\"event\":\"window_focus\",\"producer\":\"umbriel\",\"window_id\":\"1111aaaa1111aaaa1111aaaa1111aaaa\",\"app_id\":\"com.mitchellh.ghostty\",\"pid\":424242,\"title\":\"✳ synthetic shell\",\"workspace\":\"emacs\",\"output\":\"DP-3\"}"
    "{\"v\":1,\"ts\":\"2026-10-12T09:02:00.404+11:00\",\"source\":\"desktop\",\"event\":\"window_title\",\"producer\":\"umbriel\",\"window_id\":\"1111aaaa1111aaaa1111aaaa1111aaaa\",\"app_id\":\"com.mitchellh.ghostty\",\"pid\":424242,\"title\":\"π synthetic shell\",\"workspace\":\"emacs\",\"output\":\"DP-3\"}"
    "{\"v\":1,\"ts\":\"2026-10-12T09:03:00.505+11:00\",\"source\":\"desktop\",\"event\":\"window_focus\",\"producer\":\"umbriel\",\"window_id\":\"2222bbbb2222bbbb2222bbbb2222bbbb\",\"app_id\":\"signal\",\"pid\":515151,\"title\":\"Synthetic chat\"}"
    "{\"v\":1,\"ts\":\"2026-10-12T09:04:00.606+11:00\",\"source\":\"desktop\",\"event\":\"window_title\",\"producer\":\"umbriel\",\"window_id\":\"2222bbbb2222bbbb2222bbbb2222bbbb\",\"app_id\":\"signal\",\"pid\":515151,\"title\":\"Synthetic chat (1)\"}"
    "{\"v\":1,\"ts\":\"2026-10-12T09:05:00.707+11:00\",\"source\":\"desktop\",\"event\":\"window_focus\",\"producer\":\"umbriel\",\"window_id\":\"3333cccc3333cccc3333cccc3333cccc\",\"app_id\":\"steam\",\"title\":\"Synthetic game\",\"workspace\":\"3\",\"output\":\"DP-3\"}"
    "{\"v\":1,\"ts\":\"2026-10-12T09:06:00.808+11:00\",\"source\":\"desktop\",\"event\":\"workspace_focus\",\"producer\":\"umbriel\",\"window_id\":\"4444dddd4444dddd4444dddd4444dddd\",\"app_id\":\"firefox\",\"pid\":626262,\"title\":\"Synthetic page\",\"workspace\":\"web\",\"output\":\"DP-3\"}"
    "{\"v\":1,\"ts\":\"2026-10-12T09:07:00.909+11:00\",\"source\":\"desktop\",\"event\":\"window_focus\",\"producer\":\"umbriel\"}"
    "{\"v\":1,\"ts\":\"2026-10-12T09:08:00.010+11:00\",\"source\":\"desktop\",\"event\":\"snapshot\",\"producer\":\"umbriel\",\"window_id\":\"1111aaaa1111aaaa1111aaaa1111aaaa\",\"app_id\":\"com.mitchellh.ghostty\",\"pid\":424242,\"title\":\"π synthetic shell\",\"workspace\":\"emacs\",\"output\":\"DP-3\"}"
    "{\"v\":1,\"ts\":\"2026-10-12T09:09:00.111+11:00\",\"source\":\"desktop\",\"event\":\"compositor_disconnected\",\"producer\":\"umbriel\",\"reason\":\"EOF\"}"
    "{\"v\":1,\"ts\":\"2026-10-12T09:09:00.612+11:00\",\"source\":\"desktop\",\"event\":\"compositor_reconnected\",\"producer\":\"umbriel\"}"
    ;; niri (derived)
    "{\"v\":1,\"ts\":\"2026-10-12T10:00:00.121+11:00\",\"source\":\"desktop\",\"event\":\"window_focus\",\"producer\":\"niri\",\"window_id\":\"5555eeee5555eeee5555eeee5555eeee\",\"app_id\":\"com.mitchellh.ghostty\",\"pid\":737373,\"title\":\"Synthetic niri shell\",\"workspace\":\"2\",\"output\":\"DP-3\"}"
    "{\"v\":1,\"ts\":\"2026-10-12T10:01:00.232+11:00\",\"source\":\"desktop\",\"event\":\"window_title\",\"producer\":\"niri\",\"window_id\":\"5555eeee5555eeee5555eeee5555eeee\",\"app_id\":\"com.mitchellh.ghostty\",\"pid\":737373,\"title\":\"✳ synthetic niri shell\",\"workspace\":\"2\",\"output\":\"DP-3\"}"
    "{\"v\":1,\"ts\":\"2026-10-12T10:02:00.343+11:00\",\"source\":\"desktop\",\"event\":\"window_focus\",\"producer\":\"niri\",\"workspace\":\"2\",\"output\":\"DP-3\"}"
    "{\"v\":1,\"ts\":\"2026-10-12T10:03:00.454+11:00\",\"source\":\"desktop\",\"event\":\"workspace_focus\",\"producer\":\"niri\",\"workspace\":\"4\",\"output\":\"HDMI-A-1\"}")
  "Live-shaped raw desktop lines, values sanitised.  See the comment above.")

(ert-deftest satan-desktop/at-pin-live-umbriel-and-niri-shapes ()
  "VT-7 — `satan-desktop-at' over live-shaped umbriel and niri lines
decides as the design says, at cut points across the sequence."
  (satan-desktop-fixture-with-root root
    (let ((satan-desktop--zone 39600))
      (satan-desktop-fixture-write root satan-desktop-test--pin-day
                                   satan-desktop-test--pin-lines)
      (dolist (case
               '(;; reconnected alone, nothing earlier
                 ("2026-10-12T09:00:00+11:00" "missing")
                 ;; empty snapshot: nothing focused
                 ("2026-10-12T09:00:30+11:00" "ok"
                  :since "2026-10-12T09:00:01.202+11:00")
                 ("2026-10-12T09:01:30+11:00" "ok"
                  :window_id "1111aaaa1111aaaa1111aaaa1111aaaa"
                  :app_id "com.mitchellh.ghostty" :pid 424242
                  :title "✳ synthetic shell" :workspace "emacs" :output "DP-3"
                  :since "2026-10-12T09:01:00.303+11:00")
                 ("2026-10-12T09:02:30+11:00" "ok"
                  :window_id "1111aaaa1111aaaa1111aaaa1111aaaa"
                  :app_id "com.mitchellh.ghostty" :pid 424242
                  :title "π synthetic shell" :workspace "emacs" :output "DP-3"
                  :since "2026-10-12T09:02:00.404+11:00")
                 ;; window keys, no workspace/output
                 ("2026-10-12T09:04:30+11:00" "ok"
                  :window_id "2222bbbb2222bbbb2222bbbb2222bbbb"
                  :app_id "signal" :pid 515151 :title "Synthetic chat (1)"
                  :since "2026-10-12T09:04:00.606+11:00")
                 ;; no pid
                 ("2026-10-12T09:05:30+11:00" "ok"
                  :window_id "3333cccc3333cccc3333cccc3333cccc"
                  :app_id "steam" :title "Synthetic game"
                  :workspace "3" :output "DP-3"
                  :since "2026-10-12T09:05:00.707+11:00")
                 ("2026-10-12T09:06:30+11:00" "ok"
                  :window_id "4444dddd4444dddd4444dddd4444dddd"
                  :app_id "firefox" :pid 626262 :title "Synthetic page"
                  :workspace "web" :output "DP-3"
                  :since "2026-10-12T09:06:00.808+11:00")
                 ;; keyless window_focus
                 ("2026-10-12T09:07:30+11:00" "ok"
                  :since "2026-10-12T09:07:00.909+11:00")
                 ("2026-10-12T09:08:30+11:00" "ok"
                  :window_id "1111aaaa1111aaaa1111aaaa1111aaaa"
                  :app_id "com.mitchellh.ghostty" :pid 424242
                  :title "π synthetic shell" :workspace "emacs" :output "DP-3"
                  :since "2026-10-12T09:08:00.010+11:00")
                 ;; disconnected, and still so after the reconnect
                 ("2026-10-12T09:09:30+11:00" "disconnected")
                 ("2026-10-12T09:30:00+11:00" "disconnected")
                 ;; niri
                 ("2026-10-12T10:01:30+11:00" "ok"
                  :window_id "5555eeee5555eeee5555eeee5555eeee"
                  :app_id "com.mitchellh.ghostty" :pid 737373
                  :title "✳ synthetic niri shell" :workspace "2"
                  :output "DP-3"
                  :since "2026-10-12T10:01:00.232+11:00")
                 ("2026-10-12T10:02:30+11:00" "ok"
                  :workspace "2" :output "DP-3"
                  :since "2026-10-12T10:02:00.343+11:00")
                 ("2026-10-12T23:59:59+11:00" "ok"
                  :workspace "4" :output "HDMI-A-1"
                  :since "2026-10-12T10:03:00.454+11:00")))
        (should (equal (cons (car case) (satan-desktop-at root (car case)))
                       case))))))

(provide 'satan-desktop-test)
;;; satan-desktop-test.el ends here
