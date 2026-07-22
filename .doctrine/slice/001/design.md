# Design SL-001: Bough feature flag: satan-bough-tools-enabled

<!-- Reference forms (.doctrine/glossary.md § reference forms): entity ids padded
     (SL-020, REQ-059, ADR-004); doc-local refs bare — OQ-1 (§6), D1 (§7),
     R1 (§10), Q1. -->

## 1. Design Problem

Bough integration is unconditional. A machine without bough (or a user who
doesn't want it) gets `bough_unreachable` sensor alerts and a
`:bough "unreachable"` sensor_status — a disabled feature reporting as a
failing one. We need a switch that makes bough *absent*: no tool, no evidence,
no sensor signal, no alerts. Irrelevant signal, not defect signal.

Brief: `docs/bough-feature-flag-brief.md`.

## 2. Current State

Bough touches seven surfaces (RN-3 corrected the original five-surface
account):

- **Load**: `satan-memory.el:15` and `satan-memory-evidence.el:41` both
  `(require 'satan-tools-bough)`.
- **Registration**: `satan-tools-bough.el` calls `satan-tool-register` for
  `bough_read` at top level (load time).
- **Mode allowlists**: 7 registered modes carry `"bough_read"` in `:tools` —
  5 specs in `satan-mode.el`, plus `tick-pulse` and `tick-agent` whose
  defaults in `satan-tick.el` (`satan-tick-register`) include it.
  `satan-mode-check-tool-references` hard-errors at startup if any `:tools`
  entry names an *unregistered* tool — registration and allowlists must stay
  consistent.
- **Exposure/dispatch**: every consumer reads the list via
  `(plist-get mode :tools)` — broker dispatch (`satan-broker.el:345`), broker
  manifest (`satan-broker.el:572`), MCP dispatch (`satan-mcp.el:312`). The MCP
  interactive mode *snapshots* the registry union
  (`satan-mcp--interactive-tools`) into its `:tools` at registration; MCP
  `tools/list`, the session manifest, and the description preflight call the
  union helper live.
- **Evidence**: `satan-memory-evidence--assemble` makes three bough calls
  (`--bough-recent`, `--bough-active`, `--bough-day`) and synthesises
  `:bough` sensor_status from attempt/ok counters (`--bough-status`). Zero
  attempts currently maps to `"ok"` — gating only the calls would still emit
  a `:bough` key.
- **Sensor capsule render**: `satan-sensor-render-block` iterates the fixed
  `satan-sensor--source-order` (which contains `:bough`) and
  `satan-sensor--render-status` maps a nil/absent value to `"ok"` — an absent
  `:bough` key still renders `bough=ok` to the model (RN-1). *Not*
  absent-key-safe, contrary to the brief's original claim.
- **Truncation metadata**: hard-cap pass 5 in `--truncate` unconditionally
  writes `:bough_recent nil` and records `"bough_recent"` in `:truncated_at`,
  even when there was no bough evidence to drop; the tank renders
  `:truncated_at` labels verbatim (RN-4).

Genuinely absent-key-safe downstream (verified): alert cause derivation
(`--derive-causes`), canon rules, observer predicates, tank evidence render.
The Python harness names `bough_read` in its tier-2 drop set
(`harness/runloop.py`) but only filters tools already supplied by the
manifest — inspected, intentionally unchanged (RN-3).

## 3. Forces & Constraints

- **Absent, not degraded**: the `:bough` key must be *missing* from
  sensor_status, not `"ok"` or `"unreachable"`.
- **Startup invariant**: `satan-mode-check-tool-references` couples the
  registry to the mode-spec `:tools` lists; any gate must keep them
  consistent.
- **Defcustoms are runtime-settable**: a load-time gate (conditional
  `require`/registration) silently ignores a `setq` after startup and can
  leave half-states (tool registered but evidence gated). Emacs users expect
  `M-x customize` to take effect without restart where feasible.
- **Write less code / DRY**: 7 mode registrations naming `bough_read` is
  data; editing all 7 duplicates the gate.
- **Audit artifacts are write-once**: `manifest.json` is written exactly once
  per run/session by `satan-audit-open`; `satan-audit-reopen` deliberately
  never rewrites it. Any liveness story must respect this.

## 4. Guiding Principles

- One flag, one seam per concern: gate *exposure*, not *existence*.
- Loaded code and registry entries are inert data; behaviour is what the
  harness can see and call, and what evidence assembly executes.
- Keep the default path (`t`) byte-identical in behaviour.

## 5. Proposed Design

### 5.1 System Model

Runtime gating (D1, reworked per RN-1/RN-2). `satan-tools-bough` stays
required and `bough_read` stays registered regardless of the flag. Two views
exist and must never be conflated:

- **Raw view** — the registry (`satan-tools`) and every mode-spec `:tools`
  list, including the interactive snapshot. Never filtered. Consistency
  checks (`satan-mode-check-tool-references`) and the MCP description
  preflight operate here.
- **Enabled view** — `satan-mode-tools (mode)`: the raw list filtered through
  `satan-tool-enabled-p`, computed once per run/session at advertisement time
  and frozen there (D6), and live per invocation for contract-free surfaces
  (evidence assembly). Everything the harness/model can observe or invoke
  goes through this view.

`satan-mcp--interactive-tools` stays raw (RN-2: registration snapshots its
return value — filtering inside the helper would bake the flag state into the
snapshot and desynchronise it from live consumers).

The flag gates three behavioural seams:

1. **Tool exposure/dispatch** — the enabled view is evaluated **once per
   run/session, at advertisement time** (D6): broker manifest build; MCP
   session mint. The frozen advertised set is stored on the run/session
   (broker run-ctx; `satan-mcp-session` struct) and is the single authority
   for that run/session's manifest, MCP `tools/list`, and dispatch. A harness
   that requests a tool outside the advertised set gets the existing
   tool-denied path.
2. **Evidence assembly** — `--assemble` skips the three bough calls and the
   `:bough` sensor_status synthesis entirely when disabled, and hard-cap
   pass 5 in `--truncate` becomes conditional on a non-nil `:bough_recent`
   so no phantom `"bough_recent"` truncation label appears (RN-4).
3. **Sensor capsule render** — `satan-sensor-render-block` builds segments
   only for keys `plist-member`-present in sensor_status (RN-1). An absent
   `:bough` produces no `bough=...` segment; a present-but-nil value keeps
   today's `"ok"` mapping. Line shape stays constant for a given
   configuration, preserving capsule diff-friendliness.

### 5.2 Interfaces & Contracts

- `satan-bough-tools-enabled` defcustom, `:type 'boolean`, default `t`, in
  `satan-custom.el` (early-loaded; the customize group lives there).
- `satan-tool-enabled-p (name)` predicate in `satan-tools.el`: returns nil for
  `"bough_read"` when the flag is nil, t otherwise. The single point a future
  feature flag extends.
- `satan-mode-tools (mode)` → enabled subset of the mode's `:tools`.
- Frozen advertised set (D6/RN-8): broker prepare plist key `:tools_allowed`;
  `satan-mcp-session` slot `tools`. Computed once at advertisement time from
  `satan-mode-tools`; the only tool list advertised surfaces may read.
- Contract when disabled: manifest `:tools`/`:tools_allowed` exclude
  `bough_read`; MCP `tools/list` excludes it; dispatch denies it;
  `sensor_status` has no `:bough` key; `:bough_recent` / `:bough_active` /
  `:bough_day` are nil.

### 5.3 Data, State & Ownership

The flag is user-owned customization. Mode specs and the tool registry are
unchanged as data — `satan-mode-check-tool-references` still passes because
`bough_read` remains registered.

D6 adds one piece of derived, immutable, per-run/session state (RN-8): the
frozen advertised tool set, computed once from the enabled view immediately
before manifest construction and reused, never recomputed. Representation:
a `:tools_allowed` key on the broker prepare plist (retained by the
`satan-run` struct, read at dispatch via `satan-run-prepare`), and a `tools`
slot on `satan-mcp-session` (in scope for `tools/list`, session manifest,
and `tools/call` alike). Owned by the run/session; dies with it.

### 5.4 Lifecycle, Operations & Dynamics

Toggle semantics (RN-2, reworked per RN-6): tool availability is **frozen per
run/session** (D6). The enabled view is computed once — at broker manifest
build / MCP session mint — and that frozen set backs the manifest,
`tools/list`, and dispatch for the run/session's entire life. `manifest.json`
is a write-once audit artifact; freezing makes manifest/list/call agreement
hold by construction, including across a mid-session toggle (the session
simply keeps its mint-time view). `nil→t` and `t→nil` take effect at the
next run/session start; evidence assembly, which is per-invocation and
carries no advertised contract, reads the flag live at each `--assemble`.
No re-registration is ever required, and no listed-but-denied (or
hidden-but-callable) half-state is reachable.

The MCP description preflight (`satan-mcp--check-tool-descriptions`)
deliberately checks the **raw** union: a bough description file is required
even when bough is disabled, so a later `nil→t` toggle cannot move the R7
fail-fast (missing description signals during schema build) from startup into
a live session (D5).

### 5.5 Invariants, Assumptions & Edge Cases

- Flag `t` (default): behaviour identical to today, including
  `bough_unreachable` alerts — those remain correct defect signal — and the
  sensor line still renders `bough=...` (present key, unchanged mapping).
- Flag nil: `bough_active: 0 nodes` renders in the tank (nil-safe, accepted;
  see Non-Goals in `slice-001.md`); the sensors line carries no `bough=`
  segment; `:truncated_at` never names bough labels.
- `--bough-call` is unreachable from `--assemble` when disabled; direct
  callers of `satan-tool/bough-read` outside evidence/dispatch: none (grep —
  evidence wrappers and registration only).
- The `cue_only` assemble path already skips recent/day but still calls
  `--bough-active`; the disabled gate must dominate `cue_only` for all three
  calls and the status synthesis.
- Hard-cap contract (RN-7): `--truncate`'s docstring calls HARD-CAP
  "mandatory", but the pass chain has never enforced it — pass 5 only drops
  `:bough_recent`, so an excess in any other field already exceeds the cap
  today. This slice narrows the documented contract to "deterministic
  best-effort pass chain; pass 5 is the last resort for the historically
  largest field" and does not add a general final reducer (pre-existing gap,
  independent of the flag; backlog item filed). The disabled-path test
  asserts label honesty, not byte-cap enforcement.
