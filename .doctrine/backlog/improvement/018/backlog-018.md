# IMP-018: satan-context.el consumes satan-run's layout API instead of re-implementing the bucket walk

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Context

Harvested from [[SL-013]]'s reconciliation audit (RV-003 F-3). SL-013 made
`satan-run.el` the sole owner of run-directory layout (DEC-001, design §5.1) and
gave `satan-context.el` a hard `(require 'satan-run)` (F3, PHASE-02). The module
therefore has the layout API in scope — and still does not use it.

## The duplication

| `satan-context.el` | `satan-run.el` |
|---|---|
| `satan-context--bucket-regexp` (`:252`) | the byte-identical string inside `satan-run--bucket-name-p` (`:118`) |
| `satan-context--list-recent-runs` (`:255-286`) — enumerate `satan-runs-dir`, filter buckets, filter leaves | `satan-run-list-dirs` (`:156-178`) |

This is the **same-body/different-name** duplication class that SL-013's design
§2.1 counts as seven of the tree's eleven instances, and that RV-002 F-2 records
the symbol-keyed census as structurally unable to see. §2.1's census did not
reach `satan-context.el`, so this instance was never counted. It is the twelfth.

## Why it was not fixed in SL-013

Not drift against any authored criterion — no `EX-`/`VT-`/`VA-` names it, and
design F2 set the precedent of leaving `satan-context.el`'s `satan-run-*` surface
alone. And it is **not a mechanical repoint**: `satan-context--list-recent-runs`
is semantically different from `satan-run-list-dirs` —

- newest-first ordering (`sort … #'string>` on buckets *and* leaves) vs. "order
  is unspecified";
- early exit once `N` entries are collected, vs. full enumeration;
- `satan-context--run-id-regexp` captures YYYY/MM/DD/HH/MM/mode/FAILED, where
  `satan-run--legacy-run-name-p` is a bare predicate.

So the collapse needs a design call: either the leaf grows an ordered/limited
variant (and a run-id *parser*, not just a predicate), or context keeps its own
traversal and consumes only the predicates and the leaf-id stripper.

## Sharp edge

Five of the suite's 13 skips are `satan-context/*` corpus-integration tests
(`skip-unless` the `~/notes` corpus). A change here lands least-observed of
anywhere in the module. Whoever takes this should run the context suite with the
corpus present, not just `just check`.

## Related

- [[IMP-017]] — the standing structural check (canonical-body-hash) that would
  have *found* this instance mechanically. This item is evidence for that one's
  value: the class recurred a twelfth time and a symbol-keyed scan missed it.
- [[SL-013]] design §2.1, §5.1; RV-002 F-2; RV-003 F-3.
