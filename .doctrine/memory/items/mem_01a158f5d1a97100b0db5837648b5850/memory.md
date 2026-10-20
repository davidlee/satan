`~/.config/emacs/apps/dl-satan.el` loads malebolge with
`(use-package malebolge :ensure nil :load-path "~/dev/malebolge/emacs" :commands …)`.
`malebolge.el` marks `malebolge-attach/-start/-stop` with `;;;###autoload`, but nothing
generates an autoloads file for a `:load-path` package, so only the commands in
`:commands` exist before the file is loaded. With `:commands malebolge-attach` only,
`M-x malebolge-start` was undefined in a fresh Emacs (SL-028 VH-1; fixed emacs 08367c7).

How to apply: adding an interactive entry point to malebolge.el (or any :load-path
package) means adding it to that `:commands` list too. A long-lived Emacs that has
already loaded the file hides the gap — test from a fresh Emacs.
