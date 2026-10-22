# Notes SL-031: Extract pi-mcp as quotient: standalone package, satan cuts over

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## Design triage (2026-10-22, exploring)

Evidence: `research/research.md`. Operator decisions: IMP-051 § Operator
decisions.

- **Shaping decisions, settled by the operator:**
  - Name `quotient`: one bin with a `reduce` subcommand. npm package
    `@davidlee/quotient`.
  - Config is split by authority. The policy comes from env, else XDG.
  - Profiles are looked up local first, and the policy pins each profile's
    capability.
  - The host migrates at cutover.
  - No pi package in v1.
  - Claude Code and Codex are both clients.
  - Built-in help comes from one source, with per-section overrides.
  - v1 publishes to npm, with an explicit operator go-ahead at publish time.
- **Constraining governance.** DEC-089 to DEC-100 and DEC-103 (SL-029), and
  ADR-017 ledger rows 1b, 2b, 3c, 4c, 5c and 6c. Revision candidates: DEC-092,
  DEC-097, DEC-100, the ledger anchors and row 3c, and POL-001's candidate
  list.
- **Risks.**
  - A delegation outage during cutover.
  - The unconfined posture weakens the default.
  - Help overrides are text the model reads.
  - Codex's 60 s tool timeout.
  - Paths cited in memories and docs.
- **Assumptions.**
  - The code is erasable-only TypeScript; to be confirmed by `tsc
    --erasableSyntaxOnly`.
  - Claude Code CLI's MCP timeout is long enough. Observed with 300 s runs.
- **Open questions:** the design inquiries `inq-1` to `inq-13` in the design
  run. OQ-1 to OQ-5 from the scope map onto them.

## Devil's-advocate review (2026-10-22, informal, no RV)

Two pi research runs: `~/.local/state/pi-mcp/runs/run-20261021T234111161Z-6-…`
(security) and `…234139836Z-7-…` (packaging and cutover).

- **Accepted** (the operator: "Apply all"). Each is appended as an amendment to
  DEC-110 through DEC-120.
- **Refuted.** The claim that a `$HOME` root lets a delegate rewrite the policy
  is wrong. Step 8 already refuses it (`childview.ts:97-110`). The real gap was
  that the profile and help directories are missing from the protected stores.
- **Rejected.**
  - Two bins: this reopens the operator's decision.
  - A shipped default profile layer.
  - A digest pin on the unconfined binary.
- **The operator kept v1 contract-only** (no generic form).
- **Present-day bug in satan's pi-mcp**, fixed by this slice (DEC-118
  amendment). The child is spawned `detached` (`spawn.ts:290`), and the server
  kills nothing on stdin EOF or SIGTERM. A client that kills the server can
  therefore orphan the `pi` group.

## Design synthesis (2026-10-22, rev 23)

An independent redraft was compared against the rev-21 draft, and both were merged.
Operator rulings ("accept") are recorded as `2026-10-22b` amendments on DEC-112,
DEC-115, DEC-116, DEC-118, DEC-119 and DEC-120. Multi-root calls → IDE-016.
Scope gained `scripts/lib/pi-report.sh` (reducer consumer) and keeps
`pi/mcp/forms.test.ts` in satan. Correction: stdin EOF already ran the ladder;
only SIGTERM/SIGINT were uncovered.

## Hostile pass (2026-10-22, RV-058)

gpt-6-sol ran it through `codex exec` in three rounds. All 15 findings were
design defects, repaired in prose; the ledger holds the detail. F-8 is routed
`control`: its negative controls must appear on the phase that writes the
drift tests, and the raiser verifies it after `slice phases`.

**Further passes.** None is needed before planning, and the operator judged the
review conducted. Round 3 found nothing new, and all remaining risk sits in
implementation, which the plan's criteria cover. What a further pass would
probe, if one is wanted:

- the cutover table end to end against the real host (`~/flakes`, `.mcp.json`,
  form links);
- the generalised `scripts/hostile-audit` once it exists;
- the forms test's destination path, which the design leaves to the plan
  ("a satan-owned path").

## PHASE-01 execution (2026-10-22)

