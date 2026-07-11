// drive-slice.js — the `/drive-slice` unjail workflow driver (SL-206 PHASE-14).
//
// A Claude Code dynamic Workflow script. It holds NO MCP and runs NO git: it is
// the SPAWN AUTHORITY + per-phase STATE BUS (design §5.1/§5.4, 2a-a). Every
// doctrine read/write happens inside an agent it spawns; the script only threads
// facts { base_B, worker_fork, fork_tip } between the alternating agents, never
// computes them. Orchestrators (O) and workers (W) alternate: each interior O
// DISPOSES the previous W's commit AND PREPS the next W in ONE agent, and the
// script — never a nested O — spawns each W (wall #1: the workflow is spawn
// authority; the orchestrator role carries no `Agent` tool).
//
// Contract-as-code: this realizes the near-complete reference in design.md §5.4
// ("Driver loop (JS, /drive-slice)"). Deviate only where the reference is
// literally incomplete (prompt bodies, schema literals). Never auto-merges — the
// driver drives + reports; landing the fork stays /audit → /reconcile → /close
// (IMP-174). The closing divergence read is advisory, NEVER gated (§5.5).

// F1 harness contract: `meta` MUST be a pure literal (no vars/calls/spreads/
// interpolation) and the FIRST statement.
export const meta = {
  name: 'drive-slice',
  description: 'Unjail slice driver: alternating orchestrator/worker two-job loop that disposes each phase and preps the next, with bounded revive and a closing divergence advisory.',
  phases: [
    { title: 'bootstrap', detail: 'Read slice readiness and prep the first worker (read-only probe on the claude arm; unjailed O on the pi arm).' },
    { title: 'drive-loop', detail: 'Per ready phase: spawn the jailed worker, then one orchestrator disposes it (bounded revive on a fixable defect) and preps the next.' },
    { title: 'divergence', detail: 'After the loop, a read-only probe reports .doctrine/** divergence from trunk — advisory, never gated, never merged.' },
  ],
};

// --- Constants (STD-001: single-sourced, rationale in a comment each) ----------
const SEED_PHASE_COST = 45_000;   // RFC-011-observed funnel ceremony cost; the
                                  // adaptive seed used before a real hop is measured.
const SOFT_CEILING    = 120_000;  // Advisory dumb-zone batching hint (§8 R2);
                                  // planning-only, NEVER gated at one-per-phase.
const MAX_FIXUP       = 2;        // Bounded worker-fixup revivals per hop (§5.5);
                                  // exhaustion halts FIXUP_EXHAUSTED.

// --- F2 slice guard (fail-closed) ----------------------------------------------
// `args` may arrive as a JSON string (Workflow footgun). Parse, validate a
// positive integer, throw fail-closed — never let a probe guess a slice.
const slice = Number((typeof args === 'string' ? JSON.parse(args) : (args || {})).slice);
if (!Number.isInteger(slice) || slice < 1) {
  throw new Error(`drive-slice: bad slice ${JSON.stringify(args)}`);
}

// --- HALT vocabulary (F6: named, closed, single-sourced) -----------------------
// The loop branches on halt reasons AS PROTOCOL, so the vocabulary is a closed
// set — the loop references HALT members ONLY, never inline literals (STD-001).
// The `funnel:<reason>` / `coord:<reason>` families are re-exported from the
// Rust closed vocabs (FunnelOutcome::Refused.reason / CoordRefusal) by the
// orchestrator's receipt — forwarded via hop.halt_reason, never minted here.
const HALT = {
  NULL_RECEIPT:        'NULL_RECEIPT',        // an agent returned null / no receipt
  CONCLUDE_INCOMPLETE: 'CONCLUDE_INCOMPLETE', // sheet=completed ∧ boundary missing (retryable funnel fault; repair is O's, on the live tip)
  PHASE_BLOCKED:       'PHASE_BLOCKED',       // ReceiptStatus::Blocked — a real control-flow boundary (F4)
  ANOMALY:             'ANOMALY',             // any other non-Completed status (incl. Unknown — fail-loud, F4)
  VERIFY_RED:          'VERIFY_RED',          // O ran the tests and verify.green === false
  BUDGET_EXHAUSTED:    'BUDGET_EXHAUSTED',    // projected next-hop cost exceeds remaining budget
  FIXUP_EXHAUSTED:     'FIXUP_EXHAUSTED',     // bounded revive loop exceeded MAX_FIXUP without an accepted dispose
  PREP_INCOMPLETE:     'PREP_INCOMPLETE',     // A1 belt: clean dispose, null prep, but next_ready non-empty (silent prep failure)
  RECEIPT_AMBIGUOUS:   'RECEIPT_AMBIGUOUS',   // a hop carried BOTH fixup and prep — exclusivity the schema can't encode (top-level oneOf is API-forbidden)
};

