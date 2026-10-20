# Review RV-049 — code-review of SL-028

Adversarial-review ledger. Structured findings live in the sister
ledger toml; this prose companion carries the reviewer's framing.

## Brief

<!-- Pre-reading + lines of attack: what this review is probing, the invariants
     it must hold the subject to, and where the bodies are likely buried. Seeded
     at `review new`; the reviewer fills it before raising findings. -->

## Synthesis

- **Overall**: solid
- **Synopsis**: The unit module is design §4.1 verbatim plus a header in runner.nix's style;
  the built unit matches it, and switch behaviour was proved live (changed unit, same PID).
  Two deviations the design's code-impact table missed, both necessary and both recorded in
  notes § PHASE-06: the profile enable (with a red→green selection test) and the
  `dl-satan.el` `:commands` list, without which VH-1 fails from a fresh Emacs. The second is
  a duplication hazard — the command list now lives in two places (cookies and `:commands`)
  — tolerated: it is the config's existing idiom for `:load-path` packages. One nit (F-1,
  causal misattribution in SATAN.md), fixed. RSK-020 stands, documented.
- **Haiku**: No Install line here — / it sleeps until summoned, / and the switch walks past.
