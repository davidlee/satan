# ISS-028: Jails holding model output can reach around the trust-boundary protocol

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Violates SPEC-002 NF-004 (REQ-016); elaborates SPEC-001 REQ-011. Host detail: `~/flakes/SATAN.md` § Jails.

- MCP dev jails (`~/dev/satan/flake.nix:70-77`, also `.emacs.d`, `~/satan`, `~/notes` flakes) bind `/run/user/1000/emacs/server` rw — the comment says "allow arbitrary elisp execution". Any agent in those jails can `emacsclient --eval` past every allowlist.
- The jail library binds the launcher's `$PWD` rw (`~/flakes/agents/jailed-agents.nix:115-116`). `satan-broker.el` never sets `default-directory` before `make-process`; the Emacs unit runs from `~`. Probable result: the production harness has `~` read-write. **Verify** on a live run (`/proc/<pid>/mountinfo` of the bwrap child).
- The harness binds `~/dev/satan` rw at `/workspace/satan` ("## Migration !!", `flake.nix:140`).
- The harness shares the `specDev` persisted home with every interactive dev jail.

Structural fix to consider: one declared profile per consumer class (harness, MCP client, dev), mount lists asserted by test; default to path-identity mounts so ro/rw is the only per-jail variable; never bind the editor eval socket into a jail that holds model output; spawn the harness from an empty, dedicated cwd.
