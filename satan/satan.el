;;; satan.el --- SATAN broker entry point -*- lexical-binding: t; -*-

;; Author: David Lee <david.lee@inlight.com.au>
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1"))
;; Keywords: tools, ai
;; URL: https://github.com/dl/satan

;;; Commentary:

;; Aggregator + the public interactive entry `satan-run'.
;;
;; SATAN is the local broker described in `SATAN.local.md'.  Emacs is the
;; capability authority; a bubblewrap-jailed child process is the harness;
;; they exchange newline-delimited JSON over stdin/stdout; only the broker
;; mutates durable state.
;;
;; Runtime dependencies (beyond Emacs 30.1):
;;   - psql (PostgreSQL client) — the only DB interface, via `call-process'.
;;   - coreutils `timeout(1)' — bounds runaway harness children (see SL-011);
;;     provided by the project devshell / flake.
;;
;; Emacs 30.1 floor: uses `handler-bind' (added in Emacs 30).

;;; Code:

(require 'satan-audit)
(require 'satan-budget)
(require 'satan-jsonl)
(require 'satan-block)
(require 'satan-tools)
(require 'satan-tools-org)
(require 'satan-tools-notify)
(require 'satan-tools-hippocampus)
(require 'satan-tools-inbox)
(require 'satan-tools-agenda)
(require 'satan-tools-activity)
(require 'satan-tools-content)
(require 'satan-tools-notes)
(require 'satan-tools-docs)
(require 'satan-tools-sway)
(require 'satan-tools-motive)
(require 'satan-tools-vcs)
(require 'satan-memory)
(require 'satan-sensor-alerts)
(require 'satan-mode)
(require 'satan-context)
(require 'satan-output)
(require 'satan-broker)
(require 'satan-tick)
(require 'satan-tools-atsatan)
(require 'satan-patch)
(require 'satan-tank)
(require 'satan-intervention)
(require 'satan-attribute-listener)   ; daemon → broker audit LISTEN (opt-in)
(require 'satan-mcp)

;; Hard-fail at load if any mode :tools entry has no matching registration.
;; Replaces the documentary-only `:modes' field that used to live on every
;; tool spec (T4).
(satan-mode-check-tool-references)

(defgroup satan nil
  "SATAN local agent runtime."
  :group 'tools
  :prefix "satan-")

(defun satan-run (name)
  "Run a SATAN session in mode NAME.  Returns the run-id string."
  (interactive
    (list (completing-read "SATAN mode: " (satan-mode-names) nil t)))
  (let ((run-id (satan-broker-run name)))
    (when (called-interactively-p 'interactive)
      (message "SATAN run started: %s" run-id))
    run-id))

(provide 'satan)
;;; satan.el ends here