// --- Schemas (harness `schema:` on each agent() call) --------------------------
// The worker's committed fork tip (claude arm, (B) self-commit) or null (pi /
// fallback (A) — the disposing orchestrator reads the worktree diff instead).
const WorkReceipt = {
  type: 'object',
  properties: {
    fork_tip: { type: ['string', 'null'], description: 'committed fork tip (B), or null for pi/(A) worktree-diff import' },
    summary:  { type: 'string' },
  },
  required: ['fork_tip', 'summary'],
};

// The read-only divergence advisory (§5.5). Computed by the probe over
// git diff --name-only <trunk_ref>..<dispatch_tip> -- .doctrine/** — trunk_ref
// resolved from the existing trunk authority, recorded in compared_ref so the
// signal is not repo-local folklore. Never gated, never acted on.
const DivergenceReceipt = {
  type: 'object',
  properties: {
    diverged:      { type: 'boolean' },
    compared_ref:  { type: 'string' },
    drifted_paths: { type: 'array', items: { type: 'string' } },
  },
  required: ['diverged', 'compared_ref'],
};

// HopReceipt — the between-workers orchestrator's COMBINED receipt: the dispose
// half (§5.2 PhaseReceiptCore + verify + halt_reason?) plus a fixup? XOR prep?
// half, plus the slice-global next_ready adjunct. The dispose half is ABSENT on
// the bootstrap O₀ (prep-only), so the core fields are not globally `required`;
// they are present on interior hops. fixup/prep exclusivity is enforced by a JS
// guard on each returned hop (NOT a schema oneOf — the Anthropic tool input_schema
// contract forbids a top-level oneOf/allOf/anyOf, so the union cannot ride the
// schema; a receipt carrying both halts as RECEIPT_AMBIGUOUS rather than the loop
// silently taking `fixup` and dropping a live `prep`; §5.4).
const HopReceipt = {
  type: 'object',
  properties: {
    // dispose half (PhaseReceiptCore) — present on interior hops
    slice:          { type: 'number' },
    phase:          { type: 'string' },  // PHASE-NN (immutable id)
    receipt_status: { type: 'string', enum: ['NotStarted', 'InProgress', 'Blocked', 'Completed', 'ConcludeIncomplete', 'Unknown'] },
    runtime_status: { type: ['string', 'null'], description: 'advisory, sheet-derived, nullable' },
    dispatch_tip:   { type: 'string', description: 'dispatch branch HEAD (NOT a code oid)' },
    boundary: {
      type: ['object', 'null'],
      properties: { code_start: { type: 'string' }, code_end: { type: 'string' } },
    },
    verify: {
      type: 'object',
      properties: { green: { type: 'boolean' }, failures: { type: 'array', items: { type: 'string' } } },
      required: ['green', 'failures'],
    },
    halt_reason: { type: 'string', description: 'set on any stop, incl. forwarded funnel:/coord: reasons' },
    // fixup half — a fixable worker delta → revive on fork (mutually exclusive with prep)
    fixup: {
      type: 'object',
      properties: { reason: { type: 'string' }, instructions: { type: 'string' } },
      required: ['reason', 'instructions'],
    },
    // prep half — the next worker's context (mutually exclusive with fixup)
    prep: {
      type: 'object',
      properties: {
        phase:         { type: 'string' },
        arm:           { type: 'string', enum: ['claude', 'pi'] },
        base_B:        { type: 'string' },
        worker_prompt: { type: 'string' },
        worker_fork:   { type: ['string', 'null'] },
      },
      required: ['phase', 'arm', 'base_B', 'worker_prompt'],
    },
    // slice-global adjunct (dispatch_next_ready) — load-bearing for the A1 belt
    next_ready: { type: 'array', items: { type: 'string' } },
  },
  required: ['next_ready'],
  // fixup XOR prep XOR neither-when-halted. The Anthropic tool input_schema contract
  // forbids a top-level oneOf/allOf/anyOf, so this exclusivity CANNOT ride the schema
  // (a top-level oneOf 400s at agent creation). It is enforced in JS on each returned
  // hop — a receipt carrying BOTH halts as HALT.RECEIPT_AMBIGUOUS rather than the loop
  // silently taking `fixup` and dropping a live `prep`.
};