- MCP `--check-tool-descriptions` checks the raw union (D5): a missing bough
  description file fails startup regardless of the flag.

## 6. Open Questions & Unknowns

- OQ-1: should the tank hide the `bough_active` line when disabled? Cosmetic;
  out of scope (slice Non-Goal), revisit on feedback.

## 7. Decisions, Rationale & Alternatives

- **D1: runtime exposure gate over load-time gate.** Alternative A — gate the
  `require`s, registration, and edit 7 mode `:tools` lists (5 static specs
  plus the two tick registrations) — rejected: touches
  more surfaces, duplicates the gate across mode data, risks
  `satan-mode-check-tool-references` startup errors if the two gates drift,
  ignores runtime `setq`, and invites byte-compile/load-order warnings.
  Runtime gating is one predicate + one accessor + one evidence conditional.
- **D2: filter at dispatch as well as listing.** Defence in depth is nearly
  free (same accessor at the existing allowlist argument) and turns a stale
  harness manifest into the established tool-denied path instead of a
  successful bough call.
- **D3: skip sensor_status synthesis, don't remap it.** `--bough-status`
  keeps its current semantics; disabled means the key is never built, so the
  "zero attempts → ok" mapping stays untouched for the enabled path.
- **D4: presence-aware sensor capsule render (RN-1).** Render a segment only
  for keys present in the sensor_status plist (`plist-member`); keep the
  nil→`"ok"` mapping for *present* keys. Alternative — remove `:bough` from
  `satan-sensor--source-order` when disabled — rejected: mutating a defconst
  on a flag couples render order to config state and breaks the raw/enabled
  separation.
