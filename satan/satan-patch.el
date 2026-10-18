;;; satan-patch.el --- patch-agent aggregator -*- lexical-binding: t; -*-

;; SL-023: the malebolge patch runner owns patch jobs.  This client side
;; is the broker tools, the inbox watch and promote/reject, all through
;; the one control-socket client `satan-patch-rpc'.  Owners of the SATAN
;; startup sequence should require this file (not the individual
;; modules).
;;
;; Loading it in an interactive Emacs starts the inbox watch, as it
;; started the pg LISTEN listener before (`satan-patch-inbox-enabled'
;; nil opts out).
;;
;; Until PHASE-13 batch C deletes them, the elisp runner's modules
;; still load here; nothing wires them to the inbox any more.

(require 'satan-patch-store)
(require 'satan-patch-worktree)
(require 'satan-patch-adapter)
(require 'satan-patch-prompt)
(require 'satan-patch-classify)
(require 'satan-patch-runner)
(require 'satan-patch-adapter-pi)   ; auto-registers under "pi"
(require 'satan-patch-rpc)
(require 'satan-patch-inbox)
(require 'satan-patch-promote)
(require 'satan-tools-patch)

(unless noninteractive
  (satan-patch-inbox-start))

(provide 'satan-patch)
;;; satan-patch.el ends here
