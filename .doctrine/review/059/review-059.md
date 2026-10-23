# Review RV-059 — reconciliation of SL-031

Adversarial-review ledger. Structured findings live in the sister
ledger toml; this prose companion carries the reviewer's framing.

## Brief

<!-- Pre-reading + lines of attack: what this review is probing, the invariants
     it must hold the subject to, and where the bodies are likely buried. Seeded
     at `review new`; the reviewer fills it before raising findings. -->

Self-audit, conformance mode, on the primary tree. satan HEAD is `7f57995` plus
the audit's fix-now delta; quotient is at `3395eab` (`v0.1.1`). SL-031 was not
dispatched, so there is no candidate branch.

Lines of attack:
- **Cutover truth** (design sec-7): after step 7, no live pi-mcp route
  remains, and step 8 pins a published tag and proves it live.
- **Path conformance:** run `slice conformance` over satan's whole SL-031
  range. PHASE-01..08 are quotient-side and produce no satan rows.
- **Deviations against the design and DECs:** the package identity, the
  DEC-118 launcher path, and the PHASE-08 help choices flagged in the harvest.
- **Gate honesty:** `just check`, `just check-jails`, `doctrine check gate`;
  every VT's evidence is either in the gate or recorded in notes.
- **Probe strength:** the hostile-audit weaknesses carried over from SL-029.

## Synthesis

SL-031 delivered its intent. pi-mcp is now quotient
(github.com/davidlee/quotient, npm `@davlee/quotient@0.1.1`). satan consumes
it through a GitHub-tag flake input, and the old in-tree route is gone.

Evidence:
- Live calls through the final `.mcp.json`, after a restart, returned
  `final: true`. So did `codex exec` from satan and from malebolge, on the
  0.1.0 and 0.1.1 builds.
- The scratch root is revoked: a write call there refuses
  `root-not-allowlisted`.
- `npx -y @davlee/quotient help` exits 0.
- Gates: `just check` 0, `just check-jails` 0, `doctrine check gate` 0.
- Over the satan range, conformance has 0 undelivered and no undeclared code
  path once F-4's selector is added.

Divergences. Each is dispositioned, none is a blocker:
- **Identity (F-1, major):** the design named a scope the operator doesn't
  own. The cost was a re-tag (`v0.1.1`); `v0.1.0` stays as an unpublished
  GitHub tag.
  - Lesson: DEC-117's scope-ownership check ran at publish time, when it
    should have run at design time.
- **Launcher path (F-2) and help exit 1 (F-3):** the implementation is right
  and the design text is stale. Both go to reconcile.

Gate gaps:
- **F-6** (fixed): `pi-report-test.sh` ran nowhere automatically. A
  delegate's false "9/9" showed this.
- **F-5** (tolerated): PHASE-04 has no registry row. Its work was
  quotient-only, and a no-op row would lie.

Standing risks:
- The hostile-audit probes are weaker than their guarantees (F-7 → IMP-052).
- The operator now has a global npm `quotient` on PATH beside the nix bin.
  Configs name the nix bin by absolute path, so they're unaffected; a bare
  `quotient` in a shell may resolve to either.
- Codex in malebolge runs unjailed with `cwd` = satan; quotient inside a
  jailed Codex is untested.

Accepted tradeoffs:
- The form family was inlined once its last sibling went.
- `pi-report.sh` no longer guards for node.
- `PI_REDUCE` paths with spaces are unsupported (documented).

## Reconciliation Brief

### Per-slice (direct edit)
- **F-1:** design.md l.8, the package.json sketch (l.491), § Clients (l.528)
  and sec-7 rows 1 and 8: `@davidlee/quotient` → `@davlee/quotient`.
  - First publish is 0.1.1 at tag `v0.1.1`.
  - Step 8 pins `github:davidlee/quotient/v0.1.1`.
  - Note that `v0.1.0` (`6c31180`) is a GitHub-only tag, never published.
- **F-2:** design.md § Clients: replace "(`process.argv[1]`, realpath'd)"
  with: the path the bin was run as, symlinks kept. Under the nix wrapper
  that is `QUOTIENT_LAUNCHER`, its own `$0` made absolute; a relative or
  empty value is ignored.
- **F-3:** design.md CLI table, the `help [section]` row (l.106): "0, 2 for an
  unknown section, 1 when the help layer is unreadable".
- **F-4:** the load-bearing change is already made:
  `doctrine slice selector add --intent design-target 31 'test/flake/*.test.ts'`.
  Mirror it in design.md's selector prose, if that prose lists selectors.

### Governance/spec (REV or knowledge amend)
- **F-1:** DEC-117: package name `@davlee/quotient`. Record that the
  scope-ownership check failed late, and why (`@davidlee` is held by another
  account).
- **F-2:** DEC-118: the snippet path is no longer realpath'd. Record the
  symlink-kept path and `QUOTIENT_LAUNCHER`, and the reason (a store
  realpath bypasses the node wrapper and dies at GC).


## Reconciliation Outcome

The operator confirmed the proposed writes ("proceed with reconcile",
2026-10-23).

### Direct edits applied
- design.md, for F-1:
  - l.8: npm name is `@davlee/quotient`;
  - the package.json sketch: `@davlee/quotient` 0.1.1;
  - l.528, sec-7 diagram S1, row 1 and row 8: `v0.1.1`, and `--version`
    reads 0.1.1;
  - a note under the sec-7 table: `v0.1.0` is GitHub-only, plus why the
    scope moved.
- design.md § Clients, for F-2: snippets name the path the bin was run as,
  with symlinks kept, or `QUOTIENT_LAUNCHER` under the nix wrapper.
- design.md CLI table, the `help` row, for F-3: exit 1 when the help layer is
  unreadable.
- F-4: the registry fix was made during the audit
  (`slice selector add … 'test/flake/*.test.ts'`). design.md lists no
  selectors, so it needs no mirror edit.

### Knowledge amendments (no REV: no ADR, spec, requirement, policy or standard is touched)
- DEC-117: Amendment 2026-10-23, `@davlee/quotient` 0.1.1, and the lesson
  that the scope check came late (F-1).
- DEC-118: Amendment 2026-10-23, the symlink-kept snippet path and
  `QUOTIENT_LAUNCHER`, with the reason (F-2).

### Fixed in audit / tolerated / follow-up
- F-6: fixed (`shell-suite` in `just check`).
- F-5: tolerated (PHASE-04 was quotient-only; see its disposition).
- F-7: follow-up IMP-052.

Reconcile pass complete; handoff to /close.
