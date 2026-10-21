# IMP-051: Extract pi-mcp as a standalone package: nix and doctrine optional, npm + pi package gallery

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

**When:** after the try-it period shows `pi_agent` working well as the default
delegation route (CLAUDE.md, commit 3fea833). Not before.
Met 2026-10-21: the operator reports `pi_agent` working in SL-030.
Prerequisites met 2026-10-22: CHR-021 (`450d456`), CHR-022 (`f04389e`), IMP-050
(`c97140f`), IMP-049 (`4999773`). IMP-049's `pi/mcp/README.md` documents the
`PI_MCP_*` launch environment as the server's configuration surface; whether that
stays the published surface or discovery is added is still this card's call.

**Goal:** pi-mcp (`pi/mcp/` + `pi/reduce/` + `bin/pi-mcp` + `bin/pi-run-reduce`)
lives in its own repo and is installable by someone with neither nix nor
doctrine.

## Name (proposed 2026-10-22) — `quotient`, leaning; `narthex` the alternative

`pi-mcp` names the wire, not the thing. MCP is how a client speaks to the
process and will be replaced before the process is. The orbit names by *seat* —
`satan`, `malebolge`, `panopticon`, `goad`, `attrd` — so the package should too,
and the name is the one thing here that becomes permanent at first `npm publish`.

**`quotient`.** The quotient map collapses a set onto one representative per
equivalence class, which is what `pi/reduce` already does to a run: hundreds of
thousands of tokens of child transcript go in, one bounded cited representative
comes out. It names the admission half as well — the map *selects the
representative*, and selecting one capability/profile/form out of the policy is
the door's whole job. It also sits next to π as a symbol pair: the harness is
irrational, the door rationalises (ℚ). The double-take has the right shape —
`quotient` reads as a psychometric score, a villain's measure of intellect,
until you look it up.

**`narthex`.** The entry chamber a catechumen passes through before the nave,
and where the uninitiated stop. It names the *crossing*, which is what this
process actually is to a harness, and no maths candidate names the crossing as
cleanly. Its double-take is the better joke — it sounds like an 80s supervillain
and turns out to be part of a church. Rejected only because it names a room, not
the reduction that is the package's substance.

Constraints the name must satisfy. (1) It composes as a prefix: `flake.nix:335`
mints one wrapper form per capability in `pi/mcp/profiles/`, so it must read as
`quotient-read`, `quotient-write`, `quotient-research`. (2) It survives a
registry where the name is permanent. (3) No collision in this tree — all
shortlist survivors checked (`quotient`, `narthex`, `adjoint`, `aleph`, `sieve`,
`cardinal`, `eta`): zero hits. The maths register is otherwise exhausted here:
`kernel` (35 files — OS kernel, patch-job kernel) and `residue` (118) are the
two best semantic fits and both are unusable.

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
  - **v1 scope:** ship nix forms plus the explicit unconfined form only.
  - **Follow-ups after v1:** native forms per platform. macOS: seatbelt
    (`sandbox-exec` profiles); there is prior art in doctrine, and the
    operator knows where. Linux: bwrap plus something for what mount
    namespaces don't cover (e.g. Landlock or seccomp; undecided).
    Capture each as its own backlog item when v1 ships.
- Host-specific defaults: the profiles name `llm-gateway/deepseek-flash`.
  The live policy's `child_binds` names the jail.nix agent home. Ship
  example profiles and a policy example (IMP-049), not this host's values.
- The governance (SL-029 design, DEC-089…103) cites doctrine ids. The
  extracted repo needs a self-contained design doc. Whether it keeps a
  doctrine corpus is that repo's choice.
- `node` comes from the satan devshell today. The server fails to start if
  Claude Code is not launched under direnv. A packaged bin fixes this.

## Found while surveying (2026-10-22)

- **The name reaches outside the repo, into host state.** The operator policy at
  `~/.config/pi-mcp/policy.json` names each form by absolute stable link,
  `~/.local/state/pi-mcp/forms/<capability>/bin/pi-mcp-<capability>`; run
  artifacts and sessions live under `~/.local/state/pi-mcp/{runs,sessions}`.
  So renaming is a *host* migration, not a repo rename. Two options: keep
  `pi-mcp` as the bin name the forms expose while the package is `quotient`, or
  migrate the policy and both state roots with the rename. Prefer the first at
  extraction — the operator's policy pins a path, and paths are the durable
  interface.
- **The launch environment is the entire config surface** (`pi/mcp/main.ts`: no
  argv, no config discovery). Coherent for a nix-built form, in direct tension
  with the npm/gallery ambition and with IMP-049: a stranger installing from npm
  has no `PI_MCP_*` contract to read. Decide in this card whether to publish the
  env contract *as* the documented config surface or to add discovery — not in
  the extracted repo, where it will be too late.
- **The wire contract is the public API, and it currently lives in comments plus
  a doctrine-side design doc.** `server.ts` lists exactly one tool; a
  `tools/call` always answers a tool result carrying a `pi-agent-result/1`
  document; a refusal is a *successful* call that ran nothing, never a JSON-RPC
  error (SL-029 design sec-5). A third-party consumer pins that document shape,
  so the extracted repo needs it as its own versioned contract doc — not a
  reference to a doctrine id.
- **Rename census** (measured, in-repo): `bin/pi-mcp`, `bin/pi-mcp-hostile-audit`,
  `bin/pi-run-reduce`, `.mcp.json` (the client entry `pi-agent`), `justfile`
  (`pi-mcp-forms` recipe, `nix build -o … pi-mcp-read/write`), `CLAUDE.md`,
  `flake.nix` (`pi-mcp-${capability}`, `pi-mcp-baseline`, the `pi-mcp-forms`
  check), and the `pi/mcp/` sources themselves. Do the rename *at* extraction,
  never before: half-renamed is worse than `pi-mcp`.
- **Two bins, one name.** The package ships the server and the reduce CLI
  (`bin/pi-run-reduce`). Whatever the package is called, decide the second bin's
  name in the same act (`quotient` + `quotient-reduce`, or `reduce` as a
  subcommand). Leaving it to drift produces a package whose two entry points do
  not look related.

## Related

IMP-048 (child_binds exposure check), IMP-049 (policy schema doc),
IMP-050 (thinking level in profiles), CHR-021 (shared spawn/gate test
setup). The last three are better done before extraction.
