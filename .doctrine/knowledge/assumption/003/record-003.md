# ASM-003: Pi extension configuration is JSON

<!-- Knowledge record body — context, detail, links. The structured, queried
     fields live in the sister `record-NNN.toml`; this prose is free-form and is
     never structurally parsed (the storage rule). -->

Proceeding as if any Pi extension adopted for `auth-gateway` or `git-broker`
(RFC-018 D1) takes its configuration as JSON. This includes permitted
providers/models, token caps, git argv shapes, permitted refs and credential
references.

Consequence: RFC-018 OQ-5 (how a grant reaches a package) reduces to
generating JSON from the published policy artifact (ADR-018 D2, SPEC-001
REQ-006). We do not need a per-package config adapter.

Invalidated if a chosen option configures through code (a TypeScript module),
CLI flags only, or a non-JSON format that has no lossless JSON equivalent.
Check during the RFC-018 OQ-1 adopt-or-build evaluation.
