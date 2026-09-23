# Notes SL-018: Unattended runs acquire credentials by per-mode policy: probe, then prompt or defer

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## Harvest
<!-- single-copy: updated in place each harvest; ids only, never restated content -->
fresh-as-of: 2026-09-23 · PHASE-07 in_progress (red tests uncommitted) · head dd26021 · next: PHASE-07 green (see handover.md)

### Produced
- SL-018 (this slice); needs SL-017
- ISS-012 — split; now credential-only; service-account token rejected
- DEC-020 (OQ-1), DEC-021 (OQ-2), DEC-022 (OQ-3..OQ-5 + dismissed prompt), DEC-023 (run_busy gate, RV-013 F-3)
- ASM-002 (A1); QUE-001 extended (pre-spawn gates incl. run_busy)
- ISS-020 (sentinel reset) — absorbed into SL-018 (scope objective 8, design sec-6)
- RV-013 — 20 findings over two adversarial passes, concluded
- design.md sec-1..sec-9; 12 design-target selectors
- plan.toml/plan.md (8 phases; VT-25..VT-29 minted); PHASE-01 in ~/.emacs.d (45e346d, 634a878); PHASE-02..06 (e3faba6, 1a201a6, 6843f76, 723c205, aacf085) + quit fix 67adae4

### Learned
- mem.fact.satan.op-prompts-on-session-not-read (new)
- mem.fact.satan.op-read-blocks-emacs-server (rewritten: popup now surfaced)
- mem.fact.satan.op-cache-has-no-invalidation
- design-run mechanics: inquiries resolve via cp- dispose; adopt needs the record to exist in a prior apply; att- attests sections (mem.pattern.doctrine.design-run-defects)
- codex MCP down; `codex exec -s read-only -o FILE -` works for adversarial passes
- memory candidates (not yet recorded): `quit` is not `error` — acquisition boundaries catch `(error quit)`; ~/.emacs.d `dev/dl-test.el` under `-Q` needed `load-prefer-newer` (stale .elc shadowed source; fixed); `called-interactively-p 'interactive` is nil under --batch

### Open
- ASM-002: held; watched, not validated. Design sec-9 VH-1 corrected at /plan; armed as a watch in PHASE-08
- RV-013 F-9 (DST skew) and F-12 (Pi key superset) tolerated
- DEC-023 consequence: a queued daily mode can lose its day to run_busy
- close at /close: ISS-020 (fixed 1a201a6), ISS-012, IMP-021
- PHASE-05 review F1 (ref in ERR text) rejected with rationale in ## Progress — revisit only if a backend puts secrets in conditions
- pre-existing warning: `satan-run-mint-id` arg `mode-name` shadows a dynamic var (out of scope)

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

### PHASE-02 — satan-credential seam (e3faba6)

- `satan/satan-credential.el`: `--partition` (env → cached / refs / pending /
  failed lookups) is the single core shared by `ready-p`, strict `acquire` and
  lenient `resolve`. `:env` carries only ref-resolved entries; literals already
  ride the base env. `session-p` is consulted only when something is pending,
  so a warm cache makes no `op` call (design R2). `resolve` does not probe the
  session.
- Fake backend: `satan/test/satan-credential-fixture.el`
  (`satan-credential-fixture-with (calls :cache :session :read :signal) …`).
- Hermetic runner: `dev/satan-test.el` binds `satan-credential-function` to
  nil around the whole run (like `satan-announce-sink`), because the live
  Emacs is now wired to 1Password (PHASE-01).
- 16 tests; suite 1102/1108 (6 skipped, the same as baseline). VT-1/11/12 PASS.

### PHASE-03 — run_busy + sentinel reset (1a201a6)

- `run_busy` branch after `session_blocked` (precedence test pins
  perceive_failed > session_blocked > run_busy). Both refusals go through the
  new `satan-broker--write-silent-run` (PHASE-05's `credential_deferred`
  reuses it, adding its journal line). `"run_busy"` is added to
  `satan-broker--streak-transparent-reasons`.
- Sentinel: child-exit record + finalize under `unwind-protect`; the flag reset
  is the unwind form, and the error still propagates. ISS-020's fix has landed:
  close it at slice close.
- **Live effect once Emacs reloads:** a scheduled run that fires while a child
  is live is now refused as `run_busy`, where before it overlapped.
- VT-27's keyword mandate was corrected in plan.toml: its streak half is
  covered by the extended transparent-streak test.
- There is an older byte-compile warning at `satan-broker.el:799`
  (`_probe-snapshots` not left unused, in `--spawn`). Fix it in PHASE-05,
  which rewrites `--spawn`.