// --- Arm detection -------------------------------------------------------------
// Drive-level arm: 'claude' (v1, workflow self-spawns + worker self-commits) or
// 'pi' (the prior O `git worktree add`s + subprocess-spawns the worker; the
// worker cannot self-commit under a ro linked .git, so fork_tip is null).
function driveArm(a) {
  const parsed = typeof a === 'string' ? JSON.parse(a) : (a || {});
  return parsed.arm === 'pi' ? 'pi' : 'claude';
}

const arm = driveArm(args);
// The bootstrap O₀ is PREP-ONLY (no previous worker to dispose). On the claude
// arm that makes it READ-ONLY ⇒ the unprivileged, un-nominated dispatch-probe
// role (least-privilege). Only the pi arm's O₀ needs unjail, because it
// `git worktree add`s the first worker's tree.
const bootstrapType = arm === 'pi' ? 'dispatch-orchestrator' : 'dispatch-probe';

// --- Prompt builders (real driver prompts) -------------------------------------

// O₀ / bootstrap: read readiness + PREP the first worker. No dispose half.
function bootstrapPrompt(sliceId) {
  return [
    `You are the BOOTSTRAP planner for /drive-slice on slice ${sliceId}.`,
    `This is PREP-ONLY: there is no previous worker to dispose.`,
    ``,
    `1. Call dispatch_next_ready{slice:${sliceId}} for the slice-global ready set,`,
    `   and dispatch_phase_receipt{slice:${sliceId}, phase:<first ready>} to confirm`,
    `   the first ready phase has not already landed a boundary row.`,
    `2. If the coord tree cannot be resolved (unknown-slice|ambiguous|stale), return`,
    `   a HopReceipt with halt_reason "coord:<reason>" and next_ready — nothing else.`,
    `3. Otherwise PREP the first ready worker: emit a HopReceipt whose \`prep\` carries`,
    `   { phase, arm:"${arm}", base_B (the fork base OID the worker must sit on),`,
    `   worker_prompt (a tight, self-contained phase brief that EMBEDS a base-guard`,
    `   reminder — clean tree, HEAD==base_B, one non-merge commit via worker_commit),`,
    `   worker_fork (pi arm only: the branch you git-worktree-added; else null) }.`,
    `   Include next_ready. Do NOT emit a dispose half and do NOT emit \`fixup\`.`,
    `If no phase is ready, return prep:null with the (empty) next_ready — the driver`,
    `treats an empty next_ready + null prep as a genuine drive-complete.`,
  ].join('\n');
}

// Interior O_i: DISPOSE the just-run worker, then (iff accepted) PREP the next.
function hopPrompt(sliceId, phase, prep, forkTip) {
  const tip = forkTip == null ? 'null (import the worker WORKTREE DIFF — (A) path)' : forkTip;
  return [
    `You are an interior ORCHESTRATOR (nominated-unjailed) for /drive-slice on`,
    `slice ${sliceId}, phase ${phase}. You have TWO jobs in THIS one agent:`,
    `DISPOSE the just-run worker, then — iff its delta is accepted — PREP the next.`,
    ``,
    `Address the coordination tree EXPLICITLY: git -C .dispatch/SL-${sliceId} ... .`,
    `FIRST assert that tree exists AND is checked out on branch dispatch/${sliceId};`,
    `if not, STOP and return a HopReceipt with halt_reason "coord:<reason>" (this is`,
    `now a correctness precondition, not a confinement one).`,
    ``,
    `DISPOSE ${phase}:`,
    `  - Worker fork_tip: ${tip}.`,
    `  - Import the worker delta (dispatch_import) — from fork_tip under (B), or the`,
    `    worktree diff under (A). On the (A) path, VERIFY the revive commit's parent`,
    `    chain descends from the prepped fork before import; on a mismatch return`,
    `    halt_reason "coord:revive-wrong-base".`,
    `  - RUN the phase tests and record verify:{green, failures[]}.`,
    `  - If the delta is FIXABLE (verify-red-but-addressable, incomplete edit), return`,
    `    \`fixup\`:{reason, instructions} and NO \`prep\` — the driver will revive the`,
    `    worker on its fork. Do this ONLY for a repairable defect.`,
    `  - Otherwise conclude the phase (dispatch_conclude_phase) against the CURRENT`,
    `    live dispatch_tip and reap the fork (dispatch_reap). Map any funnel refusal`,
    `    to halt_reason "funnel:<reason>" — never auto-merge, never blind-retry.`,
    `  - Emit the dispose half: PhaseReceiptCore { slice, phase, receipt_status,`,
    `    runtime_status?, dispatch_tip, boundary? } + verify + halt_reason?.`,
    ``,
    `PREP the next worker (only iff dispose was accepted, i.e. no fixup and no halt):`,
    `  - Consult dispatch_next_ready{slice:${sliceId}} and emit \`prep\`:{ phase,`,
    `    arm:"${arm}" (the drive arm — PINNED; do NOT choose your own, or the driver`,
    `    spawns the wrong worker path), base_B (the CURRENT coord tip after this`,
    `    phase's conclude — NOT the old base), worker_prompt (EMBED the base-guard`,
    `    reminder; for arm "claude" the worker SELF-COMMITS its delta via worker_commit`,
    `    (B) — for "pi" it leaves the worktree diff for import), worker_fork } for the`,
    `    next ready phase. If NO phase is ready, return prep:null.`,
    `  - On a HARD prep failure (distill error, pi git-worktree-add failure) set`,
    `    halt_reason ("coord:"/"funnel:") rather than a silent null.`,
    ``,
    `Always include next_ready. \`fixup\` and \`prep\` are MUTUALLY EXCLUSIVE — emit at`,
    `most one (the driver enforces it: a hop with both halts RECEIPT_AMBIGUOUS).`,
  ].join('\n');
}

