# DEC-062: SL-023 ledger changes: patch-runner owns job lifecycle, path allowlist, its ceiling, audit and switch

<!-- Knowledge record body — context, detail, links. The structured, queried
     fields live in the sister `record-NNN.toml`; this prose is free-form and is
     never structurally parsed (the storage rule). -->

Revised 2026-10-18 (informal review finding 4): the runner's RPC schema validation is part of the patch-runner rows, distinct from row 1's model-facing tool schema in Emacs.