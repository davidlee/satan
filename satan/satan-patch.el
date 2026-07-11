;;; satan-patch.el --- patch-agent aggregator -*- lexical-binding: t; -*-

;; Loads every Phase-1/Phase-2 patch-agent module and registers the
;; broker tools.  Owners of the SATAN startup sequence should require
;; this file (not the individual modules) so the load order and the
;; adapter registrations stay consistent.

(require 'satan-patch-store)
(require 'satan-patch-worktree)
(require 'satan-patch-adapter)
(require 'satan-patch-prompt)
(require 'satan-patch-classify)
(require 'satan-patch-runner)
(require 'satan-patch-adapter-pi)   ; auto-registers under "pi"
(require 'satan-patch-inbox)        ; adds runner-hook for inbox handoff
(require 'satan-patch-listener)     ; pg LISTEN → inbox handoff (opt-in)
(require 'satan-tools-patch)

(provide 'satan-patch)
;;; satan-patch.el ends here
