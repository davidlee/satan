# Review RV-055 — reconciliation of SL-029

Adversarial-review ledger. Structured findings live in the sister
ledger toml; this prose companion carries the reviewer's framing.

## Brief

Reconciliation-facet audit of an eight-of-nine slice: PHASE-01..08 are
`completed` with green criteria, PHASE-09 is deliberately `blocked`. The audit
is therefore mostly a **closure** audit — the code has already been read
adversarially by RV-053 (three reviewers, 18 findings, 13 repairs) — so the job
here is not a second line-level review. It is: does the delivered build match
the locked design record, is every claimed criterion actually demonstrated, and
is every remaining gap dispositioned rather than absorbed.

Lines of attack, in the order they were probed:

1. **Verification closure.** Enumerate all 80 `EX-`, 55 `VT-` and 3 `VA-` rows.
   Every `VT` is executable here (54 run green, 1 `UNATTRIBUTABLE`); every `EX`
   is assertable by reading code plus the test that carries it; all three `VA`
   rows belong to PHASE-09 and are unexecuted. The audit must hold the line
   that `VA-1..3` are *not* demonstrated, and trace what that costs elsewhere
   (`verify-vt` attribution, the `flake.nix` conformance cell, the two open
   blockers on the prior ledgers).
2. **Design conformance.** Walk design sec-1..7 against the code, including
   those divergences already recorded (QUE-007's four, DEC-103's three wire
   additions, RV-053 F-16's six). The test is not "is a divergence present" —
   several are consciously taken — but "is the recorded list **complete**". A
   divergence nobody wrote down is what this pass exists to find.
3. **Registry integrity.** `slice conformance` reads recorded phase deltas. A
   concurrent SL-030 session committed into this tree throughout the slice, so
   the deltas' undeclared cell must be read with that knowledge — and the
   design-target selector set must actually name what the phases shipped.
4. **Evidence and authority.** Hold the build to the one-sink, one-ladder,
   fail-closed invariants and to ADR-017's ledger split: `pi/mcp` authors no
   jail token, the flake owns every bind, the audit is the only record.
5. **Lifecycle bookkeeping.** Is the slice's own status an honest account of
   where it is?
6. **Residual register.** RV-053's tolerated and deferred items (F-15, F-17) and
   its open answers (F-3, F-16, F-18) must land somewhere durable, not evaporate
   at handover.

Invariants this pass holds the slice to:

- one usage accumulator, one status, one termination ladder, one cause table;
- a run directory exists only after validation step 8, and an evidence failure
  fails closed;
- nothing in `pi/mcp` outside its tests authors a bwrap token;
- a phase reads `completed` only when its own criteria were demonstrated — and
  reads `blocked` when they were not.

## Synthesis

### What was audited, and how

Target SL-029 at c01735f, on the primary tree. 80 `EX-`, 55 `VT-` and 3 `VA-`
rows were enumerated from `plan.toml`. The `VT` set was run, not read:
`doctrine slice verify-vt 29` reports 54 PASS and one `UNATTRIBUTABLE`
(PHASE-09 VT-1), and `SATAN_TEST_ALLOW_NO_DB=1 just check` is exit 0 with 252
tests, 252 pass, 0 fail. `EX` rows were checked by reading the mechanism and the
test that carries it, in the axis order the phase plan assigned them (accounting
and the terminal answer; the wire shell, policy and posture gate; the profile
snapshot, grammar, root allowlist, ceilings and tool narrowing; session
ownership and reclamation; child-view disjointness and the evidence layout;
argv, the ladder and evidence capture; the gate; the cause table and the latch).
The 3 `VA` rows are all PHASE-09's and are unexecuted.

The mechanical signals were read, not trusted:

- `doctrine slice conformance 29` → 13 undeclared, 1 undelivered, 23 conformant.
  Eleven of the undeclared paths and the single undelivered path dissolve into
  two known causes (F-2, F-1); two are the genuine registry omission F-3 names.
- `doctrine check gate` → green.
- The bwrap-token source scan over `pi/mcp` excluding `*.test.ts` is green, so no
  server module authors a jail token — ADR-017's ownership split holds on this
  surface.

### Closure story

**The build matches its design.** One accumulator counts the stream and the gate
reads it; `resultFor` is the only place a verdict is derived, and its cause table
is the enumeration `TERMINATIONS`/`CAUSE_STATE` rather than a second vocabulary;
one termination ladder serves cancellation, stdin EOF, the gate and an evidence
failure; the run directory is allocated after validation step 8 and its five
files are named once in `evidence.ts`; the child-view check is a containment
predicate over the canonicalised union rather than a bind list. The four
divergence families the slice already records — QUE-007's four, DEC-103's three
wire additions, RV-053 F-16's six — were each re-checked against the code and all
reproduce as described. **Two divergences were not on any of those lists, and
this pass adds them**: the `refuse` run-audit record design sec-2 promises and the
build cannot write (F-4), and the three shipped files missing from design sec-7's
delivery list and from the design-target selector set (F-3). With those two the
correction set is complete as far as this pass can see.

**The slice cannot close on this evidence, and says so.** PHASE-09 carries three
empirical criteria that only a host with `nix` and the llm-gateway can prove.
This host has neither, so PHASE-09 is `blocked`, has no boundary row, and its
`flake.nix` work reads as `undelivered` and `UNATTRIBUTABLE` — attribution
artefacts of the missing row, not missing work (F-1). Two open blockers on prior
ledgers wait on exactly that evidence (RV-043 F-1, RV-053 F-18), and under the
close-gate they refuse the audit→reconcile crossing. The audit's verdict is
therefore: **reconcilable in substance, not yet closable in evidence.**

### Tradeoffs consciously accepted

- **Retrospective ceilings** (DEC-097, operator-accepted 2026-10-20). The gate
  aborts a crossing; it does not prevent the next request, and there is no
  provider output cap. Overshoot is bounded by observation latency plus one
  in-flight request's spend. Recorded for SPEC-001 REQ-004.
- **Accounting scope** (design sec-4). `requests`/`tokens`/`cost` describe this
  run's own provider sends. A nested `pi`, a direct call to the reachable
  gateway, and spend visible only inside a tool result are outside them, as is
  extension-mediated summarization. The per-run gateway token that would bound
  them is IDE-015, not this accumulator. Same REV.
- **The audit-record collapse** (RV-053 F-17, tolerated). `timeout` and `switch`
  are `abort` records carrying a cause rather than kinds of their own. Accepted
  as code; F-4 makes the design say so instead of leaving sec-2 and sec-6
  disagreeing.
- **`child_binds` carries no exposure half** (RV-053 F-3, answered `design-wrong`
  → `demonstrate`). Every member is treated as read-write, so a policy cannot
  declare a read-only fixed mount and the "policy file never writable" rule
  over-refuses one. Deferred to reconcile plus the operator run.

### Standing risks (carried, not resolved)

From RV-053 F-17, all failing safe and all stated in code comments:

1. **Over-broad child env strip.** `childEnv` drops any variable whose *value
   contains* a run path, so a short `PI_MCP_RUN_DIR` can strip `XDG_RUNTIME_DIR`
   or a `PATH` entry and produce a confusing `spawn` failure.
2. **Unbounded buffers.** `serve`'s `pending` accumulator and `spawn`'s
   in-memory `lines` are bounded only by RAM. Fine for the intended prompt
   sizes; nothing bounds a multi-hundred-MB prompt.
3. **No SIGTERM/SIGINT handler.** A driver that kills the server rather than
   closing stdin leaves the child's session alive. EX-11 scopes "never leaves a
   child behind" to stdin EOF, and DEC-103 names EOF as *the* shutdown, so this
   is a declared boundary — but the result vocabulary's `cancelled` reason list
   still says "a driver death", which overstates it.
4. **Stale-lock advice.** Between the `O_EXCL` create and the record write a
   lock is legitimately empty, so `reclaim`'s "must be cleared by an operator"
   can describe a lock that is about to become live. Fail-closed, but an
   operator acting on it would clear a live lock.
5. **Test-harness duplication** (RV-053 F-15, `follow-up`/`dedupe`). ~450 lines
   shared between `spawn.test.ts` and `gate.test.ts`; extraction collides with
   the source scan's "every non-`*.test.ts` file in `pi/mcp` is production"
   rule, so it needs a `pi/mcp/testing/` carve-out. Deferred, benign today.

And one this pass adds to the register: **the tenant of the conformance signal**.
Because a concurrent SL-030 session committed inside PHASE-08's delta, the
`undeclared` cell includes eight paths belonging to another slice. Read it with
F-2's caveat, or a later auditor will attribute SL-030's planning artefacts to
SL-029.

## Reconciliation Brief

Handoff to `/reconcile`. F-1's disposition is **not** in this brief: it is
blocked on an operator run or a human waiver, and no write surface can settle
it.

### Per-slice (direct edit) — `design.md`

- **§7 "Files"** — add three shipped artefacts (F-3): `pi/reduce/cli.ts` (the
  status-line consumer PHASE-01 EX-7 names), `pi/reduce/reduce.test.ts`
  (VT-1..VT-4's carrier), `bin/pi-mcp-hostile-audit` (PHASE-09's hostile driver,
  which §7's verification list already describes without naming). Also advance
  §7's reducer line from `pi-run-status/1` to `/2` if it appears there (QUE-007
  item 4).
- **§2 "Validation order", closing paragraph** — drop the clause "`refuse` in
  the run audit once a run directory exists" (F-4). Every refusal is an
  `attempts.jsonl` line; the run directory does not exist before step 8.
- **§6 "Evidence"** — state the run audit's record vocabulary as the three kinds
  the code emits (`spawn`, `abort`, `exit`) with the cause carried as a field, so
  `timeout` and `switch` are `abort` records (F-4, settling RV-053 F-17 by text).
- **QUE-007 items 1-4** — §7/§5 `final` is derived in the server, not the
  reducer; §5's `backstop` residue → `timeout`; §5's "`session` is always
  present" → `null` on a refusal; §5's result example `pi-run-status/1` → `/2`.
- **RV-053 F-16 items 1-6** — §2 validation order (request shape and the start-up
  profile snapshot precede step 1, justified in code but absent from the record);
  §1 "absent or malformed refuses everything" → state that `maxima` must carry
  `wall_clock_s` (and that a negative maximum is refused), since `maxima: {}`
  currently validates; §1/§5 `transcript_budget_bytes` → `0` means "the
  reducer's full transcript", not "no ceiling"; §5 `status.state` vs `state` for a
  settled stream whose last message ended `pending`; §5 + DEC-093's table vs
  `status.state` for `switch`, `toolUse`, `deferred`; §5's `final` definition —
  whether `final: true` with `result: null` (a textless `stop`) is the intent.
- **RV-053 F-3 `refresh` half** — §3's "the flake check asserts the form's actual
  bind set equals root + session directory + `child_binds`. That is where the
  loop closes" is overstated: the check closes **form-vs-literal**
  (`jailProbes.pi-mcp.shared`), never **policy-vs-form**. Restate it, and restate
  that `child_binds` is `string[]` so a read-only fixed mount cannot be declared.
  Add the policy-schema change to the backlog if it is not adopted now.

### Registry (`doctrine slice selector`, which `slice conformance` reads)

- `add` design-target selectors for `pi/reduce/cli.ts`,
  `pi/reduce/reduce.test.ts` and `bin/pi-mcp-hostile-audit` (F-3). Keep
  `pi/reduce/**` as `scope-relevant` for prime.
- **Do not** record a PHASE-09 boundary row: there is nothing to conclude while
  the phase is `blocked`, and a back-dated row would claim an execution that did
  not happen (F-1).

### Governance / spec (REV)

- **DEC-093** — `pi-run-status/1` → `pi-run-status/2` in the result example and
  in the sentence naming the status record (QUE-007 item 4); plus the
  `switch`/`toolUse`/`deferred` ↔ `status.state` relationship from F-16 item 5,
  and `final`'s definition if F-16 item 6 is settled rather than left.
- **SPEC-001 REQ-004** — the design's own reconcile clause (§4) carries three
  weaker properties together: ceilings are retrospective with a bounded
  overshoot rather than admission control; accounting covers this run's own
  provider sends only (nested `pi`, a direct gateway call, tool-result-only
  spend, and extension-mediated summarization are outside it); and the per-run
  gateway token that would bound the rest is IDE-015, not this accumulator.
  REQ-004 is `pending`; this REV records what is true rather than promoting it.
- **ADR-017 §3 authority ledger** — the five `pi-mcp` rows (request schema
  validation 1b, profile→tool allowlist 2b, delegate audit 4c, delegate ceilings
  5c as retrospective accounting with best-effort termination, delegate kill
  switch 6c as admission refusal *and* active halt) and one `satan-flake` row for
  the execution profiles (3c), per design §7 "Authority" and DEC-091.
- **SPEC-002 REQ-016** — the two per-call forms are the declared profile for a
  jail that holds model output, but AC1/AC2 ("test-asserted, no protocol
  bypass") are only satisfied once the bind-set check has actually run. Record
  REQ-016 as **pending on PHASE-09's operator run**; do not advance it on the
  nix-free half (F-1).