- Suite 1105/1111 (6 skipped).

### PHASE-04 — policy, escalation, attended (6843f76)

- `satan-broker--credential-policy MODE &optional NOW` → `(:policy SYM
  :context LABEL)`. The escalated label is `satan broker/NAME (escalated:
  deferred 5h00m)`. The VH-1 watch keys on the absence of "escalated".
- Escalation is due at age **>=** the threshold (so 0 means "escalate after one
  deferral"). The threshold is checked before the streak walk, so a bad value
  always signals.
- `satan-broker--failed-with-p` is the shared status-guarded predicate (N8),
  used by the failure streak and the credential streak.
- `satan-run-id-time` returns nil on a non-matching id; the policy signals.
- Batch caveat: `called-interactively-p 'interactive` is always nil under
  `--batch`, so the attended test stubs it for the positive case.
- `satan-broker-test.el` now requires `satan-run-test` (it used `--mkrun`
  relying only on the runner's load order), plus `satan` and `satan-tick`.
- Existing warning, out of scope: `satan-run-mint-id`'s `mode-name` argument
  shadows a dynamic variable.
- Suite 1115/1121.

### PHASE-05 — broker credential gate (723c205)

- `satan-broker--acquire` wraps direnv, the policy and the seam in one
  `condition-case`. The verdict gains `:base`, the direnv-merged env, which
  `--spawn` uses instead of a second direnv call. A mode with no key var yields
  `(:env nil :refs nil :base BASE)`.
- New cond arms after `budget_denied`: `credential_deferred` goes through
  `satan-broker--write-credential-deferred-run` (silent-run helper plus a
  journal line gated by `satan-failure-syslog`); `credential_unavailable` goes
  through `--write-failed-no-child-run`. `run_busy` now reads
  `(or (null cred) satan-run--spawn-running)`.
- `--spawn` takes a 4th argument, CRED. `credential-refs` is a new run-struct
  slot. The broker keeps no `my/` symbol; `satan-broker--key-var` replaces the
  inline assq.
- **Hermetic floor:** the runner now binds `process-environment` to
  `(satan-credential-scrub process-environment)`. Without it, the existing
  `satan-broker-run "morning"` tests (morning now prompts) would have depended
  on whether the developer's shell held an `op://` ref in
  `OPENROUTER_API_KEY`.
- Test mechanics: the gate helper `satan-broker-test--gate-run` takes
  `:policy :env :backend :attended :setup` and captures announcements through
  the recorder. VT-9 uses a real 1.2 s sleep, because mint-id reads the C
  clock. The `--with-spawn-collaborators` stubs for `my/scrub-op-refs-env` and
  direnv are gone.
- Fixed the older `_probe-snapshots` warning (the variable is used; renamed).
- VT-14 / VT-20 keyword mandates now point at the test names (behaviour is
  tested through `satan-broker-run`).
- Suite 1125/1131.

#### PHASE-05 adversarial review (codex gpt-6-sol, 2 findings)

- **F1 rejected** (raised as a blocker): "the `op://` ref in ERR reaches
  `final.json` / the audit event through `error-message-string`". A ref is a
  vault path, not a secret; `~/.config/zsh/env.zsh` already holds refs in
  plain text. Rendering ERR is the locked design's choice (RV-013 F-4). The
  claim that "a backend error could carry a resolved secret" does not apply:
  `read` signals only when it failed, so it holds no plaintext, and the
  dl-secret message is `op read REF failed (N): STDERR`. Revisit only if a
  backend ever puts secret material into its conditions.
- **F2 accepted** (major): `quit` (C-g while a read blocks) is not an `error`.
  It escaped both acquisition boundaries, so the trigger was lost with no run
  recorded, and a patch job would have been stranded `claimed`. Fixed in
  67adae4: `acquire`, `resolve` and `satan-broker--acquire` catch
  `(error quit)`. The fixture gained `:quit`.

### PHASE-06 — rotation self-heal (aacf085)

- `satan-broker--evict-on-auth` runs in `--finalize` right after the
  crash-context record, before `satan-audit-close`, so `evict-failed` lands
  in the transcript. The announce (inside `--mark-failed-on-disk`) follows.
- `--on-error` marks a run `failed`, so "classified auth plus a final" is a
  failed run and does evict. The `done`-with-slot case is tested directly on
  `--evict-on-auth`.
- VT-29 (recovery): cache `sk-dead` → evict → the next acquire re-reads
  `sk-rotated`.
- Suite 1130/1136 after the quit fix.
