
# Extract audit verifier to satan-audit CLI

Extraction candidate under [[POL-001]]. Mechanical port; independently useful.

Modules in scope: `dl-satan-audit.el` — the **verifier half** only. The
append-only writer half stays in the broker because it writes during a live
run.

Fit failure: post-hoc verification over JSON files. Should be runnable from CI,
cron, or a post-mortem shell without booting an emacs-server. Today's only
invocation path is `emacsclient --eval '(dl-satan-audit-verify-run …)'` — the
same live-server-only constraint that shaped `just check`
(`dl-test-run-suite`); see [[mem.fact.satan.test-db-isolation]].

Care: the 6 predicates are the spec — preserve them verbatim. Add a
golden-fixture set covering each predicate's pass/fail cases before the port to
lock semantics.

**Blocked / trigger:** act per POL-001 §Verification (esp. trigger 3 —
reviewer/CI needing to run the verifier without Emacs).
