# Review RV-057 — reconciliation of SL-030

Adversarial-review ledger. Structured findings live in the sister
ledger toml; this prose companion carries the reviewer's framing.

## Brief

Mode: conformance (self-audit). Surface: primary trees — malebolge main
(11af256; slice range 889551d..11af256), satan main (f05cd4b). No dispatch
candidate: phases ran as a pi capsule run in the main malebolge tree.

Lines of attack:
- Path conformance by hand: `slice conformance` reads satan's git only, and every
  design-target selector is in malebolge (precedent RV-050 F-2). Compare
  `git diff --stat 889551d..11af256` with the selectors.
- Delivered behaviour vs design.md (sec-3 connection lifecycle, DEC-104..109,
  sec-4 code impact): pi-research lane A, findings checked on the host.
- Every slice done-criterion and plan EX-/VT- criterion has a test that would
  fail without the feature: pi-research lane B, findings checked on the host.
- Gates at HEAD: malebolge fmt/eslint/tsc/vitest+coverage on the host;
  `doctrine check gate`.
- Carried items: RV-056 tolerated F-4, F-11; ISS-055 (version skew), ISS-056
  (unanswered submissions); the notes' open `_pi/` disappearance.
- Live state: the daemon unit runs from the live tree, so it must post-date
  the last daemon-side commit.

## Synthesis

SL-030 delivers what its design locked. One malebolge daemon now serves many
conversations: each connection binds one conversation through an optional
`attach` first frame, and a legacy first line binds root. Two pi-research lanes
read the code against design.md and the slice and plan criteria (deepseek-flash,
read-only). Both found **no blocker and no behavioural divergence**. The host
re-checked every claim used here.

What the audit found falls into three groups:

- **Verification gaps on Done criteria (F-1, F-2, F-5, F-8).** Two slice Done
  bullets had no test: the passive-client rule (DEC-108), and tools running in
  a created conversation's own `cwd`. V-1's "every refused shape closes and
  creates nothing" was exercised through the daemon for one shape only, and
  one render test was vacuous. All four were repaired by a jailed pi worker
  ($0.07), and the host committed the repairs as malebolge `8fa162c`. Red was
  shown by mutation for the two new behaviour tests. The host gate at `8fa162c`
  is green: biome, eslint, tsc, and vitest at 1765 tests with 98.29 % line
  coverage.
- **Design text that over-states or contradicts correct code (F-3, F-4, F-6,
  F-7, F-9).** F-4 matters most: design sec-3 says "no closing flag is added",
  yet the code's `Connection.ended` is what stops a queued line behind a failed
  attach from binding root. Fixing that sentence keeps a future reader from
  "simplifying" the flag away. All five go to the brief.
- **Process and tooling (F-10, F-11, F-12).** `slice conformance` is blind to
  cross-repo slices, so conformance was done by hand and is clean. malebolge's
  untracked `_pi/` disappeared during the capsule run. The cause is unknown and
  the directory cannot be recovered, so the user is told. The governance
  follow-through the design scheduled for reconcile is in the brief. ISS-055
  now records that PHASE-06's restart hint covers the observed version skew.

Checked and aligned: the ADR-017 §3 authority ledger has no SL-030 row (none
needed). `src/room`, `src/runner` and `test/structure.test.ts` are untouched.
The live `malebolge-room.service` started at 12:20, after the last daemon-side
commit; later commits change only the client, which each attach spawns fresh.
`doctrine check gate` is green.

Standing risks, accepted by the design and unchanged here:
- startup `resume()` fans out unattended (RFC-002 OQ-3);
- non-root conversations keep a stale model (OQ-2);
- concurrency is unbounded;
- the create/acknowledge gap can strand an empty conversation (DEC-108);
- an abort waits behind `beforeInput`.

ISS-056 (an unanswered submission is invisible to the client) is out of scope
and already captured.

## Reconciliation Brief

### Per-slice (direct edit) — `.doctrine/slice/030/design.md`
- F-3, sec-2 Errors table (:73): replace "any line of type `attach` after the
  connection is bound, well-formed or not (the bound check precedes shape
  validation)" with "any line that parses as an `attach` frame after the
  connection is bound, valid or refused". A line that is not JSON or not an
  object falls under "any other bad line".
- F-4, sec-3 "No line after departure" (:106): replace "`destroyed` is the
  only state the check reads; no closing flag is added" with: the check reads
  `destroyed` or the connection's `ended` marker. A failed attach sets
  `ended`; it only ends the socket, so `destroyed` lags until the peer closes.
- F-6, sec-7 V-10 (:247): "each refused one is refused in-process by
  `attachTargetOf` before any connect; `attach-main`'s usage print and exit 2
  are checked by read (sec-6)". Plan PHASE-06 EX-2 is not edited (immutable).
- F-7, sec-6 refused list (:193-195): "`--conversation` not a positive integer
  without leading zeros".
- F-9, sec-7 (:232): "Each module header carries the sec-1 invariants it owns
  (daemon, protocol: 1; conversations: 2–5)".
- Add a sec-7 Verification note: V-16, the passive connection is never bound
  (`test/daemon.test.ts`); V-8's created-conversation tool `cwd`
  (`test/conversations.test.ts`). Both were added at audit (RV-057 F-1, F-2).

### Governance / cross-repo (F-12)
- malebolge RFC-002 (`~/dev/malebolge/.doctrine/rfc/002`), in malebolge's own
  doctrine: update the "where the assumption lives" table and the wire sketch
  to the shipped `attach` / `attached` frames.
- ISS-053 (SPEC-002 transport row), backlog edit: note that the interactive
  socket now carries a creating verb (`attach` with `new`).
- No REV: no accepted ADR, policy or spec in this repo is contradicted.

## Reconciliation Outcome

User agreement: "agreed" (2026-10-21).

### Direct edits applied
- design.md sec-2 error table: bound connection answers `already attached` to any parsed attach frame (F-3).
- design.md sec-3 "No line after departure": the check reads `destroyed` or `ended`; why the marker exists (F-4).
- design.md sec-6 refused list: `--conversation` without leading zeros (F-7).
- design.md sec-7 module headers: each carries the invariants it owns (F-9).
- design.md V-10: refused flags are refused in-process; exit 2 checked by read (F-6).
- design.md V-8 extended (created conversation's tools run in its cwd, F-2); V-16 added (passive connection, F-1).
- The design run is locked; per the CLI, a reconcile edit is direct and not adopted, so `design show` reports design.md ahead of run revision 52 by design.

### Governance / cross-repo (F-12)
- ISS-053: shipped note appended (creating verb live, malebolge 2f84bce).
- malebolge RFC-002: historical note on the assumption table; "Shipped mechanism (SL-030)" bullet in §Wire protocol (malebolge 54b0393). RFC stays open.
- ISS-055: partial-fix note (at audit).
- No REV: no accepted ADR, policy or spec in this repo is contradicted.

### Tolerated
- F-10: cross-repo conformance done by hand (as RV-050 F-2).
- F-11: `_pi/` loss — unrecoverable, unattributed; with the user.

Reconcile pass complete — handoff to /close.
