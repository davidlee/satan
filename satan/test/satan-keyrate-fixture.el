;;; satan-keyrate-fixture.el --- raw keyrate day files for tests -*- lexical-binding: t; -*-

;; Writes panopticon's raw keyrate log (`ROOT/raw/keyrate-DAY.jsonl') into
;; a scratch behaviour root, through the desktop fixture's raw writer.  Not
;; a suite file (no -test suffix): suites `require' it.  Timestamps carry
;; +10:00, the zone `satan-keyrate-fixture-with-root' pins both readers to.

;;; Code:

(require 'satan-keyrate)
(require 'satan-desktop-fixture)

(defun satan-keyrate-fixture-minute (ts key-seconds pointer-seconds)
  "A raw `keyrate_minute' starting at TS with KEY-SECONDS and POINTER-SECONDS.
`keys' and `peak_5s_cpm' are derived; no reader uses them."
  `(:v 1 :ts ,ts :source "keyrate" :event "keyrate_minute"
       :keys ,(* 3 key-seconds) :key_seconds ,key-seconds
       :pointer_seconds ,pointer-seconds :peak_5s_cpm ,(* 36 key-seconds)))

(defun satan-keyrate-fixture-window (ts app-id title keys key-seconds)
  "A raw `keyrate_window' at TS: KEYS and KEY-SECONDS typed into APP-ID's TITLE.
A nil TITLE is written as JSON null."
  `(:v 1 :ts ,ts :source "keyrate" :event "keyrate_window"
       :app_id ,app-id :title ,(or title :null)
       :keys ,keys :key_seconds ,key-seconds))

(defun satan-keyrate-fixture-write (root day minutes)
  "Write MINUTES (event plists or verbatim strings) as ROOT's keyrate DAY file.
Return the file's path."
  (satan-desktop-fixture-write-raw root "keyrate" day minutes))

(defmacro satan-keyrate-fixture-with-root (var &rest body)
  "Run BODY with VAR bound to a fresh behaviour root, in the fixture zone.
As `satan-desktop-fixture-with-root', also pinning `satan-keyrate--zone'."
  (declare (indent 1))
  `(satan-desktop-fixture-with-root ,var
     (let ((satan-keyrate--zone satan-desktop-fixture-zone))
       ,@body)))

(provide 'satan-keyrate-fixture)
;;; satan-keyrate-fixture.el ends here
