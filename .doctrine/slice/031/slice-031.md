# Extract pi-mcp as quotient: standalone package, satan cuts over

## Context

IMP-051. pi-mcp is the MCP (Model Context Protocol) server behind the
`pi_agent` tool, together with the run reducer. It lives in this repo as
`pi/mcp/` + `pi/reduce/` + `bin/pi-mcp` + `bin/pi-run-reduce`, and its
confinement forms are built by `flake.nix`.

Since 2026-10-21 it has been the default delegation route. Its prerequisites
have landed (CHR-021, CHR-022, IMP-050, IMP-049). The code has no satan or
doctrine imports. Its remaining coupling is:

- the confinement forms, built only by nix;
- this host's values, in the profiles and the policy;
- governance that cites doctrine ids (SL-029, DEC-089…103);
- a `node` taken from the satan devshell.

The operator decisions are recorded in IMP-051 § "Operator decisions
(2026-10-22)". This slice implements them and does not reopen them.

## Scope & Objectives

1. **New repo `~/dev/quotient`** (remote `github.com/davidlee/quotient`). It
   holds the server and reducer sources, their suites, and the test rig, and
   must be installable without nix or doctrine.
   - **Entry point:** one bin. Bare `quotient` serves MCP over stdio, and
     `quotient reduce <events.jsonl>` takes over `pi-run-reduce`'s contract,
     with the same exit codes.
   - **Config discovery, split by authority:**
     - The policy comes from an env path, else
       `$XDG_CONFIG_HOME/quotient/policy.json`. It is never discovered in the
       project tree.
     - Profiles are looked up project-local (`./.quotient/`) first, then XDG.
       The policy's `profiles` maps each name to a capability. A profile whose
       document declares a different capability is refused, which closes the
       elevation path of DEC-092 and RV-046 F-5.
     - State defaults to `$XDG_STATE_HOME/quotient/{runs,sessions}`.
     - Env overrides remain.
     - An absent or malformed policy still refuses every call.
   - **Build:** `tsc` emits `.js` when the package is packed. Node refuses to
     strip types under `node_modules`, which was verified 2026-10-22. Dev and
     tests keep running the `.ts` directly.
   - **Confinement in v1:**
     - `form-1`, a form contract that names no mechanism (DEC-116). It states
       what a form must guarantee. bwrap, seatbelt and Landlock are possible
       implementations. `hostile-audit` probes write denial only; it does not
       establish conformance.
     - The quotient flake exports the package only. satan keeps building this
       host's forms, renamed `quotient-<capability>`.
     - An explicit *unconfined* form, which a policy must name, and only for
       `write` (DEC-114). It is never a silent fallback.
     - The policy field `child_binds` is renamed `exposure`.
   - **npm package `@davidlee/quotient`**, which installs the `quotient` bin.
     The unscoped name is taken.
   - **Clients:** Claude Code and Codex. Each gets a documented config (Claude
     `.mcp.json`, Codex `config.toml` `[mcp_servers]`), and each is
     smoke-tested.
   - **Built-in help, one sectioned source:**
     - For the model: the MCP `instructions` and the tool description are
       assembled from it, so that a client works without an installed skill.
     - For people: `quotient help [section]` prints it.
     - Overrides: any section can be replaced by a file
       (`./.quotient/help/<section>.md`, then XDG) or a config entry.
   - **Docs that stand alone:**
     - A design doc with no doctrine ids.
     - A versioned `pi-agent-result/1` wire-contract doc.
     - The operator README, ported with its drift test.
     - Example profiles and an example policy in place of this host's values.
2. **satan cuts over.** satan consumes quotient through a flake input. The
   following go: `pi/mcp/`, `pi/reduce/`, `bin/pi-mcp`,
   `bin/pi-mcp-hostile-audit`, `bin/pi-run-reduce`, `piMcpJail`, and the
   `pi-mcp-*` flake outputs and check. `.mcp.json`, the `justfile` recipes
   `pi-mcp-forms` and `pi-suites`, and `CLAUDE.md` are retargeted.
3. **Host migration at cutover**, in one act:
   - The forms move to `~/.local/state/quotient/forms/<capability>/bin/quotient-<capability>`.
   - The policy moves to `~/.config/quotient/policy.json`. The operator
     re-issues it; agents never edit it.
   - The state roots move to `~/.local/state/quotient/{runs,sessions}`. Old run
     history stays readable where it is.

## Non-Goals

- A pi package (pi-side resource or gallery listing). Raise it as a follow-up.
- Native confinement forms per platform (macOS seatbelt; Linux bwrap plus
  Landlock or seccomp). Raise one follow-up per platform.
- IMP-048 (exposure check on `child_binds`) and ISS-054 (a cancellation's grace
  period records nothing). Both move with the code but are not done here.
- Any change to the server's behaviour beyond config discovery and the entry
  point.

## Affected surface

