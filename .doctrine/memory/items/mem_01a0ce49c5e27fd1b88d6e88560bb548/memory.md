`quit` (signalled by C-g) is not a subtype of `error`. `condition-case`
with an `error` handler, `ignore-errors` and `(error nil)` all let it
through.

This matters wherever Elisp blocks on something the keeper can interrupt. In
SATAN that is a synchronous 1Password read (`op read` via `call-process`)
under a prompting credential policy. Before 67adae4, C-g during that read
escaped `satan-credential-acquire`, `-resolve` and `satan-broker--acquire`:
the trigger was lost with no run recorded, and a patch job would have been
stranded `claimed`.

**How to apply:** a boundary whose contract is "never signals / always yields
a verdict" around a blocking or prompting call catches `(error quit)`:

```elisp
(condition-case err
    (blocking-read ...)
  ((error quit) (list :unavailable err)))
```

Test it with a fake that signals `quit` (the credential fixture's `:quit`).
Don't catch `quit` in code that doesn't block: swallowing C-g elsewhere
makes Emacs uninterruptible.
