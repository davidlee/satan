;;; dl-satan-patch.el --- patch-agent aggregator -*- lexical-binding: t; -*-

;; Loads every Phase-1/Phase-2 patch-agent module and registers the
;; broker tools.  Owners of the SATAN startup sequence should require
;; this file (not the individual modules) so the load order and the
;; adapter registrations stay consistent.

(require 'dl-satan-patch-store)
(require 'dl-satan-patch-worktree)
(require 'dl-satan-patch-adapter)
(require 'dl-satan-patch-prompt)
(require 'dl-satan-patch-classify)
(require 'dl-satan-patch-runner)
(require 'dl-satan-patch-adapter-pi)   ; auto-registers under "pi"
(require 'dl-satan-patch-inbox)        ; adds runner-hook for inbox handoff
(require 'dl-satan-patch-listener)     ; pg LISTEN → inbox handoff (opt-in)
(require 'dl-satan-tools-patch)

(provide 'dl-satan-patch)
;;; dl-satan-patch.el ends here