- **filter-repo** (`nix run nixpkgs#git-filter-repo`, 2.47.0) on a `--no-local`
  scratch clone of `7aedf30`, two passes: keep the five paths with the three
  renames and `--prune-empty always`, then drop
  `src/server/forms.test.ts` (`--invert-paths`). 21 → 20 commits (the pruned
  one touched only forms.test.ts). Pulled into the operator's empty
  `~/dev/quotient` (origin preset; not pushed).
- **History review / secret scan (EX-2, for VH-1).** `git log --stat`: 20
  commits, `c0bd4e3` (pi-run-reduce) … `9e87257` (IMP-049). gitleaks 8.30.1
  over all 20 commits: no leaks. Pattern grep (key/secret/token/password/
  private-key/`sk-`/`ghp_`/`AKIA`): only the fixture literal
  `LLM_GATEWAY_KEY: 'gateway-token'`. No `/home/david` in history. Authors:
  `David Lee <dav@davlee.com>` (8), `Jailed agent <jailed-agent@localhost>`
  (12) — public on push.
- **Layout as moved.** `pi/mcp` moved whole, so `src/server/` also holds
  `README.md`, `profiles/*.md`, `readme.test.ts` and `main.ts`; they keep
  today's behaviour until PHASE-02 (main.ts), PHASE-05 (profiles → examples)
  and PHASE-07 (readme.test.ts). `bin/pi-mcp`, `bin/pi-run-reduce` are
  deleted in the bootstrap commit, history only (EX-1).
  `scripts/hostile-audit` still execs `$here/bin/pi-mcp`: not runnable until
  PHASE-09 (EX-7).
- **Decision: two tsconfigs.** Design sec-5 asks for a tsconfig that excludes
  tests from the emit *and* EX-5 asks `tsc --noEmit` to check the tests.
  `tsconfig.json` checks all of `src`; `tsconfig.build.json` extends it and
  excludes `**/*.test.ts` and `test-rig.ts`; `build`/`prepack` are
  `tsc -p tsconfig.build.json` (design said `tsc`). Build checked: dist holds
  the 13 modules, no tests, `.ts` specifiers rewritten.
