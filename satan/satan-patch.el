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

(require 'satan-patch-rpc)
(require 'satan-patch-inbox)
(require 'satan-patch-promote)
(require 'satan-tools-patch)

(unless noninteractive
  (satan-patch-inbox-start))

(provide 'satan-patch)
;;; satan-patch.el ends here