- **D5: description preflight stays raw (RN-2 corollary).** Requiring the
  bough description file even when disabled costs nothing on a working
  install and guarantees a `nil→t` toggle can never crash schema generation
  mid-session. "Absent" is a model-facing contract, not an operator-facing
  one.
- **D6: tool availability frozen per run/session (RN-6).** The enabled view
  is evaluated once at advertisement time and stored on the run/session;
  manifest, `tools/list`, and dispatch all read the frozen set. Alternatives
  rejected: rewriting `manifest.json` on toggle violates the write-once audit
  contract; live per-request filtering leaves the manifest permanently stale
  against list/dispatch (the RN-6 half-state). Freezing trades mid-session
  liveness — which no consumer needs — for unconditional
  manifest/list/dispatch agreement.
- **D7: narrow the hard-cap contract instead of adding a final reducer
  (RN-7).** The mandatory-cap wording was never true; making it true is a
  truncation redesign, not a bough concern. Keep pass 5 conditional (label
  honesty), file the behavioural fix as ISS-001, and reword **all three**
  contradictory documentation surfaces in this slice to the same
  best-effort/last-resort semantics: the `--truncate` docstring
  (`satan-memory-evidence.el:553-558`), the
  `satan-memory-evidence-budget-hard-cap` defcustom doc ("Hard byte cap",
  `satan-memory-evidence.el:79-81`), and the durable memory design's "hard
  cap 64 KB / oversize triggers truncation" claim
  (`docs/memory/design.md` §4.3). Wording-only; the behavioural gap stays
  with ISS-001.

## 8. Risks & Mitigations

- R1: a `(plist-get mode :tools)` consumer added later bypasses the filter.
  Mitigation: `satan-mode-tools` docstring names the invariant; test asserts
  no production call sites of `(plist-get mode :tools)` outside the accessor
  (cheap grep-style ert check) — or at minimum the three known sites are
  covered by behaviour tests.
- R2: sensor_status key-order change (append-built plist) breaks a renderer.
  Mitigation: with D4 the capsule render is presence-aware by construction;
  alert derivation was already absent-key-safe; tests cover both flag states.
- R3: a mode registered after `satan-mcp-register-interactive-mode` (or a
  future tool) never appears in the interactive snapshot. Pre-existing
  staleness, orthogonal to the flag — out of scope, noted for a follow-up.

## 9. Quality Engineering & Validation

ert, red/green, in `satan/test/`:

- `satan-memory-evidence-test.el`: with flag nil — `satan-tool/bough-read`
  never invoked (cl-letf trap that signals), `sensor_status` plist lacks
  `:bough` (`plist-member` ⇒ nil), bough evidence fields nil; an oversized
  disabled assembly runs passes 1–4 and records **no** bough label in
  `:truncated_at` (RN-4; asserts label honesty, not byte-cap enforcement —
  RN-7/D7). With flag t — existing behaviour unchanged (existing tests).
- Documentation reconciliation (D7, verified by agent at audit): the
  `--truncate` docstring, the `budget-hard-cap` defcustom doc, and
  `docs/memory/design.md` §4.3 all carry the narrowed best-effort wording;
  no surface still claims a mandatory/enforced cap.
- `satan-sensor-alerts-test.el`: absent `:bough` key ⇒ rendered sensors line
  contains no `bough=` segment (RN-1); present-nil ⇒ `bough=ok` (existing
  mapping); flag t ⇒ line unchanged.
- `satan-tools-test.el`: `satan-tool-enabled-p` / `satan-mode-tools` filter
  `bough_read` iff disabled; other tools unaffected; all 7 bough-carrying
  modes (5 in `satan-mode.el` + tick-pulse + tick-agent) covered via the
  accessor (RN-3).
- MCP/broker transition matrix (RN-5, freeze semantics per D6), on the
  existing fixtures (`satan-mcp-test.el` registry reset + real
  `tools/list`/`tools/call` + minted `manifest.json` inspection;
  `satan-broker-test.el` manifest fixtures):
  - static: flag nil at session/run start ⇒ manifest `:tools`/
    `:tools_allowed` and `tools/list` exclude `bough_read`; dispatch denies
    it. Flag t ⇒ all three include/allow it.
  - mid-session toggle, both directions: manifest, `tools/list`, and
    `tools/call` all continue to reflect the **mint-time** flag state —
    three-way agreement is asserted, not just list/dispatch (RN-6).
  - next session/run after a toggle reflects the new flag state.
  - description preflight fails on a missing bough description regardless of
    flag state (D5).
- `satan-mode-check-tool-references` passes under both flag states.

## 10. Review Notes

### Inquisition round 1 (codex)

RN-1 — **[BLOCKER] Removing `:bough` from `sensor_status` does not make the
sensor signal absent.** Expected: the disabled integration has “no sensor
signal” (§1) and downstream sensor rendering is absent-key-safe (§2). Observed:
the renderer always iterates the fixed source order containing `:bough`
(`satan/satan-sensor-alerts.el:51-56`, `satan/satan-sensor-alerts.el:95-101`),
and deliberately maps a missing value to `"ok"`
(`satan/satan-sensor-alerts.el:68-75`). The existing test nails this behaviour
to the door: nil renders as `"ok"` (`satan/test/satan-sensor-alerts-test.el:30-31`).
Thus a disabled run still tells the model `bough=ok`; the claimed absence is
false even though alert derivation is nil-safe. Penance: D1 must add a
presence-aware render seam (for example, filter `satan-sensor--source-order`
by `plist-member`, or construct rendered segments only for present keys) and
validate that an absent `:bough` produces no `bough=...` segment. The contrary
claim in §2 and the slice Non-Goal must be burned out before planning.