- **devDeps.** `typescript ^5.7` resolves 5.9.3; `erasableSyntaxOnly` needs
  ≥ 5.8, so the floor is nominal. `@types/node ^22` per design (not the
  operator's satan-local `^26`). satan's devshell tsc is 7.0.2; quotient uses
  its lockfile's 5.9.3 via `npx`.
- **tsc --noEmit: 18 errors, all type-only, fixed without behaviour change**
  (triaged by pi, session `be62a541…`; no latent bug found):
  - `profiles.ts` (6): `ReturnType<typeof readdirSync>` picks the last
    overload (`Dirent<Buffer>`); runtime is `Dirent<string>` → annotate
    `Dirent<string>[]`.
  - `server.ts:434` (1): `RunOutcome.abort` typed `Termination` but only
    ever an `AbortCause` → narrowed `abort` and `terminate(cause)` to
    `AbortCause`.
  - `spawn.ts:455` (1): `waitFor(done: Promise<unknown>)`, value discarded.
  - `spawn.ts:475` (2): `exit` assigned in a promise callback, so TS narrows
    it to `null` after `await` (TS#9998) → the exit audit reads through
    `outcome()`, which builds the identical values.
  - tests (8): `!` / one cast in gate, result, session tests; an
    `async` wrapper for a `context.after` returning `Promise<void[]>`.
- **Tests: 256, not 262.** The difference is `forms.test.ts`'s 6 tests, which
  stay in satan (EX-6). Path-bound tests retargeted, test code only: a shared
  `serverCommand` in `test-rig.ts` (`node src/server/main.ts`, what
  `bin/pi-mcp` exec'd) replaces three `bin/pi-mcp` spawns; childview's
  profiles path → `src/server/profiles`. PHASE-02 retargets `serverCommand` to
  `cli.ts serve`.
- **Node (EX-8):** satan devshell node v24.21.0.
- **VA-1** (2026-10-22), on a file copy of the tracked + untracked tree (Q has
  no commit yet, so no clone): `npm ci --no-audit --no-fund` → 3 packages;
  `npx tsc --noEmit` clean; `npm test` 256/256. Plain `npm ci` hung on the
  registry audit call; `--no-audit` sidesteps it (pack-check, PHASE-09,
  should pass it too). Repeated from a real `git clone` of Q at `b6d856c`
  (the bootstrap commit): same result, 256/256.
- **VH-1** given by the operator, 2026-10-22 (history review and scan accepted).
- **Per-phase review** skipped: 31-line type-only diff plus test-path
  retargets, every change itemised above; no tripwire.
- **verify-vt:** PHASE-01 VT-1/VT-2 report UNATTRIBUTABLE — keywords present,
  but doctrine attributes through satan's git history, which cannot see Q.
  Every Q-side VT will read this way; the keyword check is the evidence.

## PHASE-02 execution (2026-10-22)

- `src/cli.ts` (shebang; the only import-time side effect is its last line)
  implements the sec-2 table. Bare argv serves; `serve` is not a verb
  (DEC-111: "bare serves MCP"), so `quotient serve` exits 2. `help` is a stub
  over the nine sec-2 section names until PHASE-08.
- `src/root.ts`: `packageRoot` = parent of the module dir (pure URL math);
  `packageVersion()` reads package.json per call, so no I/O at import.
  Tested from src and from a tsc-built temp dist with a copied package.json.
- serverInfo `{ quotient, packageVersion() }`; `SERVER_VERSION` gone.
  `pi-mcp:` → `quotient:` (16 sites); now pinned by the unparsable-line test
  (`/^quotient: unparsable/m`).
- Reducer: guard deleted; usage and its three stderr prefixes say
  `quotient reduce` (design names only the usage; prefix follows it).
  reduce.test.ts and test-rig `serverCommand` drive `src/cli.ts`; main.ts
  deleted. README line 26 retargeted to `src/cli.ts`.
- 262 tests (256 + 2 root + 4 cli); tsc clean. Hand checks: TTY line under
  `script -qec`, none on a pipe; built `dist/cli.js --version` → 0.1.0 and
  answers initialize. The built server logs that `dist/server/profiles/` is
  missing: `DEFAULT_PROFILES_DIR` is module-relative until PHASE-05.
- Review (pi `f728c1b6…`): stdin stream error rejects `serve` before the
  EOF shutdown runs (pre-existing, as in main.ts) → carried to PHASE-06.
  Dismissed: version read on initialize (package.json always ships);
  hostile-audit stale (EX-7); help stub output untested (PHASE-08).

## PHASE-03 execution (2026-10-22)

- `src/config.ts`: pure `resolveLocations(env, launchDir)` per design sec-3;
  owns the `QUOTIENT_*` names and `usable(resolved)` (path or null, the
  shape the evidence writers take). Details distinguish "unset and neither
  XDG_* nor HOME", "set but empty", "set but not an absolute path". With no
  XDG config base the layer lists hold only the launch layer.
- Locations resolved once per process in `serve` (`Context.locations`): env
  and launch dir are fixed for its life; the policy file is still read every
  call. `admitCall(locations, callId)`; `refused` and admission both record
  to `usable(locations.runDir)`. `absoluteVar`/`knownRunDir` deleted.
- `PI_MCP_` → `QUOTIENT_` across src, including the scrub prefix, the
  session-test helper vars and the README env table (now documents the XDG
  defaults; PHASE-07 replaces the README). evidence.ts's stderr note says
  "no usable run dir".
- Tests: config.test.ts (6); policy.test's four env cases folded into one
  admission-level case (lookup semantics are config's); test-rig `admit(env,
  id)` resolves then admits. VT-2: `{XDG_CONFIG_HOME, XDG_STATE_HOME}` only,
  invalid policy → request-invalid and policy-invalid both in
  `<state>/quotient/runs/attempts.jsonl`. 266 tests; tsc clean.
- Hermeticity checked: the rig spreads `process.env` but always sets all
  three `QUOTIENT_*`; no test deletes one over an inherited HOME.
- Review (pi `c582178b…`): fixed — run-dir/session-home details unasserted;
  empty vs relative conflated. Dismissed — layers computed but unwired
  (PHASE-05/08); the launch-dir policy test "cannot fail" (it is the
  regression guard VT-1 names).

## PHASE-04 execution (2026-10-22)

- `policy.ts`: `schema` required and checked first — before the static-only
  posture check and the unknown-key check (`POLICY_SCHEMA`). `profiles` is a
  name → `read`|`write` map (`PROFILE_NAME` grammar; `FORM_FIELDS` doubles as
  the capability list). `forms` accepts `{ unconfined: <abs pi> }`: write
  only; exclusive with `path`; takes no `extensions` (pi runs
  `--no-extensions`, design sec-4); no PATH lookup. `Form` is the sec-3
  union. `child_binds` → `exposure` (now an unknown field).
- Server, interim: step 3 checks map keys (`Object.keys(policy.profiles)`);
  the capability pin is PHASE-05 EX-3. An unconfined form refuses
  `wrapper-unavailable` ("this build cannot yet launch an unconfined form")
  until PHASE-06; `spawn.ts` types its plan as the confined arm
  (`LaunchForm`). Both are marked "Interim" / PHASE-06 in code.
- ChildView input still says `childBinds`/role `child_bind`: PHASE-05 EX-5
  renames them; server maps `policy.exposure` into it.
- README (src/server, replaced in PHASE-07) documents `schema`, the map,
  `unconfined`, `exposure`; its json block is v1.
- 270 tests; tsc clean. No pi review this phase (handover point).

## PHASE-05 execution (2026-10-22)

Q `ac5f641` (feat), `c978df5` (F4 fix), `a8d383b` (wire audit test). 279 tests, tsc clean.

- `profiles.ts`: `loadProfiles(layers)` reads each layer once (`readLayer`,
  `readDocument`). An absent layer is empty. An unresolved entry, such as a
  dangling symlink, an unreadable layer, or an invalid document in any layer
  refuses. The highest layer wins per name. The digest is
  `name\0source\0bytes\0` over the winners in name order. `Profile.path` →
  `source`; `Snapshot.dir` → `layers`. The marker is `<!-- quotient-profile`,
  with no alias.
- Step 3: `resolveProfile(snapshot, name, policy.profiles)`. The order is
  grammar → unknown → own-key map (`Object.hasOwn`) →
  `profile-capability-mismatch`. `FILESYSTEMS`/`isFilesystem` in
  `profiles.ts` replace policy's `FORM_FIELDS` as both vocabularies.
- Step 8: `ChildViewInput.exposure`, `profileLayers` and `helpLayers`; the role
  is `exposure`. Store kinds `profile-layer` and `help-layer` are
  never-writable. **D2 (user agreed "Tighten")**: a never-writable store
  refuses any read-write overlap, including a member *inside* it. The design
  text says "is or contains".
- `DEFAULT_PROFILES_DIR` and `ServeOptions.profilesDir` are removed. The docs
  moved to `examples/profiles/`, with a usage paragraph.
- `spawn` record gains `profile_source`.
- Test rig: `launchEnv` sets `XDG_CONFIG_HOME` to the tree's own. `workspace`
  and `newRig` seed `RIG_PROFILES` in the XDG layer. `newRig` has its own
  `launchDir` (≠ root) and `serveRig`. The rig's `openServer` defaults to an
  empty temp launch dir. Hermeticity was verified by planting a broken
  profile in the ambient XDG layer and in the checkout's `.quotient/`; both
  stayed green.
- pi review: PHASE-04 policy found no violations, only the `FORM_FIELDS`
  coupling, now fixed. PHASE-05 security review:
  - F4 accepted and fixed: a dangling-symlink layer loaded as empty.
  - F1 rejected: layer stores have no `except`, so `isExempt` cannot apply.
  - F2 rejected: a symlinked layer canonicalises to its target and a
    containing root refuses; symlinked documents are skipped by
    `Dirent.isFile()`.
  - F3 rejected: an absent layer canonicalises under the launch realpath, and
    a test pins it.
- Cutover consequence (EX-5): a write call cannot be rooted at the server's
  launch dir or above it. satan's policy and smoke steps (PHASE-10) must root
  write calls elsewhere.
- Help snapshot loading is not this phase. Only the help layer *paths* are
  protected.

## PHASE-06 execution (2026-10-22)

Q `505824a` (argv split + unconfined branch), `539cee5` (signal shutdown),
`5459b29` (review fix). 285 tests, tsc clean.

- `spawn.ts`: `buildArgv` is pi's argv only and no longer takes `form`.
  `launchCommand(form, sessionDir, piArgv)` is the one branch (DEC-114).
  `LaunchForm` is removed and `SpawnPlan.form` is `Form`. The `spawn` record
  carries `form` (the command: launcher or pi path), `form_kind`, and `argv`
  (what the command received; the confined form's argv starts with the
  session dir).
- `policy.ts`: `formExtensions(form)`. An unconfined form has `[]`, so an
  `mcp__*` profile on an unconfined write form refuses `profile-invalid`.
  This follows from the policy rejecting `extensions` beside `unconfined`.
  The interim `wrapper-unavailable` refusal in `server.ts` is removed.
- `server.ts`: `ServeOptions.signal`. `inputChunks(input, diagnostics,
  signal)` calls `addAbortSignal` on the input, so the signal ends the read
  loop. A failed input writes `quotient: the input failed: …` and ends the
  loop too. All three endings reach the existing EOF sweep unchanged. Only
  the iterator's errors are caught: a `handleLine` throw propagates, as
  before. No test pins that, because no test can make `handleLine` throw.
- `cli.ts`: `shutdownSignal()` uses `process.once` for SIGTERM and SIGINT.
  A second signal takes the default action, so the operator can escape a
  stuck shutdown. Exit is 0, as on EOF.
- Rig: `LiveServer.fail(error)`. `runDirs` and `onlyRunDir` moved into
  `test-rig.ts`.
- VT-2 covers the in-process signal, a failed input, a pre-aborted signal
  (admits nothing), and a real SIGTERM to the subprocess server (exit 0,
  group dead, `abort` record with cause `eof`). The subprocess case takes
  about 2 s at the contract grace, because the CLI exposes no grace knob.
- pi review (`read`): F1 was partly valid and is fixed by `5459b29`; the catch
  had covered `handleLine`, though the error was not silent as pi claimed. F2
  is rejected: an unconfined `-e builtin:mcp` cannot be reached past step 5,
  and the new test pins this.

## PHASE-07 execution (2026-10-22)

Q `dae39fb` (contracts, docs, drift tests) and `5a032ed` (review fixes). 290
tests, tsc clean.

- `docs/contract/pi-agent-result-1.md` has four tables the drift test parses:
  Fields (path, type, nullable, meaning; `x[]` names an array element),
  States, Terminations (termination → state) and Refusals.
  `quotient-policy-1.md` holds the content of the old `src/server/README.md`,
  plus resolution, admission order, protected stores and the unconfined
  section. `form-1.md` gives an evidence table in which only the sampled G6
  write case is verified by quotient. `docs/design.md` ends with
  "extracted from github.com/davidlee/satan". Also new: `README.md` and
  `examples/policy.json`.
- `src/drift.test.ts`: each check is a pure function from text to
  violations, and each negative control runs the same function on a doctored
  copy. There are four controls: wrong type, nullable doctored to no, wrong
  termination row, and a Fields row missing a cell.
- **Fixture source (interpretation).** A "rig-produced result per state" is
  built by the real reducer with `resultFor`, `failedResult` and
  `refusedResult` (`buildResult` in `test-rig.ts`, moved from
  `result.test.ts`). These are the builders every server answer goes through;
  no fixture runs a subprocess per state.
- **Scope widened, stricter.** The doctrine-id scan covers `docs/`,
  `examples/` and `README.md`. Its id set is the design's plus IMP, ISS,
  SPEC, RFC, REV, CHR, IDE and RSK. A generic `[A-Z]+-\d{3}` pattern would
  false-positive on `SHA-256`. `help/` joins in PHASE-08.
- The README is written for the v0.1.0 end state: the nix install arrives in
  PHASE-09 and `quotient help clients`/`profiles` in PHASE-08.
- Corrected along the way:
  - `REACHABILITY` prose said stdin EOF produces `cancelled`; it is `eof`
    (`incomplete`).
  - The example profiles cited "design sec-3" and `src/server/profiles.ts`
    (not shipped). They now cite `quotient-policy-1.md` and
    `quotient help profiles`.
  - pi's upstream is `github.com/earendil-works/pi`.
- The drift test caught the policy contract writing `$XDG_CONFIG_HOME`
  rather than the variable name: fixed.
- VA-1 (pi `read` cold read): all nine design topics, the origin pointer, and
  the README's install, setup and links are present. The accepted gap was
  undefined terms (pi, MCP, form, capability); the README now defines them.
- pi review of the drift tests:
  - accepted: F5 and latent F4 (malformed Fields rows are now violations);
    F3 (each fixture is checked against its labelled state);
  - partly accepted: F6 (the id set is extended);
  - rejected: F1 (`childrenOf` keeps `alerts`, and `alerts[]` is checked
    on the element walk); F7 (a spurious env-var match fails loudly).

## Harvest
<!-- single-copy: updated in place each harvest; ids only, never restated content -->
fresh-as-of: 2026-10-22 · started (PHASE-07 complete; Q 88da980)

### Produced

SL-031 (scope, research, notes, plan.toml/plan.md, phase sheets PHASE-01..12);
DEC-110 through DEC-120, with amendments (incl. 2026-10-22b); IDE-016;
IMP-051 § Operator decisions; design run `dr-01a160a3…` locked; RV-058
concluded, all 15 findings verified; memory
`mem.pattern.review.codex-exec-hostile-reviewer`.

### Learned

- Codex `tool_timeout_sec` defaults to 60 s.
- pi-mcp re-reads its policy on every call; profiles are read only at
  start-up.
- Node refuses type stripping under `node_modules`.
- satan's forms depend on the private `inputs.agents` flake.
- Nothing type-checks `pi/` today (RV-058 F-2): expect `tsc --noEmit` errors
  in PHASE-01.

The first four are in `research/research.md` and the DECs; the last is in the
plan.

From execution (PHASE-01..05):

- pi_agent policy maxima: 6 requests per call; cached tokens count toward
  `tokens` (now 320k), so a reused session is short-lived. Ask for batched
  reads and a capped answer; on a ceiling, continue the session with
  `tools: ["read"]` and "answer now, no tool calls".
- pi run with `cwd: ~/dev/quotient` cannot see satan's `.doctrine/` (jail
  view): paste design text into the prompt.
- `npm ci` hangs on the registry audit call here: use `--no-audit`.
- `doctrine slice verify-vt` reports Q-side VT rows UNATTRIBUTABLE (it
  attributes through satan's git); the keyword check is the evidence.
- PHASE-04 was completed without first entering `in_progress`, so it has no
  conformance boundary recorded (warning at completion).
- The pi `read` profile has no `node` on PATH: ask for review by reading, not
  running.
- pi reviews overclaim: 3 of the 4 PHASE-05 findings fell to a code read.
  Adjudicate each finding against the code before acting on it.

### Open

- Uncommitted: CLAUDE.md and flake.nix (operator's edits, not SL-031's).
- PHASE-07 complete; license MIT by operator decision 2026-10-22 (Q 88da980).
  Next: `/phase-plan` PHASE-08.
- PHASE-08: add `help/` to the drift test's shipped-text scan, and make the
  `profiles` help section carry the profile grammar (the example profiles
  point to it).
- PHASE-10: write calls must not be rooted at, or above, the server's launch
  dir (EX-5 step 8).
- PHASE-09 pack-check: `npm ci --no-audit` (audit call hangs).
- Operator gates: PHASE-10
  (policy write, smoke confirmation), PHASE-11 VH-1, PHASE-12 (push, publish:
  separate go-aheads).
- No open QUE or ASM.
