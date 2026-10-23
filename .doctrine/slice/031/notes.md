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

## PHASE-09 execution (2026-10-23)

Q `ac7f729` (hostile-audit), `a1104d0` (pack-check), `c56a2a6` (flake);
tagged `v0.1.0` (annotated, local, not pushed). 312 tests, tsc clean,
shellcheck clean on both scripts.

- **Delegation.** Two pi workers (`scripts/pi-agent dispatch-worker`,
  `jailed-pi`, deepseek-flash, thinking medium) in two Q worktrees, in
  parallel; the host ran pack-check, `nix build`, tests and commits.
- **Preflight decisions (operator: no preference).** pack-check owns its
  bash stub form and fake pi (the rig stays test-only); one canned stream it
  writes is both check 2's fixture and the fake pi's output; a real probe
  PASS is left to PHASE-10 (`just quotient-hostile-audit` on the real forms).
- **`serve` is bare.** `quotient` with no verb serves (design sec-2 names
  `serve`; PHASE-02's cli.ts has no such verb). Both scripts run it bare.
- hostile-audit: `--form --capability --model [--exposure]... <root>
  <session-home> <run-dir>`; gateway checks removed (host recipe's,
  PHASE-10 EX-3). The verdict block is byte-identical to SL-029's. SKIP 77
  checked: no args, missing form, ambient `QUOTIENT_POLICY`. A stub form
  reaches the server and FAILs (no attempt), as it should.
- **VA-1 pack-check:** all four PASS from a clone of `514c4b1` (the tarball
  comes from HEAD; the scripts themselves are not packed). After review, check 2
  also asserts the reduced `status.json` is `state: completed`; rerun PASS.
- **VA-1 nix build:** one hash-from-failure round
  (`sha256-7oIHeV7WcQZoQ7SzB78hEEBUtiYTb8T4HhPUJ0iWwrU=`); then green.
  `result/bin/quotient --version` → `0.1.0`; the wrapper execs nodejs 22.23.3;
  the output's `node_modules/` is empty (no devDeps). `result` added to Q's
  `.gitignore` (it was ignored only by the global gitignore).
- pi review (read profile, 17 findings), adjudicated against the code:
  - accepted: F4 (reduce check asserted only a non-empty status.json).
  - rejected: F1 (`pipefail` is set, so `|| fatal` fires); F10 (the
    `!attempt` fail precedes the fallback PASS); F11 (fail-closed is an
    admissible shape by design); F6, F15, F16 (out of the probe's scope /
    evidence kept by design / built bin verified).
  - noted, pre-existing (verdict logic unchanged from SL-029): F9, the
    attempt test matches any bash naming the run root, not specifically the
    append; F8, timeouts SKIP rather than FAIL. Candidates for the
    probe-per-guarantee follow-up.

## PHASE-10 execution (2026-10-23)

satan `47f06e0` (step 2), `578d509` (step 3), `7b2970f` (step 4 profiles),
`eaa15d6` (step 5). Steps 2-3 written by a Sonnet subagent (host nix);
committed and split by the orchestrator. The step-2 commit builds on its own
(`nix build git+file://…?rev=47f06e0#checks…quotient-forms`).

- **One form family, two instances.** `mkFormFamily { prefix, sessionVar,
  dieWithParent }`, `formProbes`, `mkFormCheck`; pi-mcp store paths are
  unchanged. Step 7 deletes the pi-mcp instance in each.
- **`--die-with-parent` is already emitted by jail.nix.** The quotient
  family adds it explicitly anyway (the form states its own G7; the duplicate
  is harmless). The check asserts it is present in each built launcher; a
  negative control (nonsense probe) goes red. A first count-based check was
  vacuous against the generator's copy and was replaced.
- The quotient-forms check also asserts three `exit 64` guards per form (G8).
- `just quotient-forms`: `~/.local/state/quotient/{forms/<cap>,pkg}` GC roots,
  `bin/quotient -> ../pkg/bin/quotient`; `--version` → 0.1.0.
- `quotient-hostile-audit` runs the input's script via
  `packages.quotient-hostile-audit` (nodejs_22, store source), exposure
  `~/.local/share/jail.nix/home/agent` (the old `child_binds`).
- Step 4: scratch root `~/scratch/quotient-smoke` (git, one empty commit).
  Policy draft validated by quotient's `readPolicy`: the old roots plus the
  scratch root, profiles `{read: read, research: read, write: write}`, the
  quotient form links, exposure as above, the old maxima.
- Step 5: `.mcp.json` `quotient` entry, no env. Session restarted; the
  server connected and served the profile table in its instructions.
- **Step 6 smoke (VA-1), 2026-10-23**, all via `mcp__quotient__pi_agent`
  unless stated; run dirs under `~/.local/state/quotient/runs/`:
  - `read`: completed, final true (`run-20261022T224258939Z-2-…`).
  - `research`: completed, final true (`run-20261022T224301814Z-3-…`).
  - `write` at `~/scratch/quotient-smoke`: completed, final true;
    `SMOKE.txt` present; spawn record `form_kind: confined`
    (`run-20261022T224304769Z-4-…`).
  - `write` at satan: refused `view-overlaps-protected` (the root contains
    `.quotient/profiles`).
  - `just quotient-hostile-audit`: PASS on both forms; each delegate ran the
    real append loop and got `No such file or directory` (evidence under
    `~/.local/state/quotient/hostile-audit/{read-wVxOwl,write-x6PYUL}`).
  - `codex exec` (`-c` overrides, `tool_timeout_sec = 360`): completed,
    final true, **but with the stable `~/.local/state/quotient/bin/quotient`
    as `command`, not the printed one.**
- **Finding: `quotient help clients` prints a fragile command.** The realpath
  of `process.argv[1]` (DEC-118) under the nix wrapper is
  `/nix/store/…-quotient-0.1.0/lib/node_modules/@davidlee/quotient/dist/cli.js`:
  it bypasses the node-carrying wrapper (its shebang is `/usr/bin/env node`)
  and dies with the store path at the next rebuild + GC. EX-6's "with the
  printed snippet" was not met as written.
  - **Fixed pre-publish (operator: "fix now"), Q `6c31180`:** `runningBin`
    keeps symlinks (`path.resolve`, no realpath); the nix wrapper exports
    `QUOTIENT_LAUNCHER` (its own `$0`, absolutised); `resolveLocations`
    carries it as `launcher` (normalised; a relative or empty value is
    ignored, never refuses — a hint, not a location); the snippets prefer it.
    Documented in `quotient-policy-1.md`; 315 tests; pack-check PASS.
    Deviation from DEC-118's "realpath'd": recorded here for reconcile.
  - Local tag `v0.1.0` moved `c56a2a6` → `6c31180` (never pushed). satan
    relocked (`nix flake update quotient`), `just quotient-forms` rebuilt.
  - Re-run `codex exec` with the printed snippet's exact values
    (`command = ~/.local/state/quotient/bin/quotient`, cwd, timeout 360):
    completed, final true. EX-6 met.
- **VH-1** given by the operator, 2026-10-23 ("confirmed": the step 6 smoke
  results above, policy written via `install -D -m 0444`).

## PHASE-11 execution (2026-10-23)

- Removal delegated to one Sonnet subagent (main tree, no commit); reviewed and
  committed as `a1cea43` by explicit paths (the operator's staged CLAUDE.md line
  is subsumed by the retargeted block, intent kept: only profile edits need a
  restart).
- Form family: with one instance left the abstraction was dropped —
  `quotientFormFamily` / `formProbes` / `quotientFormsCheck` are plain lets;
  `--die-with-parent` is unconditional and check (f) always asserts it.
- pi-report (EX-2, VT-1/2): `read -ra` over `PI_REDUCE`, default
  `$HOME/.local/state/quotient/bin/quotient reduce`, `-x "${reduce[0]:-}"`;
  the `command -v node` guard is gone (the bin is a nix-wrapped launcher).
  Test case 3 is the stub reducer (`PI_REDUCE="$STUB reduce"`, asserts
  `first=reduce`). Review caught two defects in the hand-back: case 2 passed
  `PI_REDUCE=/nonexistent/quotient reduce` unquoted (ran `reduce` as the
  command; 2 FAIL, while the worker reported 9/9), and case 1 now needed the
  host bin, so it skips when `~/.local/state/quotient/bin/quotient` is absent.
  Result 9/0 on host, 4/0 with `HOME=/nonexistent`; shellcheck clean.
  Gap, pre-existing: `pi-report-test.sh` is not run by `just check`.
- EX-3 residual grep (`pi-mcp|PI_MCP|pi/mcp|pi-run-reduce`, excluding
  `.doctrine`, `node_modules`, `.git`, `.capsule-runs` — the last is in
  `.git/info/exclude`): one hit, `test/flake/forms.test.ts:53`, the
  `doesNotMatch(flake, /pi-mcp/)` guard — intentional. The three
  `.quotient/profiles/*.md` pointed at `pi/mcp/profiles.ts`; now
  `quotient help profiles` (profile digest is recorded, not pinned).
- EX-4: `just check` exit 0 (forms-suite 10/10); `just check-jails` exit 0.
- Policy draft without the scratch root: `~/.local/state/quotient/policy.final.json`,
  `readPolicy` ok.
- Orphaned on host after this phase: `~/.config/pi-mcp/policy.json`; the old
  form links `~/.local/state/pi-mcp/forms` go after EX-5.
- **VH-1 / EX-6:** the operator installed `policy.final.json` with
  `install -D -m 0444`. The scratch root is gone, and `~/.config/emacs` was
  added. A `write` call with `cwd` set to `~/scratch/quotient-smoke` refused
  `root-not-allowlisted`.
- **EX-5** (after the restart, `.mcp.json` without `pi-agent`):
  - The `read` call through `mcp__quotient__pi_agent` returned completed,
    final true, run `run-20261022T234358494Z-2-f2a899b1227d`.
  - The `codex exec` call used the printed snippet's values (command
    `~/.local/state/quotient/bin/quotient`, cwd satan, `tool_timeout_sec`
    360, each passed as `-c`). It returned completed, final true, run
    `run-20261022T234425936Z-2-fcf878006a46`.