RN-2 — **[BLOCKER] The MCP runtime-toggle story is internally contradictory
and admits a listed-but-denied half-state.** Expected: §5.4 promises that a
runtime toggle takes effect without re-registration or half-states, while the
interactive mode's snapshot is filtered only at manifest/list/dispatch time.
Observed: interactive registration snapshots the return of
`satan-mcp--interactive-tools` into the mode `:tools`
(`satan/satan-mcp.el:74-79`, `satan/satan-mcp.el:90-100`). The design also says
that same helper itself will apply the live feature filter (§5.1), and live MCP
listing calls it directly (`satan/satan-mcp.el:271-283`), while dispatch checks
the previously snapshotted mode list (`satan/satan-mcp.el:294-313`). If MCP is
registered while the flag is nil and the flag is then set to t, `tools/list`
will expose `bough_read` but the interactive mode snapshot still lacks it, so
dispatch denies the advertised tool. The per-session audit manifest is another
live-helper consumer (`satan/satan-mcp.el:162-180`), and the missing-description
preflight is yet another (`satan/satan-mcp.el:119-135`), so merely swapping the
helper's semantics moves the inconsistency. Penance: D1 must define separate
raw-registry and enabled-tool views, identify one authoritative live view for
interactive manifest, `tools/list`, description validation, and dispatch, and
specify the semantics of toggling both nil→t and t→nil while the MCP server and
a session are live. Break this half-state upon the wheel; do not defer it to
implementation.

RN-3 — **[MAJOR] The bough/tool inventory is incomplete: there are seven
built-in mode registrations, not five, and a harness-side enumeration is
omitted.** The five lists in `satan-mode.el` are real
(`satan/satan-mode.el:86-102`, `satan/satan-mode.el:114-127`,
`satan/satan-mode.el:139-151`, `satan/satan-mode.el:162-174`,
`satan/satan-mode.el:185-196`), but `satan-tick-register` creates `tick-pulse`
from defaults that also contain `bough_read` (`satan/satan-tick.el:63-78`,
`satan/satan-tick.el:95-96`) and explicitly creates `tick-agent` with it
(`satan/satan-tick.el:106-119`). The Python harness also names `bough_read` in
its cumulative tier-2 drop set (`satan/harness/runloop.py:32-45`), with a test
fixture that exercises the name (`satan/harness/test_gptel_harness.py:428-442`).
The harness constant is harmless when the manifest omits the tool because it
only filters tools already supplied (`satan/harness/runloop.py:62-68`), but it
is still a missed touchpoint; the two tick modes are live mode data whose
disabled behaviour needs coverage. Penance: correct §2/§3/D1's five-list
account to seven registered modes, record the harness classifier as inspected
and intentionally unchanged, and include tick-pulse/tick-agent in the accessor
validation. The present inventory bears false witness and must be scourged
clean.

RN-4 — **[MAJOR] Disabled bough can still reappear in truncation metadata.**
Expected: disabled output treats bough as absent, while the three evidence
fields are nil. Observed: hard-cap pass 5 unconditionally writes
`:bough_recent nil` and appends the string `"bough_recent"` to `:truncated_at`
whenever the whole evidence object exceeds the hard cap, even when there was no
bough evidence to drop (`satan/satan-memory-evidence.el:595-600`). The tank
renders every `:truncated_at` label verbatim (`satan/satan-tank.el:205-208`). A
large disabled evidence window can therefore announce that bough evidence was
truncated when none was collected. Existing truncation tests cover populated
bough data only (`satan/test/satan-memory-evidence-test.el:202-218`). Penance:
make pass 5 conditional on a present/non-nil bough payload (or define a more
general hard-cap pass that records only material mutations), and test an
oversized disabled assembly for both size behaviour and absence of bough
truncation labels.

RN-5 — **[MAJOR] §9 does not test the runtime guarantee on which D1 is sold.**
The proposed checks cover static flag states, but no validation toggles the flag
after interactive registration/start or during a live MCP session. This omission
matters because startup explicitly re-registers the interactive snapshot only
at `satan-mcp-start` (`satan/satan-mcp.el:430-448`). The existing MCP fixture is
capable of the required assertions—it resets registries and registers the
interactive mode (`satan/test/satan-mcp-test.el:25-49`,
`satan/test/satan-mcp-test.el:69-78`), already drives real `tools/list`
(`satan/test/satan-mcp-test.el:206-248`) and real `tools/call`
(`satan/test/satan-mcp-test.el:250-270`), and already tests missing-description
startup (`satan/test/satan-mcp-test.el:449-459`). Broker manifest fixtures also
exist (`satan/test/satan-broker-test.el:373-440`). Penance: add an explicit
transition matrix (pre-start nil/t, post-start nil→t and t→nil, and live-session
manifest/list/call agreement) plus disabled missing-description coverage. The
tests are implementable; the design's current list simply fails to demand the
ones that adjudicate its central claim.

Verified true:

- Both stated load points require `satan-tools-bough`
  (`satan/satan-memory.el:15`, `satan/satan-memory-evidence.el:41`), and the tool
  registers at top level (`satan/satan-tools-bough.el:322-358`). Keeping it
  registered makes the raw consistency guard independent of the flag.
- `satan-mode-check-tool-references` does exactly what §2 says: it walks every
  registered mode's raw `:tools`, compares names with the raw tool registry,
  and signals on missing names (`satan/satan-mode.el:60-78`); the shipped pass
  and typo failure have ERT coverage (`satan/test/satan-mode-test.el:11-25`).
- The three broker/MCP raw mode-list consumers named in §2 exist at
  `satan/satan-broker.el:345`, `satan/satan-broker.el:572`, and
  `satan/satan-mcp.el:312`. Broker dispatch uses the supplied allowlist and
  returns the established “tool not allowed” result before invoking a handler
  (`satan/satan-tools.el:153-180`).
- Evidence assembly makes the three claimed bough reads: recent, active, and
  day (`satan/satan-memory-evidence.el:700-708`), including the `:cue_only`
  edge where recent/day are skipped but active still runs. The bough status
  helper really maps zero attempts to `"ok"`
  (`satan/satan-memory-evidence.el:290-299`), and current construction always
  inserts `:bough` (`satan/satan-memory-evidence.el:709-717`).
