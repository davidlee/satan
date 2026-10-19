# Review RV-029 — reconciliation of SL-023

Adversarial-review ledger. Structured findings live in the sister
ledger toml; this prose companion carries the reviewer's framing.

## Brief

<!-- Pre-reading + lines of attack: what this review is probing, the invariants
     it must hold the subject to, and where the bodies are likely buried. Seeded
     at `review new`; the reviewer fills it before raising findings. -->

Mode: **conformance** (post-implementation, self-audit; raiser and responder
driven with `--as`). Facet: reconciliation. Target: SL-023, all 18 phases
completed. Surface reviewed: the primary trees as committed — satan `0affb18`,
malebolge `c617c84` (runner code at `8c93902`), flakes `58c908a2`+, emacs
`e6cea06`, corpus; not a dispatch candidate branch (the slice was driven by
capsules in the main trees). Canon: design.md locked rev 63 (run
dr-01a14d77), DEC-050..DEC-065, POL-001, ADR-017 (§1, §3 ledger, §4),
ADR-018 D1/D3/D5 (REV-006), SPEC-001, SPEC-002.

Lines of attack:

1. **Conformance algebra** — `doctrine slice conformance 23`: undeclared code
   paths, the one undelivered selector (the ADR-017 ledger, applied at audit).
2. **Checks** — malebolge `just check` (fmt, lint 0, tsc, vitest + coverage),
   satan `just check`, `just check-jails`, flakes `jailed-agents` check,
   `doctrine check gate`.
3. **Design vs implementation drift** — every section the amended DECs
   (DEC-055 Connection seam, DEC-057 widened gate, DEC-060/061, DEC-065) or
   phase deviations moved: §5.1 module table, §5.2 port and wire, §5.3 DDL and
   event vocabulary and the one-source config claim, §5.4 pause/resume,
   recovery phases, §5.5 assumptions, §7 index, §9 closure evidence and rungs.
4. **User rulings 2026-10-19** against stale canon: closure ran against the
   deployed room (PHASE-14 EX-5), CHR-016 closed except the SL-006-lock
   re-check, closure jobs carry no intervention row (accepted by
   construction), CHR-017 "must land before SL-023 closure".
5. **Invariants I1..I17** held in deployed state: one consumer (I1), no
   `patch_jobs` in `satan_memory`, runner socket unjailed (I4), no derived
   door values (I13).
6. **Governance follow-through** (design §10): DEC-062 ledger rows with
   transition lines (INV-3), backlog supersession (ISS-030/038/039/041,
   CHR-003, IDE-007; IMP-006), DEC-064 runner tech spec at reconcile, SPEC-002
   container list, SPEC-003 OQ-3.
7. **Implementer open items** from notes.md (PHASE-02..18) — each a candidate,
   verified against code before it is raised.

## Synthesis

**Closure story.** SL-023 replaced two non-working `patch_jobs` consumers (the
elisp runner and the Go satan-patcher) with one TypeScript runner in
`~/dev/malebolge` hosting a pi-durable harness on the host, its tools in the
oubliette room `assistant` through pi-env, work returned only as git collected
into a host quarantine, and promotion enacted from Emacs. It is deployed and
was exercised end to end: two PHASE-12 smokes (one through a room stop and
resume) and the closure pair — P promoted to `satan/patch/<P>` at its
`reviewed_oid`, R rejected — with exactly one consumer verified in deployed
state (satan-patcher unit absent, Go repo archived, `patch_jobs` dropped).
Checks at audit: malebolge vitest 47 files / 1206 tests, coverage
97.81/93.91/98.2/97.96, tsc clean, eslint 0 over the committed tree (the
recipe's `just check` fails only on another agent's untracked
`.pi/extensions/`); satan `just check` 1303/1307 (4 env skips); `doctrine check
gate` rc 0; `just check-jails` rc 0; flakes `jailed-agents` rc 0.

