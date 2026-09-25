The notes module shells out (`fd` for notes_recent, `rg` for notes_grep). Three policies existed in the tree before this slice:

- `hippocampus_grep` errors on a non-0/1 rg exit (`satan-tools-hippocampus.el:250-305`).
- `content_read`'s search scope soft-fails to an empty result when `rg` is not found (`satan-tools-content.el:242-260`).
- `notes_recent` errors on a non-zero `fd` exit.

Decision: the notes tools error. A missing or failing binary, and any exit code above 1, produce `(error . "<probe> failed: ...")`. Exit 1 from `rg` (no matches) is a *successful* empty result — `(ok … :count 0)` — because it carries no ambiguity.

The reason is SL-015's: a wrong-but-readable answer is worse than an error. A soft-failed search is indistinguishable from a corpus with no hits, so the model would draw a conclusion the tool cannot support. `content_read`'s policy is not imported here.