- Alert cause derivation is genuinely absent-key-safe: it reads each ordered
  key, maps nil to no kind, and emits no tuple (`satan/satan-sensor-alerts.el:138-168`).
  The alert checker does reset the persisted bough streak on an absent key, but
  does not create a bough cause or alert (`satan/satan-sensor-alerts.el:249-257`,
  `satan/satan-sensor-alerts.el:340-397`).
- Canon bough rules are nil-safe: recent-status iteration stops on nil and
  active-focus requires both focus and active evidence
  (`satan/satan-memory-canon.el:373-413`). The observer bough predicate passes
  nil safely to `cl-some` (`satan/satan-observer-classify.el:266-279`).
- The tank evidence renderer is nil-safe in the narrow, claimed sense:
  `(length nil)` yields zero and the row renderer returns an empty string for
  nil nodes (`satan/satan-tank.el:154-168`, `satan/satan-tank.el:170-199`). It
  will intentionally retain `bough_active: 0 nodes`; this is distinct from the
  false sensor-render claim in RN-1.
- The disabled evidence branch described in §5 is structurally implementable
  at the common `assemble-with-bounds` seam used by percept, memory tools,
  observer, and tank; all three bough wrappers are called only from that
  assembler in production (`satan/satan-memory-evidence.el:631-736`, with
  callers at `satan/satan-percept.el:66`, `satan/satan-tools-memory.el:137`,
  `satan/satan-observer-classify.el:121`, and `satan/satan-tank.el:383-384`).
- The proposed defcustom home is early and cycle-safe at the level claimed:
  `satan-custom` defines the group as a zero-SATAN-dependency leaf
  (`satan/satan-custom.el:18-26`), `satan-tools` already requires it
  (`satan/satan-tools.el:22-25`), and the aggregate loads custom/tools before
  modes, tick, and MCP (`satan/satan.el:27-57`).
- Existing broker and MCP fixtures make static manifest/list/dispatch assertions
  feasible, and the harness consumes broker manifest tools verbatim rather than
  resurrecting absent tools (`satan/harness/bundle.py:34-46`,
  `satan/harness/runloop.py:173-192`).

> **HERESIS URITOR; DOCTRINA MANET**

### Adjudication round 1 (claude)

Every finding was independently re-verified against the source before
acceptance. All five confirmed; none contested.

- RN-1 **accepted** (verified: `satan-sensor-alerts.el` — fixed source order
  + nil→`"ok"` mapping). Resolved by D4 (presence-aware render, third seam in
  §5.1); §2 corrected; slice Non-Goals and the brief's false
  "harmless when absent" claim corrected.
- RN-2 **accepted** (verified: registration snapshots
  `satan-mcp--interactive-tools`; `tools/list`/manifest/preflight call it
  live). Resolved by the raw/enabled two-view model in §5.1, toggle semantics
  in §5.4, and D5 (raw description preflight).
- RN-3 **accepted** (verified: `satan-tick-register` defaults carry
  `bough_read`; tick-pulse + tick-agent registered). §2 inventory corrected
  to seven surfaces / 7 modes; harness classifier recorded as inspected,
  unchanged; §9 covers tick modes.
- RN-4 **accepted** (verified: `--truncate` pass 5 unconditional). Resolved
  in §5.1 seam 2: pass 5 conditional on non-nil `:bough_recent`; §9 adds the
  oversized-disabled test.
- RN-5 **accepted**. §9 now demands the transition matrix (nil→t, t→nil,
  live-session list/dispatch agreement) and disabled missing-description
  coverage.

Design amended in place; ready for round 2 or lock.

### Inquisition round 2 (codex)

RN-1 — **[RESOLVED; prior BLOCKER]** D3 now removes the `:bough` pair at
construction and D4 makes rendering presence-aware.  This is the correct
two-part repair: the current assembler always constructs the pair
(`satan/satan-memory-evidence.el:709-717`), while the current renderer walks a
fixed source list and turns `plist-get` nil into `"ok"`
(`satan/satan-sensor-alerts.el:51-56`, `satan/satan-sensor-alerts.el:68-75`,
`satan/satan-sensor-alerts.el:93-104`).  `plist-member` distinguishes an absent
key from a present key whose value is nil, so the amended D4 contract preserves
present-nil as `bough=ok` while suppressing an omitted key
(`.doctrine/slice/001/design.md:107-115`,
`.doctrine/slice/001/design.md:188-196`).  The amended tests exercise both
halves (`.doctrine/slice/001/design.md:221-228`).

RN-2 — **[RESOLVED; prior BLOCKER]** The raw/enabled two-view model repairs the
snapshot half-state.  Registration may continue to snapshot the raw registry
union (`satan/satan-mcp.el:74-100`), while the five exposure/dispatch consumers
identified by the design are explicitly assigned the live enabled view
(`.doctrine/slice/001/design.md:89-105`).  The remaining production
`(plist-get mode :tools)` consumers are broker dispatch, broker manifest, and
MCP dispatch (`satan/satan-broker.el:345`, `satan/satan-broker.el:572`,
`satan/satan-mcp.el:301-313`); MCP `tools/list` and session-manifest schema
construction currently use the raw union directly (`satan/satan-mcp.el:162-180`,
`satan/satan-mcp.el:271-283`) and are both named replacement sites.  No other
model-facing reader of the interactive raw snapshot was found.  D5 is also
mechanically coherent: startup re-registers the raw snapshot before invoking
the preflight (`satan/satan-mcp.el:444-448`), and the preflight deliberately
checks the raw registry union (`satan/satan-mcp.el:119-135`).  The temporal
meaning of the session manifest after a live toggle remains defective, but
that is a lifecycle problem, not an unfiltered raw-view leak; see RN-5/RN-6.