**What the audit found.** No blocker. The code matches the amended decisions;
the canon does not. The design (locked rev 63) still describes the
pre-amendment gate and tool wrapping, an `audit.ts` module, a port and wire
narrower than built, a DDL without `ceilings`, a pause trigger the
implementation had to split and back with a gate refusal, a startup-only phase
A, and above all a slot as the live rung — overtaken by the user's ruling that
the closure run against the deployed room is the evidence, and by oubliette
SL-006 shipping. The SL-006-lock re-check (CHR-016's remainder) is done here:
the adapter matches the locked sec-4/5/6. Governance follow-through the design
assigned to closure was owed and is now partly done in this audit: the DEC-062
ledger rows with transition lines (the repo's first authority migration), and
the supersession closures (ISS-030/038/039/041, CHR-003, IDE-007, plus IMP-006
whose extraction this slice performed). DEC-064's runner spec and the SPEC-002
/ SPEC-003 updates remain reconcile's.

**Standing risks.**
- The runner unit executes malebolge's live, dirty working tree (CHR-017,
  which the user ruled must land before closure). A restart deploys whatever
  the tree holds.
- A held job whose repo leaves config wedges the one seat across restarts
  (ISS-047). Low likelihood, total impact.
- Room config values are literals beside a fleet that cannot export them
  (F-8); the preparing `guest_path` check and push oid gate are the backstop.
- Producer lanes other than `fix`/`goad-walk` are refused (ISS-046), so the
  runner serves one lane today.

**Tradeoffs consciously accepted.** No intervention row for jobs created
outside a run (user ruling); one model request may race a `host_key` abort;
zero catalog cost is accepted at load (deployed price verified); the research
baseline stays unstamped; plan criteria stay as written with appended EX-5.

**Housekeeping noticed.** RV-027 (SL-023's rev-63 design pass, recorded as
waived) is still `active · await=raiser` with no findings; reconcile or close
may conclude it with a waiver basis. While opening this ledger the MCP
`review_new` call timed out and a `review_prime` was mis-aimed at RV-028
(SL-024's design ledger); prime only rewrites that ledger's gitignored cache
from SL-024's own selectors.

## Reconciliation Brief

### Per-slice (direct edit)

- **Selector registry (F-1, load-bearing):** `doctrine slice selector add 23
  --intent design-target flake.nix justfile satan/satan-attribute.el
  satan/test/satan-attribute-listener-test.el
  satan/test/satan-memory-migrate-test.el docs/INDEX.md docs/governance.md`;
  bound the delta registry to SL-023's satan commits — `doctrine slice
  record-delta 23 PHASE-11 --commit 83b5362`, `… PHASE-12 --commit f17d33f`,
  `… PHASE-13 --start 87d8cfd^ --end 01dab54` — and stop the code-free phases
  spanning to HEAD. Mirror in design §10 "This repo" (jail check in
  `flake.nix`/`justfile`, attribute comment rewords, migrate test, docs).
- **design.md §5.1 (F-4):** `model-gate.ts` row per amended DEC-057 (nine
  members gated and counted; `cancelDeferred` uncounted pass-through;
  `getAuth`/`login`/`logout` refused); drop `audit.ts` (auditing is
  `store.ts`); list the runner's modules or mark the table principal-only.
- **design.md §5.2 (F-4, F-5, F-12, F-16):** "Tools offered" — registration
  copies, `read` `replay: "safe"`, no `wrapTool`; slot adapter no longer "live
  rung", room adapter no longer provisional (SL-006 done; re-checked RV-029
  F-7); port `collect → {quarantine, ref, oid}`, `reachable(repo, jobId)`,
  `checkClone`/`cleanClone`; `result` adds `jobId`, `state`, `repoPath`;
  summary adds `failure`; refused promotion audited as a `disposition` event;
  Emacs mode enum from `satan-tools-patch-modes`; policy ladder: an unknown
  mode/repo at `preparing` → `failed`, a restart keeps the recorded policy.
- **design.md §5.3 (F-8, F-11, F-16):** DDL gains `ceilings TEXT NOT NULL
  DEFAULT '{}'`; event-kind comment = the store's vocabulary (no `resume` row
  kind: the `waiting_room → running` transition plus a `warning` receipt with
  trigger `resume`); failure/payload reasons as free text with the current
  set; `end_reason = cancelled` also on queued/preparing; runner-config
  paragraph: literals commented with their fleet source (no fleet output
  exists), drift caught by the `preparing` check and push gate.
- **design.md §5.4 (F-9, F-10, F-16):** room-down sequence — `afterTool`
  replaces, `afterTools` signals, the gate refuses `paused` (in-memory signal +
  durable mark; no count, event or latch), `waiting_room` decided from the
  durable row; gate refusal reasons add `paused`, `no_job`, `credentials`;
  classification row for `cancelled` (class as collected, `partial` when
  clean); ceilings: `ceiling_exceeded` before `usage_unavailable`; restart
  recovery — startup phase A room-free, room-touching rows and re-arm in the
  rejoined run before its act, no `resume()` without an in-flight segment,
  row 7 on a disabled start with `reason: recovered`, `stopping` leaves rows as
  a crash does.
- **design.md §5.5 (F-4, F-5, F-10):** assumptions — widened gate, no
  `wrapTool`, no "slot remains the live rung"; I15 reworded to cover the
  rejoin.
- **design.md §6, §7, §8, §9, §10 (F-5, F-8, F-12):** §6 SL-006 lock drift →
  resolved (re-checked at ad2dd7d; sec-5 strict-runner relay absorbed by
  SL-006); deployment-facts line → literals; §7 row "DEC-0NN (proposed)" →
  DEC-065; §8 "Runner config drifts" mitigation → literals + backstops; §9
  live smoke / live room rung rows and Closure evidence → closure ran against
  the deployed room door, PHASE-12 + closure run are the live room rung,
  waived items per ruling (1); §10 corpus row "committed by path"; §10
  governance line → DEC-065.

### Governance/spec (REV)

- **DEC-065 (F-5, F-8):** revision note per user ruling (1) 2026-10-19 — the
  slot is no longer the live rung; live room rung covered by PHASE-12 and the
  closure run; SL-006 re-check done (RV-029 F-7); config values are literals
  until the fleet exposes room data.
- **DEC-055 (F-9):** revision note — pause trigger split (`afterTool`
  replaces, `afterTools` signals) and the gate's `paused` refusal (STOP-1
  ruling 1).
- **DEC-057 (F-9):** revision note — refusal reasons now include `paused`
  (and `no_job`, `credentials`) besides exhaustion and unreadable usage.
- **SPEC (DEC-064, F-25):** author the runner tech spec under SPEC-002 from
  the reconciled design; SPEC-002 container row / diagram / coupling prose /
  transport row / shared-database row / migrator list updated (runner =
  `satan-runner` unit from `~/dev/malebolge`, own SQLite store, NDJSON UDS, no
  `pg_notify`; satan-patcher retired); SPEC-003 OQ-3 resolved.
- **Project governance (F-26):** `.doctrine/governance.md` ADR-017 bullet —
  owners are `emacs-client` except rows 4b/5b/6b/8/9 (`patch-runner`, since
  SL-023). (The ledger itself was edited in this audit, F-3, per DEC-062.)

### Not for reconcile (recorded here so close can check)

- CHR-017 must be resolved (or waived by the user) before `slice status 23
  done` (F-20, user ruling).
- Follow-ups owned elsewhere: CHR-019 (F-21), ISS-047 (F-23); already filed:
  IMP-042, IMP-043, CHR-017, CHR-018, ISS-046.