- **After EX-5:** deleted `~/.local/state/pi-mcp/forms` (`read`, `write`
  links) and, at the operator's request, `~/.config/pi-mcp/policy.json`.
  `~/.local/state/pi-mcp/{runs,sessions}` are kept as historical evidence.

## PHASE-12 execution (2026-10-23)

- **Push (EX-1).** The operator pushed `main` ("i pushed"). The tag was
  missing from the remote, so the agent pushed `v0.1.0` under the same
  go-ahead. `ls-remote` shows `refs/heads/main` = `6c31180` and
  `refs/tags/v0.1.0` = `1f87d70`, which peels to `6c31180`.
  - Before the push: the GitHub repo already existed, public and empty.
  - A key-pattern scan over `git log -p v0.1.0` found nothing; gitleaks is
    not installed on the host.
- **Pin (EX-2).** `quotient.url` is now `github:davidlee/quotient/v0.1.0`,
  relocked with `nix flake update quotient`.
  - Lock: `path:/home/david/dev/quotient` (narHash `YJVAlK…`) became
    `github` rev `6c311801…` (narHash `gLMuv4…`).
  - Same commit; the narHash differs because a `path:` input copies the
    working directory.
  - After `just quotient-forms`, the bin moved from
    `/nix/store/k22yj3…-quotient-0.1.0` to `/nix/store/jgr1my…-quotient-0.1.0`.
    `quotient --version` reads `0.1.0`.
  - The live call ran from malebolge through `codex exec`, so a fresh server
    on the new bin served it. It returned completed, final true, run
    `run-20261022T235114159Z-2-bf61fef3aec9`, with `profile_source`
    satan's `.quotient/profiles/read.md`, root malebolge and `form_kind`
    confined.
    - One earlier attempt printed `state=undefined`. Codex's model
      (gpt-6-luna) failed to extract the fields; the tool call itself had
      completed. A rerun printing the raw JSON showed final true.
  - `just check` exit 0; `just check-jails` exit 0.
