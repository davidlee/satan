---
name: satan-refactor-T1
description: Split the outcome observer into a thin coordinator + a pure classifier module
metadata:
  type: refactor-theme
  topic: satan-refactor
  status: merged
  blocked_by: []
  updated_at: 2026-05-23
---

# Theme T1 — Split the outcome observer (mechanical refactor)

**Impact:** Med. **Effort:** S. **Risk:** Low. **Reversibility:** Easy.

## Current shape

`satan-observer.el` (`satan/satan-observer.el`, 859 LOC, 33 defuns) spans Broker + Output + State per `review/10-LAYER-MAP.md` and mixes five concerns: defcustoms (`observer.el:45-95`), intervention scanning + dedup (`observer.el:144,791,814,831`), classification (`observer.el:474,569`), persistence (`observer.el:614,666` — three of the codebase's five `memory-store-mark` callers), and broker integration (`observer.el:721`).

## Why it hurts

Attributes adds negative-outcome classification and Shame delta logic; bolted onto the current file they land in 859 LOC of mixed-verb context. Tests live in the test monolith.

## Target shape

Two files. Keep the intervention-scanning helpers in `observer.el` until T7 deletes them; do not relocate-then-delete. Extract only the pure classifier (`classify`, `classify-for-motives`, predicate registry) into a new `satan-observer-classify.el` (~350 LOC). Earlier draft had a three-file split; GPT-5.5 push-back: extracting an "intervention" module whose contents are transcript-scraping conflates two different domain objects (the candidate-from-audit vs. the declared-record). Keep T1 honest.

## Migration sketch

One PR: extract classifier + predicate registry into `observer-classify.el`; observer.el requires it; existing tests in `test/satan-observer-test.el` unchanged.

## Considered and rejected

- Three-way split (observer / intervention / classify) now — conflates pre-T7 candidate-from-transcript with post-T7 declared-record.
- Move classify into `satan-memory-canon.el` because classifiers are pure — wrong layer; entangles memory with observer.
- Honest interim name (`observer-transcript.el`) — helpers get deleted by T7 anyway; no point.

## First concrete step

PR that creates `satan/satan-observer-classify.el`, moves `classify` + `classify-for-motives` + the `--predicates` registry, adds `(require 'satan-observer-classify)` to observer.el. Confirm `test/satan-observer-test.el` is green.

## Open questions

- Does the classifier return pure verdicts and let the coordinator route persistence, or does it know about the persistence path? (Recommendation: former.)

## PR log

- [x] PR 1: extract classifier + predicate registry → `satan-observer-classify.el` — merged 2026-05-23 (observer 859 → 503 LOC, classify 387 LOC, 126/126 tests green, byte-compile clean)
