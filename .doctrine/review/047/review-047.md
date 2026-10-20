# Review RV-047 — code-review of SL-028

Adversarial-review ledger. Structured findings live in the sister
ledger toml; this prose companion carries the reviewer's framing.

## Brief

<!-- Pre-reading + lines of attack: what this review is probing, the invariants
     it must hold the subject to, and where the bodies are likely buried. Seeded
     at `review new`; the reviewer fills it before raising findings. -->

Depth: quick pass (~80 lines of nix across five repos, one test file).
Subject: PHASE-05 delta — `~` commit d73eddd5 (`flakes/agents`), plus
uncommitted `flake.nix` in satan, satan-corpus, emacs, notes and
`notes/justfile`. Held to design §4.5 (DEC-088) and DEC-101.

Lines of attack:
- Does every client jail end with `mcp/` read-only, in every launcher, under
  any bind order? (DEC-088's security point, not just its letter.)
- Do the VT-1 asserts fail for the failure modes that matter (file bind,
  writable dir), or only for the exact string chosen?
- Does the notes reorder (DEC-101) hold under the states the host is really
  in: `mcp/` absent at jail launch, later edits to the option list?
- Kept binds (emacs server) and the malebolge strict bind unchanged.
- Consumers' formatting conventions respected (satan-corpus is nixfmt).

## Synthesis

- **Overall**: solid
- **Synopsis**: `satanMcpOptions` matches design §4.5 verbatim. Its test
  asserts the read-only directory bind and refutes both the socket-file bind
  and a writable directory bind. A deliberate `try-readwrite` mutation turned
  it red. The env-forward asserts are not vacuous, because nothing else in
  jailed-agents.nix forwards those variables. All four consumers now take the
  combinator. satan and emacs keep their Emacs server bind, jailed-malebolge
  keeps its strict bind and pre-creates the directory (asserted by
  `malebolge-jail-profile`), and satan-corpus kept its nixfmt style after an
  alejandra slip was caught. VA-1 grep over every launcher of the four flakes
  (override build): 15 mcp-binding launchers clean, notes jailed-pi
  correctly layered. The one finding (F-1) is notes' writable SATAN runtime
  dir. It predates this phase (notes e2965c4) and DEC-101 contains it only
  in the common state. It is owned by IMP-047. Accepted: `/run/user/1000` is
  hard-coded in a shared library, as in the design and in every consumer.
- **Haiku**: A directory, / read-only — but one jail / still holds the
  parent.
