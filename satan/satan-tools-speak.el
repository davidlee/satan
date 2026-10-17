;;; satan-tools-speak.el --- speak tool handler -*- lexical-binding: t; -*-

;; Speech aloud through the announce seam (`satan-announce' :speech), which
;; runs `satan-speak-program' (default `say').  Recorded as an intervention
;; first, exactly like `notify_send' (`satan-intervention-emit'): kind
;; `notify', surface `audio' — speech is a notification on another
;; channel, so the closed kind set and its projection stay unchanged.  Speech
;; is more intrusive than a pop, so it has its own `speak' capability and
;; a length cap.  IMP-040.

(require 'satan-announce)
(require 'satan-tools)
(require 'satan-intervention)

(defconst satan-speak-max-chars 300
  "Longest text `speak' accepts.  Longer text is refused, not truncated.")

(defconst satan-speak-intervention-window-minutes 30
  "`outcome_window_minutes' for speak interventions; as for notify.")

(defun satan-speak--refusal (text)
  "Why TEXT cannot be spoken now, or nil."
  (cond
   ((null satan-speak-program) "speech is disabled")
   ((not (string-match-p "[^[:space:]]" text)) "text is blank")
   ((> (length text) satan-speak-max-chars)
    (format "text too long: %d chars, max %d"
            (length text) satan-speak-max-chars))))

(defun satan-tool/speak (args ctx)
  "Speak ARGS' `:text' aloud, recorded as an intervention first.

CTX: broker-supplied tool-ctx with `:id', `:mode-name', `:time-now',
and `:audit'.  Speech is asynchronous: `ok' means it started.
Recorded, spoken and projected by `satan-intervention-emit', which
documents the result shapes.  Returns (error . MSG), with nothing
recorded, when speech is disabled or TEXT is blank or too long."
  (let* ((text (plist-get args :text))
         (refusal (satan-speak--refusal text)))
    (if refusal
        (cons 'error refusal)
      (satan-intervention-emit
       ctx
       (list :kind "notify"
             :target-surface "audio"
             :message text
             :expected-outcome "user hears and responds to the speech within window"
             :outcome-window-minutes satan-speak-intervention-window-minutes
             :severity "medium")
       (lambda () (satan-announce :speech text) nil)))))

(satan-tool-register
 (list :name "speak"
       :risk 'low
       :capability 'speak
       :args-schema '(text (:type string :required t))
       :handler 'satan-tool/speak))

(provide 'satan-tools-speak)
;;; satan-tools-speak.el ends here
