;;; satan-desktop-fixture.el --- raw desktop day files for tests -*- lexical-binding: t; -*-

;; Writes panopticon's raw desktop log (`ROOT/raw/desktop-DAY.jsonl') into
;; a scratch behaviour root, so every suite that reads desktop state builds
;; its input one way.  Not a suite file (no -test suffix): suites `require'
;; it.
;;
;; Events are plists in raw key order (`v', `ts', `source', `event',
;; `producer', then the event's own fields).  A string element is written
;; verbatim, so torn lines, garbage and pinned live-shaped lines go
;; through the same writer.  Timestamps in fixtures carry +10:00, the
;; zone `satan-desktop-fixture-with-root' pins the reader to.

;;; Code:

(require 'satan-desktop)

(defconst satan-desktop-fixture-zone 36000
  "The zone fixture timestamps are written in: +10:00.")

(defun satan-desktop-fixture-event (ts event &rest fields)
  "A raw desktop EVENT stamped TS, carrying FIELDS (a plist).
The envelope comes first, in panopticon's key order.  The producer is
\"umbriel\", today's only live producer, unless FIELDS carries its own
`:producer', which then takes the envelope slot instead."
  (let ((producer (or (plist-get fields :producer) "umbriel"))
        (own nil))
    (while fields
      (unless (eq (car fields) :producer)
        (setq own (nconc own (list (car fields) (cadr fields)))))
      (setq fields (cddr fields)))
    `(:v 1 :ts ,ts :source "desktop" :event ,event :producer ,producer
         ,@own)))

(defun satan-desktop-fixture--line (event)
  "EVENT as one decoded JSON line: a string verbatim, a plist serialised.
`json-serialize' returns unibyte UTF-8; decoding it keeps a non-ASCII
title from being inserted as raw eight-bit bytes."
  (if (stringp event)
      event
    (decode-coding-string (json-serialize event) 'utf-8)))

(defun satan-desktop-fixture-write (root day events)
  "Write EVENTS as ROOT/raw/desktop-DAY.jsonl, one line each, in UTF-8.
DAY is \"YYYY-MM-DD\".  Overwrites the file, creating `raw/' as
needed.  Each element is an event plist or a string written verbatim.
Return the file's path."
  (satan-desktop-fixture-write-raw root "desktop" day events))

(defun satan-desktop-fixture-write-raw (root source day events)
  "Write EVENTS as ROOT/raw/SOURCE-DAY.jsonl, as `satan-desktop-fixture-write'.
SOURCE names the raw stream (\"desktop\", \"keyrate\")."
  (let ((path (expand-file-name (format "raw/%s-%s.jsonl" source day) root))
        (coding-system-for-write 'utf-8))
    (make-directory (file-name-directory path) t)
    (with-temp-file path
      (dolist (event events)
        (insert (satan-desktop-fixture--line event) "\n")))
    path))

(defun satan-desktop-fixture-focus (root ts app)
  "Write ROOT's raw day file for TS as one snapshot: APP focused on \"main\".
For suites that only need a focused app at a frozen instant.  The day
is TS's own date, which matches the reader's under the fixture zone.
Return the file's path."
  (satan-desktop-fixture-write
   root (substring ts 0 10)
   (list (satan-desktop-fixture-event ts "snapshot"
                                      :app_id app :workspace "main"))))

(defun satan-desktop-fixture-append (path text)
  "Append TEXT to PATH verbatim, in UTF-8, adding no newline.
How a test tears a line or leaves a file without a final newline, as
panopticon's concurrent appends can."
  (let ((coding-system-for-write 'utf-8))
    (write-region text nil path t 'silent)))

(defmacro satan-desktop-fixture-with-root (var &rest body)
  "Run BODY with VAR bound to a fresh behaviour root, in the fixture zone.
`satan-desktop--zone' is pinned to `satan-desktop-fixture-zone', so the
day file a TIME selects does not depend on the host's zone.  The root
starts empty (no `raw/') and is removed afterwards."
  (declare (indent 1))
  (let ((dir (make-symbol "dir")))
    `(let* ((,dir (make-temp-file "satan-desktop-test-" t))
            (,var ,dir)
            (satan-desktop--zone satan-desktop-fixture-zone))
       (unwind-protect (progn ,@body)
         (delete-directory ,dir t)))))

(provide 'satan-desktop-fixture)
;;; satan-desktop-fixture.el ends here
