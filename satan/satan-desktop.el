;;; satan-desktop.el --- focused desktop state at an instant -*- lexical-binding: t; -*-

;; Answers "what was focused at instant T" from panopticon's raw desktop
;; log, `ROOT/raw/desktop-YYYY-MM-DD.jsonl' (schema owned by panopticon:
;; `panopticon/docs/schema.md', "Desktop events").  ROOT is the behaviour
;; root, passed in; this module reads no defcustom and knows nothing of
;; its callers (SL-021 DEC-039).
;;
;; Pure with respect to SATAN state: reads at most two day files, writes
;; nothing, keeps nothing between calls.  The answer is the state carried
;; by the last state event at or before T, stamped `:since' with that
;; event's `ts'; a `compositor_disconnected' after it reads disconnected.
;; Never dropped for age (DEC-035).
;;
;; Two deployment premises, not checked here (design sec-2, Invariants):
;; - append order is `ts' order, so walking back from the end finds the
;;   last event at or before T;
;; - panopticon and Emacs share a local zone, so the day file named by
;;   panopticon's `ts' date is the one `satan-desktop--zone' selects.
;;
;; Requires only `subr-x' and `satan-memory-canon' (instant parser, date
;; helpers), so both the evidence assembler and `activity_read' can
;; reach it without a require cycle.

;;; Code:

(require 'subr-x)
(require 'satan-memory-canon)

(defvar satan-desktop--zone nil
  "Zone the day file of an instant is chosen in; nil is Emacs's local zone.
A test seam: production leaves it nil, tests pin it to a fixed offset.")

(defconst satan-desktop--state-keys
  '(:window_id :app_id :pid :title :workspace :output)
  "The state keys copied into a window: panopticon's `DesktopState' fields.")

(defconst satan-desktop--state-events
  '("snapshot" "window_focus" "workspace_focus" "window_title")
  "Events carrying the full focused state; each decides \"ok\".")

(defun satan-desktop--day-file (root day)
  "The raw desktop log for DAY (\"YYYY-MM-DD\") under behaviour ROOT."
  (expand-file-name (format "raw/desktop-%s.jsonl" day) root))

(defun satan-desktop--state-window (event)
  "EVENT's state keys, verbatim and in its order, plus `:since' (its `ts').
Envelope and event-specific fields are left out; a key absent or null
in EVENT stays absent."
  (let ((fields event) (window nil))
    (while fields
      (let ((key (car fields)) (value (cadr fields)))
        (when (and value (memq key satan-desktop--state-keys))
          (push key window)
          (push value window)))
      (setq fields (cddr fields)))
    (nconc (nreverse window) (list :since (plist-get event :ts)))))

(defun satan-desktop--decide (event)
  "The (STATUS . WINDOW) EVENT decides, or nil when the walk skips it."
  (let ((name (plist-get event :event)))
    (cond ((member name satan-desktop--state-events)
           (cons "ok" (satan-desktop--state-window event)))
          ((equal name "compositor_disconnected")
           (list "disconnected")))))

(defun satan-desktop--parse-line (line)
  "LINE as (INSTANT . EVENT), or nil when it is not a usable event.
Usable means a JSON object whose `ts' the strict instant parser
accepts; anything else (a torn append, garbage, an array) is nil."
  (let* ((event (condition-case nil
                    (json-parse-string line
                                       :object-type 'plist
                                       :array-type 'list
                                       :null-object nil
                                       :false-object :false)
                  (json-error nil)))
         (instant (and (consp event)
                       (satan-memory-canon-parse-instant
                        (plist-get event :ts)))))
    (and instant (cons instant event))))

(defun satan-desktop--scan-file (path instant)
  "Walk PATH backward from its end for the event deciding INSTANT.
Return its (STATUS . WINDOW); else `malformed' when PATH has a
non-blank line and none parsed; else nil (no file, or nothing at or
before INSTANT decides)."
  (when (file-readable-p path)
    (with-temp-buffer
      (let ((coding-system-for-read 'utf-8))
        (insert-file-contents path))
      (goto-char (point-max))
      (let ((decision nil) (seen nil) (parsed nil) (done nil))
        (while (not (or decision done))
          (let ((line (buffer-substring-no-properties
                       (line-beginning-position) (line-end-position))))
            (unless (string-blank-p line)
              (setq seen t)
              (when-let* ((entry (satan-desktop--parse-line line)))
                (setq parsed t)
                (unless (time-less-p instant (car entry))
                  (setq decision (satan-desktop--decide (cdr entry)))))))
          ;; Line 1 is processed above before the walk stops.
          (if (= (line-beginning-position) (point-min))
              (setq done t)
            (forward-line -1)))
        (cond (decision)
              ((and seen (not parsed)) 'malformed))))))

(defun satan-desktop-at (root time)
  "The focused desktop state at TIME, from the raw log under ROOT.
TIME is an ISO 8601 string with an offset (`Z' or `+10:00', with or
without fractional seconds); an unparseable TIME signals.  Return
\(STATUS . WINDOW):

- \"ok\": WINDOW is the deciding state event's state keys
  (`satan-desktop--state-keys', verbatim; absent stays absent) plus
  `:since', that event's `ts'.  No window keys means nothing focused.
- \"disconnected\": a `compositor_disconnected' followed the last state.
- \"missing\": no state at or before TIME in TIME's local day file
  (in `satan-desktop--zone') or the day before.
- \"malformed\": as missing, but a file read had no parseable line.

WINDOW is nil unless STATUS is \"ok\".  Events are compared as
instants, never strings; appending events after TIME never changes
the answer."
  (let* ((instant (or (satan-memory-canon-parse-instant time)
                      (error "satan-desktop-at: not an ISO 8601 instant: %S"
                             time)))
         (day (satan-memory-canon-local-date time satan-desktop--zone))
         (days (list day (satan-memory-canon-day-shift day -1)))
         (decision nil)
         (malformed nil))
    (while (and days (not decision))
      (pcase (satan-desktop--scan-file
              (satan-desktop--day-file root (pop days)) instant)
        ('malformed (setq malformed t))
        ((and (pred consp) found) (setq decision found))))
    (or decision (list (if malformed "malformed" "missing")))))

(provide 'satan-desktop)
;;; satan-desktop.el ends here
