# REV REV-009 — reconcile SL-025

Revision — a pending revise-intent against authored governance/spec
truth. The structured `[[change]]` payload lives in the sister `revision-NNN.toml`;
this prose companion carries the rationale and the free-text before/after excerpts
for prose-body section edits.

## Rationale

<!-- Why this revision: what authored truth needs to change and why, the scope of
     the staged delta, and (for ADR/POL/STD/prose rows) the before/after excerpts
     the structured payload only labels. Seeded at `revision new`. -->

The SL-025 audit (RV-032 F-8) found SPEC-004 and the ADR-017 authority ledger
silent on mode scope, which SL-025 built and deployed (DEC-068, DEC-069). Design
§7 deferred this to SL-025 reconcile, after SL-023's REV-007 (done). No new
decision: each change restates what SL-025 decided and built. User approved the
before/after text in session on 2026-10-19 ("approve").

## Reconcile narrative

- [RV-032 F-8, DEC-068, DEC-069] **SPEC-004 § Job contract**: a paragraph after
  the repo/baseRef/policy paragraph. `mode` is client-stamped from the acting
  run mode, never a model argument. Each mode requires `repos` and
  `allowed_paths` (a list or `"*"`). Submit refuses out-of-scope repos or paths
  `invalid_request`, naming what the mode allows, before the repo lookup.
  Admission is the scope snapshot. Scope is outside the policy ladder.
- [RV-032 F-8, DEC-068] **ADR-017 authority ledger row 1** (*Enforced at*):
  `patch_job_create`'s mode is stamped from the tool ctx (`satan-tools-patch.el`),
  not schema-validated model input. Owner unchanged (`emacs-client`).
- [RV-032 F-8, DEC-069] **ADR-017 authority ledger row 9** (*Enforced at*): the
  submit clause adds mode scope, `withinModeScope` (`protocol.ts`). Owner
  unchanged (`patch-runner`); no ownership-history entry, since no ownership
  moved.