// Revive-on-fork: a fresh worker resuming from the committed fork_tip + O's notes.
function fixupPrompt(prep, fixup) {
  return [
    `You are a REVIVE worker for phase ${prep.phase} on the /drive-slice fork.`,
    `Your prior live reasoning is GONE — you resume from the committed fork tip,`,
    `which is fork-durable, not context-intact.`,
    ``,
    `BASE GUARD (enforced, not hoped): your worktree's base is re-stamped to the`,
    `prior fork tip; worker_commit refuses unless HEAD==base and the new commit's`,
    `single parent == base, so a wrong-base revive is MECHANICALLY rejected before`,
    `any tip moves. Do NOT git reset to "fix" the base — the base check is the`,
    `guarantee, not a prompt-obeyed reset. Clean tree, ONE non-merge commit.`,
    ``,
    `The orchestrator flagged this defect:`,
    `  reason:       ${fixup.reason}`,
    `  instructions: ${fixup.instructions}`,
    ``,
    `Apply the fix within your original declared file set, re-run the fast check,`,
    `then commit via worker_commit and return a WorkReceipt { fork_tip, summary }.`,
  ].join('\n');
}

// Closing divergence probe prompt — read-only, advisory.
function divergencePrompt(sliceId) {
  return [
    `You are the CLOSING divergence probe for /drive-slice on slice ${sliceId}.`,
    `Call dispatch_authored_divergence{slice:${sliceId}} and return its`,
    `DivergenceReceipt { diverged, compared_ref, drifted_paths? } VERBATIM.`,
    `This is a fact to REPORT, never a conflict to resolve: do not merge, do not`,
    `write, do not land anything. compared_ref names the trunk ref the diff used.`,
  ].join('\n');
}

// Divergence probe (read-only, dispatch-probe role) — appended, NEVER gated.
async function divergenceProbe(sliceId) {
  return await agent(divergencePrompt(sliceId), {
    schema: DivergenceReceipt,
    agentType: 'dispatch-probe',
  });
}

// --- Driver body (top-level; F1 permits top-level await) -----------------------

let lastActual = null;
const report = { phases: [], halted: null, divergence: null };

// Bootstrap O₀: read next_ready + PREP the first worker. Read-only on the claude
// arm (dispatch-probe), unjailed on the pi arm (dispatch-orchestrator).
let hop = await agent(bootstrapPrompt(slice), { schema: HopReceipt, agentType: bootstrapType });
if (!hop || hop.halt_reason) {
  report.halted = { reason: hop?.halt_reason ?? HALT.NULL_RECEIPT };
  return report;
}
// Bootstrap O₀ is prep-only — a fixup half here is malformed (nothing to dispose).
if (hop.fixup) { report.halted = { reason: HALT.RECEIPT_AMBIGUOUS }; return report; }