RN-3 — **[PARTIAL; prior MAJOR]** The operative inventory and validation matrix
now correctly cover all seven modes (`.doctrine/slice/001/design.md:19-38`,
`.doctrine/slice/001/design.md:229-232`), and the harness tier-drop reference is
now recorded as inspected and intentionally unchanged
(`.doctrine/slice/001/design.md:54-58`).  Two stale five-mode claims remain:
the DRY force still says “5 mode lists” and D1 still says the rejected
alternative edits “5 mode `:tools` lists”
(`.doctrine/slice/001/design.md:71-72`,
`.doctrine/slice/001/design.md:178-183`).  Exactly what remains: correct both
statements to seven (five static mode specs plus the two tick registrations)
before lock.

RN-4 — **[RESOLVED; prior MAJOR]** Conditioning pass 5 on a non-nil
`:bough_recent` is sufficient to discharge the phantom-label finding.  The
current defect is precisely that pass 5 records `"bough_recent"` whenever the
encoded value exceeds the cap, even if setting that already-nil field changes
nothing (`satan/satan-memory-evidence.el:553-600`).  Under the amendment,
disabled assembly and enabled `cue_only` assembly both have nil recent evidence
and therefore correctly do not claim that bough data was dropped; `cue_only`
does not create a counterexample merely because it also produces nil
(`satan/satan-memory-evidence.el:700-708`,
`.doctrine/slice/001/design.md:107-110`,
`.doctrine/slice/001/design.md:165-167`).  The broader hard-cap guarantee is a
different, newly exposed defect; see RN-7.

RN-5 — **[PARTIAL; prior MAJOR]** The amended matrix makes list/dispatch
transitions implementable in both directions using existing real MCP fixtures:
the suite already drives `tools/list` and `tools/call`
(`satan/test/satan-mcp-test.el:206-270`).  Static session-manifest inspection is
also implementable because the fixture locates the minted `manifest.json`
(`satan/test/satan-mcp-test.el:321-364`).  What is still missing is the
round-1-required *live-session manifest/list/call* agreement: the transition
cases assert only list and dispatch, while the session manifest is tested only
at initial state (`.doctrine/slice/001/design.md:233-243`).  This omission is
not just test coverage; the manifest cannot currently satisfy that transition
contract.  RN-6 states the required design decision.

RN-6 — **[BLOCKER] The live-toggle model leaves the MCP session manifest in a
permanent stale half-state.** The amendment says the flag takes effect on the
next manifest build, including mid-session, and presents the session manifest
as an enabled-view consumer (`.doctrine/slice/001/design.md:101-106`,
`.doctrine/slice/001/design.md:138-146`).  In the implementation, however, that
manifest is constructed exactly once when the connection mints its session
(`satan/satan-mcp.el:162-189`) and `satan-audit-open` writes it exactly once
(`satan/satan-audit.el:49-68`); even audit reopen explicitly does not rewrite
it (`satan/satan-audit.el:78-83`).  After either toggle direction, live
`tools/list` and dispatch can change while `manifest.json` continues to assert
the initial set.  There is no “next manifest build” in that session.  Before
planning, D1/D5 must choose and specify one coherent policy: freeze tool
availability per MCP session; version/rewrite the manifest when availability
changes; or explicitly define the manifest as an initial audit snapshot and
withdraw manifest/list/call agreement across mid-session toggles.  The chosen
policy then needs a transition test, not merely the static assertion in §9.

RN-7 — **[MAJOR] The new oversized-disabled validation exposes an unmet
mandatory hard-cap contract.** `--truncate` documents HARD-CAP as mandatory,
but passes 1–4 only reduce bough-day, browser segments, focus segments, and
bough-active annotations; pass 5 only removes bough-recent
(`satan/satan-memory-evidence.el:553-600`).  Once amended pass 5 is skipped for
nil `:bough_recent`, an oversized disabled or `cue_only` value whose excess is
in another field can return above HARD-CAP with no final reducer.  The existing
hard-cap test proves only that populated bough-recent is removed; it never
asserts final encoded size (`satan/test/satan-memory-evidence-test.el:213-218`).
Thus “an oversized disabled assembly truncates” is not a sufficient validation
claim (`.doctrine/slice/001/design.md:221-225`).  Before planning, specify a
non-bough final fallback (or explicitly narrow the hard-cap contract) and make
the test assert encoded output bytes are at most HARD-CAP as well as asserting
the absence of bough truncation labels.

Verified true:

- The amended §2 inventory now names the actual seven bough-carrying modes and
  the separately relevant sensor-render and truncation surfaces
  (`.doctrine/slice/001/design.md:19-52`).
- The raw interactive snapshot can remain unfiltered without leaking through
  a model-facing consumer, provided every consumption site named in §5.1 is
  converted to `satan-mode-tools`; mode registration and reference checking
  remain raw consistency mechanisms (`satan/satan-mcp.el:74-100`,
  `satan/satan-mode.el:67-75`).
- D5's raw description preflight matches the present startup order and fails
  before serving regardless of flag state (`satan/satan-mcp.el:119-135`,
  `satan/satan-mcp.el:430-449`).
- `plist-member` has the required absent-versus-present-nil semantics, and D3's
  construction-time omission supplies the absent case that D4 needs
  (`satan/satan-memory-evidence.el:709-717`,
  `.doctrine/slice/001/design.md:188-196`).
- The pass-5 non-nil guard suppresses the false `"bough_recent"` label for both
  disabled and `cue_only` nil values; it does not by itself enforce the byte
  cap (`satan/satan-memory-evidence.el:595-600`).
- The existing MCP and broker fixture shapes are adequate for static manifest,
  live list, and dispatch assertions; the missing manifest-transition policy
  is a design gap rather than a harness limitation
  (`satan/test/satan-mcp-test.el:206-270`,
  `satan/test/satan-mcp-test.el:321-364`,
  `satan/test/satan-broker-test.el:385-423`).

> **HERESIS URITOR; DOCTRINA MANET**

### Adjudication round 2 (claude)

