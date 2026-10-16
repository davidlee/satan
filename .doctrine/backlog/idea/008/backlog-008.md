# IDE-008: pandaemonium on pi-env: harness and transcript on the host, tools executing in the microVM

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

From CHR-012 (RFC-018 F5). `@earendil-works/pi-env` is a remote
`ExecutionEnv`: a small daemon deployed over SSH. pandaemonium's `env` hook
(`src/session.ts`, currently `NodeExecutionEnv`) could return it, so:

- the durable transcript and session storage stay host-side (not precious
  habitat state; bears on RFC-018 OQ-4);
- `bash`/`read`/`edit` run in the oubliette microVM against its checkouts
  (IDE-007).

Next spike candidate. Untested: pi-env's auth, its SSH reach into the capsule,
and how it composes with oubliette's host-initiated git channel (OQ-3).