while (hop.prep) {                                   // prep present ⇒ a phase is ready to run
  const prep = hop.prep, phase = prep.phase;

  // Budget guard: stop before a hop we cannot afford. Unmetered when total is
  // null (budget.total && short-circuits). Adaptive: projected cost is the last
  // measured hop, seeded by SEED_PHASE_COST before the first measurement.
  if (budget.total && budget.remaining() < (lastActual ?? SEED_PHASE_COST)) {
    report.halted = { reason: HALT.BUDGET_EXHAUSTED, phase };
    break;
  }
  const before = budget.spent();

  // W_i (JAILED). claude arm: the workflow spawns the worker, which self-commits
  // (B) and reports its fork_tip. pi arm: the prior O already git-worktree-added
  // + spawned it, so skip this agent() and thread fork_tip = null (import (A)).
  let work = prep.arm === 'claude'
    ? await agent(prep.worker_prompt, { schema: WorkReceipt, isolation: 'worktree', agentType: 'dispatch-worker' })
    : { fork_tip: null };

  // O_i — ONE orchestrator, TWO jobs: dispose W_i then (iff accepted) prep W_{i+1}.
  // Bounded fixup loop: a fixable defect revives W_i on its fork and re-disposes;
  // no prep happens until the dispose is accepted.
  let fixups = 0;
  for (;;) {
    hop = await agent(hopPrompt(slice, phase, prep, work.fork_tip), { schema: HopReceipt, agentType: 'dispatch-orchestrator' });
    if (!hop) { hop = { halt_reason: HALT.NULL_RECEIPT, prep: null }; break; }
    // fixup XOR prep — the exclusivity the schema can't encode (top-level oneOf is
    // API-forbidden). A hop carrying BOTH is ambiguous: halt loud rather than let the
    // next line silently take fixup and drop a live prep.
    if (hop.fixup && hop.prep) { hop = { halt_reason: HALT.RECEIPT_AMBIGUOUS, prep: null }; break; }
    if (!hop.fixup) break;                           // disposed: accepted (may carry prep) or halted
    if (++fixups > MAX_FIXUP) { hop = { halt_reason: HALT.FIXUP_EXHAUSTED, prep: null }; break; }
    // Revive-on-fork (§5.5): a FRESH worker on the SAME fork (delta durable under
    // (B)) carrying O's fixup notes. NOT a context-intact SendMessage — fork-durable.
    // "Same fork" is enforced by worker_commit's base check, not by prompt obedience.
    work = await agent(fixupPrompt(prep, hop.fixup), { schema: WorkReceipt, isolation: 'worktree', agentType: 'dispatch-worker' });
  }

  lastActual = budget.spent() - before;              // adaptive (whole hop, incl. worker + fixups)
  report.phases.push({ phase, ...hop });
  log(`phase ${phase}: ${lastActual / 1000 | 0}k${fixups ? ` (${fixups} fixup)` : ''}`);

  // Halt on the DISPOSE half — named, single-sourced (F6). Forwarded funnel:/
  // coord:/FIXUP_/NULL_ reasons ride hop.halt_reason (F3).
  if (hop.halt_reason)                                { report.halted = { reason: hop.halt_reason, phase }; break; }
  if (hop.receipt_status === 'ConcludeIncomplete')   { report.halted = { reason: HALT.CONCLUDE_INCOMPLETE, phase }; break; }
  if (hop.receipt_status === 'Blocked')              { report.halted = { reason: HALT.PHASE_BLOCKED, phase }; break; } // (F4)
  if (hop.receipt_status !== 'Completed')            { report.halted = { reason: `${HALT.ANOMALY}:${hop.receipt_status}`, phase }; break; } // Unknown (F4)
  if (!hop.verify.green)                              { report.halted = { reason: HALT.VERIFY_RED, phase }; break; }

  // A1 belt — hop.prep is OVERLOADED (drive-complete vs prep-failed vs prep-skipped).
  // A clean dispose that then FAILS to prep also returns prep:null; treating null as
  // done would report a truncated drive as complete (violates F3 — success must not
  // be an omission). A null prep with a NON-EMPTY next_ready is an anomaly, not
  // completion. (The disposing O SHOULD also set halt_reason on a hard prep failure;
  // this cross-check catches a SILENT omission the receipt didn't name.)
  if (!hop.prep && hop.next_ready && hop.next_ready.length) {
    report.halted = { reason: HALT.PREP_INCOMPLETE, phase };
    break;
  }
  // Accepted ⇒ loop on hop.prep; null prep ∧ empty next_ready ⇒ drive genuinely done.
}

// Closing advisory — read-only, appended, NEVER gated, never acted on (§5.5).
report.divergence = await divergenceProbe(slice);
return report;