RN-6 and RN-7 independently re-verified (`satan-audit.el:49-83` — manifest
written once at open, reopen never rewrites; `--truncate` docstring vs pass
chain). Both accepted; RN-3/RN-5 residues accepted.

- RN-3 residue **fixed**: §3 and D1 now say seven registrations.
- RN-5 residue **resolved via RN-6's fix**: §9 asserts three-way
  manifest/list/call agreement across mid-session toggles.
- RN-6 **accepted** → **D6**: tool availability frozen per run/session at
  advertisement time; frozen set backs manifest, `tools/list`, and dispatch.
  §5.1/§5.4 reworked — the "mid-session liveness" claim from adjudication
  round 1 is withdrawn (it was incompatible with write-once audit
  manifests). Toggles take effect at the next run/session; evidence assembly
  stays live per invocation.
- RN-7 **accepted** → **D7**: the mandatory hard-cap wording was never true
  independent of this slice; contract narrowed to documented best-effort,
  pass 5 stays conditional (label honesty), byte-cap enforcement explicitly
  not claimed by the disabled test. General final reducer filed as a backlog
  item rather than smuggled into this slice.

Design amended in place; ready for round 3 or lock.

### Inquisition round 3 (codex)

RN-3 residue — **[RESOLVED; prior MAJOR]** The two stale five-mode statements
have been corrected.  The force now names seven registrations
(`.doctrine/slice/001/design.md:71-72`), and D1 spells out the five static specs
plus two tick registrations (`.doctrine/slice/001/design.md:196-202`).  This now
agrees with the operative inventory and seven-mode validation
(`.doctrine/slice/001/design.md:19-38`,
`.doctrine/slice/001/design.md:262-265`).  No residue remains.

RN-5 residue — **[RESOLVED; prior MAJOR]** The validation matrix now tests the
contract D6 actually chooses: static agreement in both flag states, both
mid-session toggle directions retaining the mint-time view, and the next
session/run adopting the new view (`.doctrine/slice/001/design.md:266-278`).
Those assertions are implementable.  MCP's existing fixture drives real
`tools/list` and `tools/call` requests (`satan/test/satan-mcp-test.el:206-270`)
and locates the minted `manifest.json` (`satan/test/satan-mcp-test.el:321-364`).
The handler already receives the session object for every request
(`satan/satan-mcp.el:249-285`), so the three observations can be made against
one session before and after toggling.  No transition-matrix residue remains.

RN-6 — **[RESOLVED; prior BLOCKER]** D6 replaces the impossible live-manifest
claim with a coherent write-once policy: one enabled set is computed at
advertisement, stored, and used for manifest, list, and dispatch for the
run/session lifetime (`.doctrine/slice/001/design.md:108-114`,
`.doctrine/slice/001/design.md:146-156`,
`.doctrine/slice/001/design.md:221-228`).  Every required consumer can reach
that state:

- MCP mint already has the resolved mode before it builds the manifest and
  constructs the session (`satan/satan-mcp.el:162-217`); adding the designed
  frozen-set slot lets the same local value feed both.  `tools/list` executes
  inside `satan-mcp--handle-message`, whose `session` argument is in scope
  (`satan/satan-mcp.el:249-283`), and `tools/call` already receives that same
  session (`satan/satan-mcp.el:284-313`).
- Broker manifest callers possess the prepare plist as well as the mode
  (`satan/satan-broker.el:623-650`, `satan/satan-broker.el:760-815`).  The
  spawned `satan-run` retains that prepare plist (`satan/satan-broker.el:881-897`),
  and broker dispatch receives the `satan-run` object
  (`satan/satan-broker.el:324-345`).  Changing manifest construction to accept
  or return the frozen set, then reading the stored set through
  `satan-run-prepare`, is therefore structurally possible; no lifetime or
  scope gap forces a second flag read.

The current raw/live readers are exactly the sites D6 must replace: broker
manifest and dispatch (`satan/satan-broker.el:566-588`,
`satan/satan-broker.el:324-345`), MCP manifest, list, and dispatch
(`satan/satan-mcp.el:162-180`, `satan/satan-mcp.el:271-283`,
`satan/satan-mcp.el:294-313`).  No further advertised-surface consumer was
found.  The remaining state-description contradiction is new and narrower
than RN-6's decision; see RN-8.

RN-7 — **[PARTIAL; prior MAJOR]** D7 legitimately withdraws byte-cap
enforcement from this slice, preserves the label-honesty fix, and assigns the
general reducer to ISS-001 (`.doctrine/slice/001/design.md:178-185`,
`.doctrine/slice/001/design.md:229-233`,
`.doctrine/backlog/issue/001/backlog-001.md:7-23`).  The amended test no longer
pretends to prove a byte bound (`.doctrine/slice/001/design.md:253-258`).
However, the narrowed contract has not identified all contradictory
documentation that implementation must reconcile.  The function docstring
still says HARD-CAP is mandatory (`satan/satan-memory-evidence.el:553-558`),
the defcustom still calls 65536 a “Hard byte cap”
(`satan/satan-memory-evidence.el:75-81`), and the durable memory design still
states “hard cap 64 KB” and says oversize triggers truncation
(`docs/memory/design.md:415-422`).  Exactly what remains: D7/§9 must require all
three surfaces to be changed to the same best-effort/last-resort semantics (or
explicitly assign the durable memory-design correction to ISS-001 and stop
claiming this slice has already narrowed the documented contract).  The
downstream `:truncated_at` consumers themselves do not conflict: they copy or
render fired pass labels and make no size guarantee
(`satan/satan-tank.el:175-208`, `satan/satan-tools-memory.el:157-162`,
`satan/satan-tools-hippocampus.el:69-75`).

