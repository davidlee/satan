# IMP-051: Extract pi-mcp as a standalone package: nix and doctrine optional, npm + pi package gallery

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

**When:** after the try-it period shows `pi_agent` working well as the default
delegation route (CLAUDE.md, commit 3fea833). Not before.

**Goal:** pi-mcp (`pi/mcp/` + `pi/reduce/` + `bin/pi-mcp` + `bin/pi-run-reduce`)
lives in its own repo and is installable by someone with neither nix nor
doctrine.

## Distribution channels (all optional, not exclusive)

- **npm package**: `npx`/global install gives the `pi-mcp` and `pi-run-reduce`
  bins. Node refuses to strip types for files under `node_modules`
  (`ERR_UNSUPPORTED_NODE_MODULES_TYPE_STRIPPING`; known Node behaviour,
  not yet checked here). So a published package needs a build step to `.js`,
  or the no-build-step stance in `bin/pi-mcp` ends at the repo boundary.
- **pi package** (`pi install npm:…`, gallery listing via the `pi-package`
  keyword, pi `docs/packages.md`). Open question: what the pi-side resource
  *is*. An MCP server is for other clients (Claude, codex). Candidates:
  - a pi extension giving pi itself a delegate tool (pi → pi);
  - config for pi's `builtin:mcp` extension pointing at the server;
  - skills documenting delegation.
  Decide before building. A gallery listing alone is not a reason.
- **nix**: a flake output (package + the wrapper forms), as today. Optional,
  not required.

## Coupling to cut (checked 2026-10-21)

- Code imports: `pi/mcp/` imports only `../reduce/reduce.ts`. The two move
  together. No doctrine or satan imports. `server.ts` cites `satan-mcp.el` in
  comments only.
- **Confinement is nix-built.** The `forms` the policy names are bwrap jails
  generated in `flake.nix` (`piMcpJail`, the `pi-mcp-forms` check). Without
  nix, the package needs a portable form, e.g. a plain bwrap script
  generator or a documented "unconfined" form. That form must be explicit
  in the policy and never a silent fallback (DEC-097 refuses an absent
  policy; keep that posture).
- Host-specific defaults: the profiles name `llm-gateway/deepseek-flash`.
  The live policy's `child_binds` names the jail.nix agent home. Ship
  example profiles and a policy example (IMP-049), not this host's values.
- The governance (SL-029 design, DEC-089…103) cites doctrine ids. The
  extracted repo needs a self-contained design doc. Whether it keeps a
  doctrine corpus is that repo's choice.
- `node` comes from the satan devshell today. The server fails to start if
  Claude Code is not launched under direnv. A packaged bin fixes this.

## Related

IMP-048 (child_binds exposure check), IMP-049 (policy schema doc),
IMP-050 (thinking level in profiles), CHR-021 (shared spawn/gate test
setup). The last three are better done before extraction.
