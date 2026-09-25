# RSK-016: Production runs two revisions of satan: pinned harness, live-tree elisp

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Violates SPEC-002 NF-003 (REQ-015). Related: CHR-001.

The production harness binary comes from `~/flakes` input `satan = github:davidlee/satan` (pinned rev), while systemd runs `~/dev/satan/satan/bin/*` and Emacs loads elisp from the live working tree. A JSONL protocol or bundle-shape change can be live on one side only, with no error: the harness does not report a protocol version and the broker does not check one.

Mitigations: harness reports a protocol version in `ready` and the broker refuses a mismatch; and/or deploy both halves from one source (all `path:` or Emacs loading the pinned package).