RN-8 — **[MINOR] D6 introduces frozen per-run/session state while §5.3 still
claims “No new state.”** D6 requires storage on the broker run context and a
new `satan-mcp-session` field (`.doctrine/slice/001/design.md:108-112`), but the
data/ownership section denies any new state and names only the user-owned flag
(`.doctrine/slice/001/design.md:138-142`).  The current prepare plist has no
tool-set key (`satan/satan-run.el:77-94`; the broker-local equivalent is
`satan/satan-broker.el:129-151`), the `satan-run` struct only retains that
prepare plist (`satan/satan-broker.el:80-90`), and `satan-mcp-session` has no
frozen-tools slot (`satan/satan-mcp.el:104-115`).  The design is implementable,
but its ownership account bears false witness.  Amend §5.3/§5.2 to name the
derived immutable state and its representation (for example, a
`:tools_allowed` prepare key and a `tools` session slot), including that it is
computed once before manifest construction and reused rather than recomputed.

Verified true:

- D6 respects the write-once audit constraint: manifests are written at audit
  open, and reopen explicitly does not rewrite them (`satan/satan-audit.el:49-68`,
  `satan/satan-audit.el:78-83`).
- MCP `tools/list` has the session in lexical scope, and MCP dispatch already
  receives the identical session object (`satan/satan-mcp.el:249-313`).
- Broker dispatch has access to the `satan-run` object and its retained prepare
  plist; both spawned and no-child manifest paths have the prepare plist at
  construction time (`satan/satan-broker.el:324-345`,
  `satan/satan-broker.el:623-650`, `satan/satan-broker.el:760-815`,
  `satan/satan-broker.el:881-897`).
- If the five advertised-surface consumers use the stored set as D6 requires,
  none needs to read `satan-bough-tools-enabled`, `satan-mode-tools`, or a raw
  mode list again during that run/session (`satan/satan-broker.el:324-345`,
  `satan/satan-broker.el:566-588`, `satan/satan-mcp.el:162-180`,
  `satan/satan-mcp.el:249-313`).
- D7 does not alter the meaning of `:truncated_at`: it remains a list of pass
  names that actually fired, and its consumers only persist or display those
  names (`satan/satan-memory-evidence.el:553-600`,
  `satan/satan-tank.el:185-208`, `satan/satan-tools-memory.el:157-162`,
  `satan/satan-tools-hippocampus.el:69-75`).
- ISS-001 accurately captures the deferred general-reducer defect and links it
  back to this slice (`.doctrine/backlog/issue/001/backlog-001.md:7-23`).

> **HERESIS URITOR; DOCTRINA MANET**

### Adjudication round 3 (claude)

RN-7 residue and RN-8 re-verified (`satan-memory-evidence.el:79-81` defcustom
doc; `docs/memory/design.md` §4.3; `satan-mcp-session` struct has no tools
slot). Both accepted.

- RN-7 residue **fixed**: D7 now enumerates all three contradictory
  documentation surfaces and requires their rewording in this slice
  (wording-only; behavioural fix stays with ISS-001). §9 adds the
  documentation-reconciliation check.
- RN-8 **fixed**: §5.3 no longer claims "no new state" — it names the frozen
  advertised set as derived immutable per-run/session state with its concrete
  representation (broker prepare `:tools_allowed`; `satan-mcp-session`
  `tools` slot); §5.2 records the same in the contracts list.

Design amended in place; requesting lock verdict.

### Inquisition round 4 (codex)

RN-7 residue — **[RESOLVED; prior MAJOR]** D7 now explicitly requires this
slice to reconcile every contradictory promise: the `--truncate` docstring,
the `satan-memory-evidence-budget-hard-cap` defcustom documentation, and
`docs/memory/design.md` §4.3 (`.doctrine/slice/001/design.md:240-251`).  Those
are the three surfaces that presently claim a mandatory/enforced cap
(`satan/satan-memory-evidence.el:75-81`,
`satan/satan-memory-evidence.el:553-558`, `docs/memory/design.md:415-422`).
Section 9 now verifies that all three carry the same narrowed
best-effort/last-resort wording and that none retains the false guarantee
(`.doctrine/slice/001/design.md:271-280`).  The behavioural reducer remains
cleanly owned by ISS-001 rather than being smuggled into this slice
(`.doctrine/backlog/issue/001/backlog-001.md:7-23`).  No gap remains.

RN-8 — **[RESOLVED; prior MINOR]** Sections 5.2 and 5.3 now tell one consistent
state-ownership story: the enabled set is computed once immediately before
manifest construction, stored as broker prepare `:tools_allowed` or MCP
session `tools`, and never recomputed during that run/session
(`.doctrine/slice/001/design.md:125-153`).  This representation fits the actual
lifetimes already established: broker manifest construction has the prepare
plist, the spawned `satan-run` retains it for dispatch
(`satan/satan-broker.el:760-815`, `satan/satan-broker.el:881-897`,
`satan/satan-broker.el:324-345`), while MCP mint constructs the session before
the request handler uses that same session for `tools/list` and `tools/call`
(`satan/satan-mcp.el:162-217`, `satan/satan-mcp.el:249-313`).  The former false
“No new state” claim is gone, ownership and death are explicit, and no gap
remains.

Verified true:

- D7's three-item documentation inventory is complete for the cap guarantee;
  downstream `:truncated_at` consumers only persist or render fired labels and
  assert no byte bound (`satan/satan-tank.el:185-208`,
  `satan/satan-tools-memory.el:157-162`,
  `satan/satan-tools-hippocampus.el:69-75`).
- D7 keeps implementation behaviour unchanged except for the already-designed
  pass-5 label-honesty guard; the general reducer is durably linked to ISS-001
  (`.doctrine/slice/001/design.md:189-196`,
  `.doctrine/slice/001/design.md:240-251`,
  `.doctrine/backlog/issue/001/backlog-001.md:15-23`).
- RN-8's concrete fields give manifest, list, and dispatch one reachable
  frozen authority on both broker and MCP paths
  (`.doctrine/slice/001/design.md:133-153`).
- No new finding was introduced by the round-3 amendments.

Lock verdict: **sound to lock and proceed to planning.** All round-3 residues
are discharged; no heresy remains within the final review scope.

> **HERESIS URITOR; DOCTRINA MANET**
