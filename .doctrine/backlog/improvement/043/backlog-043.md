# IMP-043: Review a patch job's diff from the Emacs inbox

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

The patch inbox offers only `satan-patch-promote` / `satan-patch-reject`; the
user promotes without seeing the change. The runner's `result` already carries
`commits` and `diffstat` (SL-023 design §5.1 op table) and
`satan-patch-rpc--job-fields` projects them, but
`satan-patch-inbox--body-fields` never renders them.

Proposed:
1. Render diffstat + commit subjects in the inbox entry body.
2. `satan-patch-show`: job id at point → fetch the quarantine ref into the
   incoming ref (reuse `satan-patch-promote--fetch`, no second fetch path) →
   show `base_oid..reviewed_oid` in magit (fall back to `vc-diff`); drop the
   incoming ref after.

Workaround today:
`git --git-dir=/var/lib/capsule/collect/assistant/<repo>.git show <reviewed_oid>`.

Raised 2026-10-19 after the SL-023 PHASE-14 closure run.
