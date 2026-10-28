;;; satan-tools-activity.el --- activity_read tool handler -*- lexical-binding: t; -*-

;; Read-only window into the user's behaviour state, produced by
;; panopticon (~/dev/panopticon).  Files live under
;; `satan-tools-activity-dir' (default `~/.local/state/behaviour/').
;;
;; Scopes:
;;   - "today"          -> today's aggregate histogram
;;                         (per-app, per-workspace, per-hour seconds)
;;   - "recent_focus"   -> last N focus segments for today, default 20,
;;                         max 200.  Each segment: app_id, workspace,
;;                         start/end timestamps, duration_s.
;;   - "recent_browser" -> last N firefox tab segments for today, same
;;                         shape contract as recent_focus.  Each segment
;;                         is returned verbatim: full url + domain +
;;                         title_start/title_end (panopticon strips only
;;                         query/fragment at capture, never to origin),
;;                         start/end timestamps, duration_s.
;;   - "current"        -> the focused window at now, replayed from
;;                         panopticon's raw desktop log
;;                         (raw/desktop-YYYY-MM-DD.jsonl).  Keys:
;;                         :status (ok|disconnected|missing|malformed)
;;                         and :window (the state keys plus :since; nil
;;                         unless ok; an ok window without app_id means
;;                         nothing is focused).
;;                         NOTE: title is passed through verbatim and
;;                         can be sensitive (browser tab page-title,
;;                         editor file path, etc.) — see SATAN.md open
;;                         thread "current-scope title leak".
;;
;; Presence (IMP-055): every scope also reads panopticon's raw keyrate
;; minutes (`satan-keyrate'), so one call says whether the user was
;; typing, reading, idle or mixed, not only what was focused:
;;   - today          -> `:presence', key/pointer seconds per hour + total;
;;   - recent_focus   -> each segment carries key/pointer seconds and a
;;                       presence, and a stretch of a minute or more with
;;                       no segment is a `gap' entry of its own (the last
;;                       one, up to now, is `:open');
;;   - recent_browser -> each segment carries the same, no gaps;
;;   - current        -> `:presence' over the last
;;                       `satan-keyrate-window-minutes'.
;; A closed segment followed by nothing used to read as an ongoing
;; session (SATAN inbox, 2026-10-25); the gap entry is the answer.
;;
;; Typing (IMP-059): keys, key seconds and wpm per focused window, from
;; panopticon's raw `keyrate_window' rows (`satan-keyrate-typing'):
;;   - today        -> `:typing' per app with titles, current to the last
;;                     row; the histogram's lagging `typing_per_app' copy
;;                     is dropped so the model sees one figure;
;;   - recent_focus -> each focus segment's `:typing' for its app; titles
;;                     only with the `titles' arg (its cost grows with
;;                     `limit');
;;   - current      -> `:typing' per app with titles over the presence
;;                     window.
;; Titles widen the "current-scope title leak" thread above: verbatim,
;; capped per app (`satan-keyrate-title-cap'), accepted 2026-10-28.
;;
;; Risk = `read'; no capability required.  Panopticon is the producer
;; that handles redaction (firefox extension strips queries/fragments
;; and drops incognito); SATAN is a downstream consumer.

(require 'cl-lib)
(require 'subr-x)
(require 'satan-tools)
(require 'satan-jsonl)
(require 'satan-desktop)
(require 'satan-keyrate)
(require 'satan-memory-canon)

(defcustom satan-tools-activity-dir
  (expand-file-name "~/.local/state/behaviour/")
  "Root directory holding panopticon's behaviour-state output."
  :type 'directory :group 'satan)

(defcustom satan-tools-activity-default-limit 20
  "Default `:limit' for the `recent_focus' scope."
  :type 'integer :group 'satan)

(defconst satan-tools-activity--limit-max 200
  "Hard upper bound on `:limit'; clamped without error.")

(defun satan-tools-activity--today ()
  (format-time-string "%Y-%m-%d"))

(defun satan-tools-activity--read-json (path)
  "Parse JSON at PATH into a plist, or return nil if unreadable/empty."
  (when (and (file-readable-p path)
             (> (file-attribute-size (file-attributes path)) 0))
    (with-temp-buffer
      (let ((coding-system-for-read 'utf-8))
        (insert-file-contents path))
      (json-parse-string (buffer-string)
                         :object-type 'plist
                         :array-type 'list
                         :null-object nil
                         :false-object :false))))

(defun satan-tools-activity--clamp-limit (raw)
  (cond
   ((null raw) satan-tools-activity-default-limit)
   ((< raw 1) 1)
   ((> raw satan-tools-activity--limit-max)
    satan-tools-activity--limit-max)
   (t raw)))

;; ── keyrate presence (IMP-055) ──────────────────────────────────────────────

(defconst satan-tools-activity--gap-seconds 60
  "Shortest stretch without a focus segment shown as a gap entry.")

(defun satan-tools-activity--span (entry)
  "ENTRY's (FROM . TO) instants, or nil when a stamp does not parse."
  (let ((from (satan-memory-canon-parse-instant (plist-get entry :start_ts)))
        (to (satan-memory-canon-parse-instant (plist-get entry :end_ts))))
    (and from to (cons from to))))

(defun satan-tools-activity--with-presence (entry keyrate)
  "ENTRY plus its key/pointer seconds and presence from KEYRATE.
KEYRATE is `satan-keyrate-read''s (STATUS . MINUTES); unless its status
is ok, or ENTRY's span does not parse, ENTRY is returned as is."
  (let ((span (satan-tools-activity--span entry)))
    (if (and span (equal (car keyrate) "ok"))
        (append entry (satan-keyrate-describe (cdr keyrate) (car span) (cdr span)))
      entry)))

(defun satan-tools-activity--with-typing (entry windows titles)
  "ENTRY plus `:typing', its app's typing in WINDOWS over its span.
Only a focus segment names the app its keys went to; any other entry,
or a segment with no typing, is returned as is.  TITLES lists titles."
  (let ((span (satan-tools-activity--span entry))
        (app (plist-get entry :app_id)))
    (if-let* (((equal (plist-get entry :event) "focus_segment"))
              (span)
              (typing (car (satan-keyrate-typing
                            (seq-filter (lambda (w) (equal (plist-get (cdr w) :app_id) app))
                                        windows)
                            titles (car span) (cdr span)))))
        (append entry (list :typing typing))
      entry)))

(defun satan-tools-activity--gap (from-ts to-ts)
  "A gap entry from FROM-TS to TO-TS, or nil when it is too short to show."
  (let ((from (satan-memory-canon-parse-instant from-ts))
        (to (satan-memory-canon-parse-instant to-ts)))
    (when (and from to)
      (let ((seconds (float-time (time-subtract to from))))
        (when (>= seconds satan-tools-activity--gap-seconds)
          (list :event "gap" :start_ts from-ts :end_ts to-ts
                :duration_s (round seconds)))))))

(defun satan-tools-activity--with-gaps (segments now-ts)
  "SEGMENTS with a gap entry wherever a minute or more passes between one's
end and the next's start, or between the last's end and NOW-TS.  That
last gap is `:open': panopticon writes a segment only once it closes,
so it also covers whatever window is focused now."
  (let ((out nil))
    (cl-loop for (segment . rest) on segments
             do (push segment out)
             (when-let* ((gap (satan-tools-activity--gap
                               (plist-get segment :end_ts)
                               (if rest (plist-get (car rest) :start_ts) now-ts))))
               (push (if rest gap (append gap (list :open t))) out)))
    (nreverse out)))

(defun satan-tools-activity--recent (root scope prefix limit gaps titles)
  "SCOPE's result: the last LIMIT segments of today's PREFIX file under ROOT.
Each entry carries its keyrate presence, and a focus segment its typing
(`satan-tools-activity--with-typing', TITLES as there); with GAPS, gap
entries are interleaved (`satan-tools-activity--with-gaps')."
  (let* ((today (satan-tools-activity--today))
         (now-ts (format-time-string "%FT%T%:z"))
         (now (satan-memory-canon-parse-instant now-ts))
         (path (expand-file-name (format "segments/%s-%s.jsonl" prefix today) root))
         (tail (last (satan-jsonl-read-file path) limit))
         (entries (if gaps (satan-tools-activity--with-gaps tail now-ts) tail))
         (from (or (car (satan-tools-activity--span (car entries))) now))
         (keyrate (satan-keyrate-read root from now))
         (windows (cdr (satan-keyrate-read root from now
                                           satan-keyrate-window-event))))
    (list :scope scope
          :date today
          :limit limit
          :path path
          :keyrate (car keyrate)
          :segments (mapcar (lambda (e)
                              (satan-tools-activity--with-typing
                               (satan-tools-activity--with-presence e keyrate)
                               windows titles))
                            entries))))

(defun satan-tools-activity--day-presence (root day)
  "DAY's key and pointer seconds under ROOT, in total and per local hour."
  (pcase-let ((`(,status . ,minutes) (satan-keyrate-read-day root day)))
    (if (not (equal status "ok"))
        (list :status status)
      (let ((hours (satan-keyrate-per-hour minutes)))
        (append (list :status status
                      :key_seconds (apply #'+ (plist-get hours :per_hour_key_seconds))
                      :pointer_seconds (apply #'+ (plist-get hours
                                                             :per_hour_pointer_seconds)))
                hours)))))

(defun satan-tools-activity--day-typing (root day)
  "DAY's typing per app, with titles, from ROOT's raw window rows."
  (satan-keyrate-typing
   (cdr (satan-keyrate-read-day root day satan-keyrate-window-event)) t))

(defun satan-tools-activity--recent-typing (root now)
  "Typing per app, with titles, over the `satan-keyrate-window-minutes'
ending at NOW, from ROOT's raw window rows."
  (let ((from (time-subtract now (* 60 satan-keyrate-window-minutes))))
    (satan-keyrate-typing
     (cdr (satan-keyrate-read root from now satan-keyrate-window-event))
     t from now)))

(defun satan-tools-activity--without-typing-copy (histogram)
  "HISTOGRAM without `typing_per_app': `today' computes it fresh from raw."
  (cl-loop for (key value) on histogram by #'cddr
           unless (eq key :typing_per_app) nconc (list key value)))

(defun satan-tools-activity--recent-presence (root)
  "Presence over the last `satan-keyrate-window-minutes' under ROOT."
  (if-let* ((description (satan-keyrate-recent root (current-time))))
      (append (list :status "ok" :window_minutes satan-keyrate-window-minutes)
              description)
    (list :status "missing")))

(defun satan-tool/activity-read (args _ctx)
  "Implements activity_read.
ARGS: (:scope today|recent_focus|recent_browser|current :limit INT?
:titles BOOL?).
Returns (ok PLIST) | (error STRING)."
  (let* ((scope (plist-get args :scope))
         (today (satan-tools-activity--today))
         (root  satan-tools-activity-dir)
         (titles (eq (plist-get args :titles) t)))
    (pcase scope
      ("today"
       (let* ((path (expand-file-name
                     (format "histograms/daily-%s.json" today) root))
              (data (satan-tools-activity--read-json path)))
         (cons 'ok (list :scope "today"
                         :date today
                         :path path
                         :histogram (satan-tools-activity--without-typing-copy data)
                         :presence (satan-tools-activity--day-presence
                                    root today)
                         :typing (satan-tools-activity--day-typing root today)))))
      ("recent_focus"
       (cons 'ok (satan-tools-activity--recent
                  root "recent_focus" "focus"
                  (satan-tools-activity--clamp-limit (plist-get args :limit)) t titles)))
      ("recent_browser"
       (cons 'ok (satan-tools-activity--recent
                  root "recent_browser" "browser"
                  (satan-tools-activity--clamp-limit (plist-get args :limit)) nil titles)))
      ("current"
       (let ((probe (satan-desktop-at root (format-time-string "%FT%T%:z"))))
         (cons 'ok (list :scope "current"
                         :status (car probe)
                         :window (cdr probe)
                         :presence (satan-tools-activity--recent-presence
                                    root)
                         :typing (satan-tools-activity--recent-typing
                                  root (current-time))))))
      (_ (cons 'error (format "unknown scope: %s" scope))))))

(satan-tool-register
 (list :name "activity_read"
       :risk 'read
       :args-schema '(scope (:type string :required t
                             :enum ("today" "recent_focus"
                                    "recent_browser" "current"))
                      limit (:type integer :required nil)
                      titles (:type boolean :required nil))
       :handler 'satan-tool/activity-read))

(provide 'satan-tools-activity)
;;; satan-tools-activity.el ends here
