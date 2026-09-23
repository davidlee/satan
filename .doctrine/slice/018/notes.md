# Notes SL-018: Unattended runs acquire credentials by per-mode policy: probe, then prompt or defer

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## Harvest
<!-- single-copy: updated in place each harvest; ids only, never restated content -->
fresh-as-of: 2026-09-23 · PHASE-01 done (~/.emacs.d 45e346d, 634a878) · status started · next: /phase-plan PHASE-02

### Produced
- SL-018 (this slice); needs SL-017
- ISS-012 — split; now credential-only; service-account token rejected
- DEC-020 (OQ-1), DEC-021 (OQ-2), DEC-022 (OQ-3..OQ-5 + dismissed prompt), DEC-023 (run_busy gate, RV-013 F-3)
- ASM-002 (A1); QUE-001 extended (pre-spawn gates incl. run_busy)
- ISS-020 (sentinel reset) — absorbed into SL-018 (scope objective 8, design sec-6)
- RV-013 — 20 findings over two adversarial passes, concluded
- design.md sec-1..sec-9; 12 design-target selectors

### Learned
- mem.fact.satan.op-prompts-on-session-not-read (new)
- mem.fact.satan.op-read-blocks-emacs-server (rewritten: popup now surfaced)
- mem.fact.satan.op-cache-has-no-invalidation
- design-run mechanics: inquiries resolve via cp- dispose; adopt needs the record to exist in a prior apply; att- attests sections (mem.pattern.doctrine.design-run-defects)
- codex MCP down; `codex exec -s read-only -o FILE -` works for adversarial passes

### Open
- ASM-002: held; watched, not validated. Design sec-9 VH-1 corrected at /plan; armed as a watch in PHASE-08
- RV-013 F-9 (DST skew) and F-12 (Pi key superset) tolerated
- DEC-023 consequence: a queued daily mode can lose its day to run_busy
- two-repo rollout: dl-secret.el first (design sec-9)

## Progress

### PHASE-01 — dl-secret backend (~/.emacs.d 45e346d, changelog 634a878)

- `my/op-session-p` (`op whoami`, exit 0) and `my/satan-credential` (pcase over
  lookup / session-p / read / forget) in `lisp/dl-secret.el`; `init.el` sets
  `satan-credential-function`. Inert until PHASE-05.
- EX-5 evidence: `~/.emacs.d` `just check` → `Ran 8 tests, 8 results as
  expected` (baseline before the phase: 0 tests). VT-25 / VT-26 live in
  `lisp/test/dl-secret-test.el`; a stub `op` script logs argv, so no test calls
  the real `op`.
- Found and fixed: `dev/dl-test.el` ran under `emacs -Q` without
  `load-prefer-newer`, so a stale gitignored `lisp/dl-secret.elc` shadowed the
  edited source and the new tests saw `void-function`. The live Emacs is
  unaffected (dl-core sets it). The runner now sets it.
- `my/op-session-p` lets a missing `op` binary signal: a config fault stays
  loud, and SATAN's boundary (design sec-2) records it as `:unavailable`.