- New: `~/dev/quotient/**`.
- This repo:
  - removed: `pi/mcp/**`, `pi/reduce/**`, `bin/pi-mcp`,
    `bin/pi-mcp-hostile-audit`, `bin/pi-run-reduce`;
  - edited: `flake.nix`, `flake.lock`, `.mcp.json`, `justfile`, `CLAUDE.md`,
    `scripts/lib/pi-report.sh` (+ its test; reducer default, added in
    design), and the `docs/` that cite pi-mcp;
  - kept, moved: `pi/mcp/forms.test.ts` tests satan's flake, not the server
    (added in design).
- Host, outside both repos: `~/.config/quotient/`, `~/.local/state/quotient/`,
  and `~/flakes`, if the host pins satan's forms.

## Risks & assumptions

- **Delegation outage.** Cutover breaks `pi_agent` until the new forms, policy
  and `.mcp.json` all agree. Mitigation (DEC-120): run both servers side by
  side, smoke the new one, then remove the old route and repeat a live call
  before deleting the old form links.
- **Unconfined form.** It weakens the default posture for non-nix users. The
  policy must name it, and the README must say what it does not confine.
- **Profile lookup.** Discovering profiles project-local lets a repo choose
  its profile set, but the profiles and the policy are separate. The policy
  still bounds what any profile may ask for. Assumed; to be checked in design.
- **Paths in the tree.** Repo-relative paths (`pi/mcp/profiles/`, the
  `flake.nix` line refs) are cited across memories and docs. The rename sweep
  must find them all.

- **Codex tool timeout.** Codex limits each MCP tool call, with a default of
  about 60 s (`tool_timeout_sec`, from recall and unverified). `pi_agent`
  blocks for the whole run, which takes minutes. Research must verify this. The
  README must then give the setting, or the tool must return before the
  timeout and be polled.
- **Help overrides are model-facing text.** A project-local help override
  steers the orchestrator model. It does not change authority, because the
  policy still bounds every call. It is an injection surface all the same, and
  design decides whether that is acceptable.
- **Publishing is permanent.** The publish step is in scope. It still needs
  the operator's explicit go-ahead at the time, after `npm pack` has been
  verified.

## Open questions (for /design): resolved 2026-10-22

All are answered in the design run (`doctrine design tree SL-031`):

- OQ-1: DEC-110.
- OQ-2: DEC-116.
- OQ-3: DEC-111.
- OQ-4: hostile-audit moves to quotient as the `form-1` write-denial probe.
- OQ-5: DEC-118. Calls stay blocking in v1, and the job shape is a follow-up.

The questions as originally posed:

- OQ-1: Carry git history into quotient (`git filter-repo` on `pi/` + `bin/`),
  or start with a fresh import commit?
- OQ-2: How does satan's flake consume the forms? Through a flake input, with
  the forms built from quotient's output, or does satan keep generating the
  forms from quotient's package?
- OQ-3: Does the reducer's library API (`reduce.ts`, imported by the server)
  stay internal, or is it exported as well?
- OQ-4: Where does `bin/pi-mcp-hostile-audit` go: quotient, or retired?

- OQ-5: If Codex's timeout is real, should the tool block, or move to a job
  family (start / status / result / cancel)? A job family changes the
  single-tool wire contract. Prior art: `~/.local/src/codex-plugin-cc`
  (`codex-companion.mjs` task `--background` / status / result / cancel; its
  `NOTES.md`). That checkout is not mounted in the pi jail.

## Verification / closure intent

- The quotient suites pass in `~/dev/quotient`, run as `.ts`. A packed tarball
  installs into a clean directory, and both `quotient` and `quotient reduce`
  run from `node_modules` as `.js`.
- Config discovery tests cover:
  - env beats XDG;
  - the policy is never read from the project tree;
  - a local profile beats an XDG one;
  - an absent policy refuses.
- After cutover, satan has no `pi/` sources. `just check` is green, and a live
  `pi_agent` call through `.mcp.json` returns `final: true` from the
  `quotient-read` form.
- Before removal, a `write` call through `quotient-write` writes a file in a
  scratch root.
- A live `pi_agent` call succeeds from both Claude Code and Codex.
- `quotient help` and the MCP `instructions` are built from the same sections,
  and a section override from a file is tested.
- `@davidlee/quotient` is published, with the operator's go-ahead, and
  `npx @davidlee/quotient help` runs.
- The README drift test passes in quotient. The design doc and the contract
  doc contain no doctrine ids.

## Summary

Move pi-mcp into its own repo as `quotient`, with one bin, config discovery
split by authority, a built npm artefact, and nix forms plus an explicit
unconfined form. Then switch satan and this host to it in one act.

## Follow-Ups

- The pi package: the pi-side resource and the gallery listing.
- A Claude Code plugin as an install channel: one plugin install gives the MCP
  config plus commands and skills. The shape is `codex-plugin-cc`'s
  `.claude-plugin/` marketplace and `plugins/<name>/`.
- Native confinement forms, as implementations of `form-1`: macOS (seatbelt),
  and Linux (bwrap plus Landlock or seccomp). Also generic forms for nix users
  outside this host.
- A wait-then-handle job shape for clients with short tool timeouts (DEC-118).
- A generic `form-1` probe per guarantee (G1–G8), beyond write denial.
