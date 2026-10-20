# Implementation Plan SL-030: malebolge daemon: many conversations — thread the conversation through the interactive daemon

Prose companion to `plan.toml`. Narrative only — no queried data lives here
(the storage rule); the phase list, criteria, verification, and links are
authored in the TOML. Use this for the plan's rationale and sequencing.
<!-- Reference forms: `lib:reference/glossary.md` § reference forms. -->

## Overview

All code is in `~/dev/malebolge`. The locked design (`design.md`, run
dr-01a15954 rev 42) is the authority; this plan orders its code impact
(sec-7) into eight phases, each ending with `just check` green, and maps its
verification rows V-1..V-15 onto phase VT criteria.

```
PHASE-01 wire frames ──┬──▶ PHASE-02 conversations.ts ──┬──▶ PHASE-03 cwd section
(protocol.ts, render)  │                                 │
                       └─────────────────────────────────┴──▶ PHASE-04 daemon transport ──▶ PHASE-08 mid-bind departure (V-15)
                                                                          │                            │
                                                                          │                            ▼
                                                                          │                  PHASE-05 overlap (V-4)
                                                                          └──▶ PHASE-06 line client ──▶ PHASE-07 docs + gate
```

| V-row | phase |
|---|---|
| V-1 | PHASE-01 (parse), PHASE-04 (daemon: resolution over the wire; refusal closes, creates nothing) |
| V-2, V-3, V-5, V-6, V-11, V-13, V-14 | PHASE-04 |
| V-15 | PHASE-08 |
| V-4 | PHASE-05 |
| V-7, V-8 | PHASE-02 |
| V-9 | PHASE-03 |
| V-10 | PHASE-06 |
| V-12 | every phase's gate; asserted in PHASE-07 |

## Sequencing & Rationale

**Leaves first.** PHASE-01 and PHASE-02 add types and a module with no
caller: pure parsing, then pi calls tested against a real harness. Both are
small, and they let PHASE-04 compose finished parts instead of growing them
inside the rewrite.

**cwd before the daemon.** PHASE-03 needs only `conversations.open({kind:"new"})`
to create a conversation whose prompt it reads (V-9). It is independent of the
transport and isolates a fixture change (`systemPromptSections(test,
conversation)`, root's explicit `cwd`) that touches several test files.

**The transport is one phase; its hardest test is the next.** sec-3's rules —
one splitter and queue, departure as each turn's first step, bind order —
describe one function, so PHASE-04 writes all of it: an intermediate daemon.ts
would satisfy neither lifecycle. Its tests are split instead (RV-052 F-7).
PHASE-04 carries the behaviours a control connection can settle (V-11, V-14
are negatives: "no stream", "nothing created", "nothing submitted" are only
meaningful against a control that did happen). PHASE-08 carries V-15, which
needs a barrier inside the `vi.mock`ed `watchEvents` to hold `watch` open
while the socket goes — new fixture mechanics that deserve their own green
landing. PHASE-04's VA-1 is the implementation-time read of sec-3 against the
rewrite that notes § Design review RV-051 asked for.

**The client bridge rides with the daemon.** Once the daemon withholds the
snapshot until a first line (DEC-108), `test/attach.test.ts`'s "shows the
transcript so far on attach" fails unless the client speaks first. So
PHASE-04 makes `attach.ts` send `{type:"attach"}` on connect — the one-line
seed of PHASE-06 — and updates that file's `serve()` calls and banner
assertions. `render.ts` already renders `attached` (PHASE-01), so the bridge
needs nothing else.

**Overlap is its own phase.** V-4 is the slice's headline behaviour and the
test most likely to expose a defect (shared faux queue, abort scope, stream
isolation). PHASE-05 follows a green PHASE-04 and PHASE-08 so a failure there points at
concurrency, not at the lifecycle.

**Client, then docs.** PHASE-06 completes sec-6 against a daemon that
answers. PHASE-07 updates README and `docs/internals.md` last, when the
behaviour they describe exists, and asserts that `test/structure.test.ts`,
`src/room/` and `src/runner/` are untouched since the slice's base (DEC-105).

## Notes

- Plan review RV-052 round 1 amended the locked design (run rev 44): the
  wire-id key is a type predicate, `isConversationKey`, because malebolge's lint
  forbids type assertions (user's choice, 2026-10-21); `ConversationDefaults`
  makes `cwd` required for `exactOptionalPropertyTypes`; flag parsing moves to
  an exported `attachTargetOf` in `attach.ts`; events before `attached`
  render as they arrive; more README lines are in the docs list. The run must
  be re-locked before PHASE-01 starts (its EN-1).
- inq-7 follow-through is reconcile-time and unphased: malebolge RFC-002's
  table and wire sketch, the ISS-053 note, the ADR-017 §3 ledger confirmed
  untouched at audit (design sec-7).

- VT `test_file` paths are absolute (malebolge is outside this repo;
  SL-023/SL-027/SL-028 convention).
- RV-051 has no routed (demonstrate/probe/control) findings; nothing to
  transcribe.
- The task-owned fixture for V-7 copies pi's own test precedent
  (`~/.local/src/pi/packages/durable/test/harness-conversations.test.ts:378-388`);
  `~/.local/src/pi` is the 1.3.0 source matching malebolge's `node_modules`.
- The faux fixture's root carries a model but no `cwd`; once the cwd section
  reads `agent.cwd`, tests that expect it configure root's `cwd` (PHASE-03 EX-3).
- Strict ordering changes timing for existing tests that send several lines
  (e.g. "does not run beforeInput for abort or compact"): each now waits for
  the previous. Their assertions should hold; a hang there is a PHASE-04
  defect, not a test to relax.
