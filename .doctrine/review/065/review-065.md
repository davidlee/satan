# Review RV-065 — code-review of SL-037

Adversarial-review ledger. Structured findings live in the sister
ledger toml; this prose companion carries the reviewer's framing.

## Brief

Quick pass: a small, test-heavy diff in one subsystem. Mandatory because `satan/test/satan-broker-test.el` falls outside design sec-6. Lines of attack: any path that advances the watermark without `(ok . ID)`; tests that still lean on a real or nil enqueue; new tests that cannot fail; the call-log macro's other caller.

## Synthesis

- **Overall**: solid
- **Synopsis**: `probe-commit` matches design sec-3, and only `(ok . ID)` reaches the watermark write. Every advancing test stubs enqueue through one helper. The new tests were red before the change, and negative controls show the audit and broker tests fail under their target faults. F-1 (docstring overclaim) and F-2 (fixture duplication) were fixed. Three of pi's nits were discarded: `(ok . nil)` and the failure message are design text, and the `(ok . 1)` stub value hides no credible fault. The scope departure, `satan-broker-test.el`, was necessary: its spy returned nil. Standing risk: curiosity and wpm still advance after a failed insert, as the design accepts.
- **Haiku**: The row reached the inbox; / only then the mark moves on. / Failed, it counts again.
