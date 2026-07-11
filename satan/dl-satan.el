;;; dl-satan.el --- SATAN broker entry point -*- lexical-binding: t; -*-

;; Aggregator + the public interactive entry `my/satan-run'.
;;
;; SATAN is the local broker described in `SATAN.local.md'.  Emacs is the
;; capability authority; a bubblewrap-jailed child process is the harness;
;; they exchange newline-delimited JSON over stdin/stdout; only the broker
;; mutates durable state.

(require 'dl-satan-audit)
(require 'dl-satan-budget)
(require 'dl-satan-jsonl)
(require 'dl-satan-block)
(require 'dl-satan-tools)
(require 'dl-satan-tools-org)
(require 'dl-satan-tools-notify)
(require 'dl-satan-tools-hippocampus)
(require 'dl-satan-tools-inbox)
(require 'dl-satan-tools-agenda)
(require 'dl-satan-tools-activity)
(require 'dl-satan-tools-content)
(require 'dl-satan-tools-notes)
(require 'dl-satan-tools-docs)
(require 'dl-satan-tools-sway)
(require 'dl-satan-tools-motive)
(require 'dl-satan-tools-vcs)
(require 'dl-satan-memory)
(require 'dl-satan-sensor-alerts)
(require 'dl-satan-mode)
(require 'dl-satan-context)
(require 'dl-satan-output)
(require 'dl-satan-broker)
(require 'dl-satan-tick)
(require 'dl-satan-tools-atsatan)
(require 'dl-satan-patch)
(require 'dl-satan-tank)
(require 'dl-satan-intervention)
(require 'dl-satan-attribute-listener)   ; daemon → broker audit LISTEN (opt-in)
(require 'dl-satan-mcp)

;; Hard-fail at load if any mode :tools entry has no matching registration.
;; Replaces the documentary-only `:modes' field that used to live on every
;; tool spec (T4).
(dl-satan-mode-check-tool-references)

(defgroup dl-satan nil
  "SATAN local agent runtime."
  :group 'tools
  :prefix "dl-satan-")

(defun my/satan-run (name)
  "Run a SATAN session in mode NAME.  Returns the run-id string."
  (interactive
    (list (completing-read "SATAN mode: " (dl-satan-mode-names) nil t)))
  (let ((run-id (dl-satan-broker-run name)))
    (when (called-interactively-p 'interactive)
      (message "SATAN run started: %s" run-id))
    run-id))

(provide 'dl-satan)
;;; dl-satan.el ends here