- **Rollback (EX-3).** Set `quotient.url` back to `"path:/home/david/dev/quotient"`
  and run `nix flake update quotient`. Then `just quotient-forms`, and repeat
  one live `read` call (through `codex exec`, or after a session restart).
- **Rename to `@davlee/quotient` 0.1.1** (operator decision; deviates from
  the plan's `@davidlee/quotient` at `v0.1.0` — for reconcile).
  - Why: the operator's npm user is `davlee`, and `@davidlee` belongs to a
    squatter. Unscoped `quotient` is taken (v0.1.4, 2022). `quotient-mcp` was
    considered and rejected, because quotient is a CLI as well as a server.
  - Q `3395eab` renames the package, bumps the version and updates the
    lockfile, the README and `npmDepsHash`. The deps hash moved with the
    lockfile's root name.
  - Q's 315 tests pass, tsc is clean and `pack-check` passes on the tag.
    `v0.1.0` stays where it is.
  - The operator pushed `main` and `v0.1.1`; `v0.1.1` = `b3a3da3`, which
    peels to `3395eab`.
  - satan is re-pinned to `github:davidlee/quotient/v0.1.1`; the lock moved
    `6c31180` → `3395eab`.
  - After `just quotient-forms`, the bin is `/nix/store/30xq7a…-quotient-0.1.1`
    and `--version` reads 0.1.1.
  - Live call through `codex exec` from malebolge: completed, final true,
    run `run-20261023T000138887Z-2-7cc745bc49de`. `just check-jails` exit 0.
  - Rollback is as above, with the earlier pin `v0.1.0` as an option.
- **npm (EX-4).** `npm whoami` returns `davlee`.
  - The first publish attempt from the tag worktree failed in `prepack`:
    there was no `node_modules`, and `pack-check` runs `npm ci` in its own
    copy, not in the caller's checkout. Nothing was uploaded.
  - After `npm ci`, the publish stopped at `EOTP` (2FA by browser), so the
    operator runs it interactively.
- **malebolge Codex config** (operator request, outside SL-031's plan): malebolge
  `1d3b7bb` adds `[mcp_servers.quotient]` to `.codex/config.toml`, with
  `cwd` = satan so writes rooted in malebolge are not
  `view-overlaps-protected`. Verified with a `read` call rooted at malebolge.

## Harvest
<!-- single-copy: updated in place each harvest; ids only, never restated content -->
fresh-as-of: 2026-10-23 · PHASE-10 complete · Q 6c31180 (v0.1.0)

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
- Writing pi workers: `scripts/pi-agent dispatch-worker` under `jailed-pi`
  in a `git worktree` of Q. The jail has node and npm but no nix, and git
  is unusable there (the worktree's `.git` points outside the mount).
- `doctrine slice verify-vt` reports Q-side VT rows UNATTRIBUTABLE (it
  attributes through satan's git); the keyword check is the evidence.
- PHASE-04 was completed without first entering `in_progress`, so it has no
  conformance boundary recorded (warning at completion).
- The pi `read` profile has no `node` on PATH: ask for review by reading, not
  running.
- pi reviews overclaim: 3 of the 4 PHASE-05 findings and all 6 PHASE-08 ones
  fell to a code read.
  Adjudicate each finding against the code before acting on it.

### Open

- Uncommitted: CLAUDE.md (operator's staged edit). The operator's flake.nix
  `typescript` line landed in `47f06e0` (step 2), by operator say-so.
- License MIT by operator decision 2026-10-22 (Q 88da980).
- PHASE-09 complete (Q ac7f729..c56a2a6); tag v0.1.0 now at Q 6c31180.
- PHASE-10 complete (VH-1 given). Next: `/phase-plan` PHASE-11.
- PHASE-08 choices to confirm at audit: `quotient help` exits 1 on an
  unreadable help layer (the design's table lists 0/2); a start-up-refused
  server's instructions and tool description name the failure; help/setup.md
  replaces the README's setup steps.
- ISS-044 (intermittent sentinel error in `just test`) hit the satan gate
  once this session; rerun green.
- PHASE-10: write calls must not be rooted at, or above, the server's launch
  dir (EX-5 step 8).
- Audit: DEC-118 deviation (`help clients` no longer realpaths; wrapper
  `QUOTIENT_LAUNCHER`) — reconcile into the design/DEC. Probe weaknesses F8/F9
  (PHASE-09) — candidate backlog item.
- Operator gates: PHASE-11 VH-1 (reissue policy without the scratch root),
  PHASE-12 (push, publish: separate go-aheads).
- No open QUE or ASM.
