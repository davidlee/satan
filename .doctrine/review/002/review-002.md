# Review RV-002 — design of SL-013

Adversarial-review ledger (ADR-007). Structured findings live in the sister
ledger toml; this prose companion carries the reviewer's framing.

## Brief

An Inquisition, raised under the posture label `inquisitor`, against the **design
aspect** of SL-013 — the design locked at 2b87023 (`docs(SL-013): design locked
— satan-run.el as sole owner`). Implementation has not begun and no plan exists;
the accused is `design.md` and nothing else. Conformance of code to design is a
separate aspect and is not tried here.

### Doctrine the accused is held to

- **ADR-018 D4.1 + VT-2** — the in-language rehearsal of single-owner discipline,
  and its acceptance test. ADR-018's Consequences record the copy-instead-of-
  extract failure as the thing D4.2 must not repeat.
- **POL-001** — precondition, not an extraction.
- **`slice-013.md`** — scope, non-goals, and the "Verification / closure intent"
  section, which the design may refine but may not silently narrow.
- **The design's own §10 standard**, self-imposed and therefore binding: *"both
  explanations on record are wrong, and the wrongness matters because each
  implies a false safety condition."* A mitigation whose stated mechanism is
  false is charged on the accused's own authority.
- **AR-3 and AR-4's standard**, established by the design's own adversarial pass:
  a phase may not pass its own gate with its work undone, and every accepted
  remediation must be assigned a phase that can run it.

### Lines of interrogation

1. **Do the phase gates bite?** AR-3 corrected P4's exit criterion. Was the same
   scrutiny applied to P1, P2, P3 and P5, or did the pass stop where it started?
2. **Does the lint forbid the collision that actually happened?** The scope
   demands the generic form. The tree's duplication is largely *same body,
   different prefix*. A symbol-keyed check cannot see that.
3. **Is every accepted adversarial remediation owned by a phase and a gate?**
   AR-1 was accepted; F7 does not appear in any phase row.
4. **Are the evidential claims true, or merely load-bearing?** §2.2's docstring
   assertion underwrites R3 and R5; R7's premise underwrites I3; §10's EVD-001
   underwrites the whole phase order.
5. **Do the citations resolve?** Every file:line, every `D`/`F`/`AR`/`OQ`
   cross-reference, every entity id.

### Cross-examination performed

`satan-run.el` read in full; `satan-broker.el` definition census and the cloned
bodies at `:80/119/126/129/153/159/171/176/183/191/202/223/247/270`; the F1/F3/
F4/F5/F6 sites; `justfile`; `dev/satan-test.el`; `bin/` and `tools/` layout.
EVD-001 was **independently reproduced** rather than taken on trust — a fresh
`cl-defstruct` + shadowing `defun` under GNU Emacs 31.0.90 confirms the
`compiler-macro` property survives, the syntactic call returns the frozen slot,
and only `funcall` reaches the defun. That charge does not stand; R1's verdict of
*latent* is sound and the phase order may rest on it.

## Synthesis

### Summary judgement

**This is not heresy. It is a good design with a soft flank.**

The doctrinal core is sound and the Inquisition attacked it in earnest and
failed. `satan-run.el` is the correct owner and DEC-001 argues it from the
constraint that produced the clone rather than from taste. R1 is settled with
evidence, and that evidence was **re-run in this tribunal, not believed** —
EVD-001 reproduces exactly under Emacs 31.0.90. The design corrected ADR-018's
Context and its own R1 rather than quietly inheriting two false mechanisms, and
routed the correction to a REV at reconcile instead of hand-editing an accepted
ADR. The adversarial pass found F7 and prosecuted it. Nine of nine spot-checked
file:line citations land on the nose. Both cited knowledge entities exist and say
what they are said to say. Men have been broken on the wheel for less care than
this, and the Inquisition acknowledges it.

The heresy is not in what the design decided. It is in **what the design's own
standards, applied consistently, would have caught and did not.** Every charge
that stuck is the design failing a test it wrote itself:

- AR-3 established that a phase may not pass its own gate with the work undone.
  It was applied to P4 and to no other phase. **P3 — the phase that performs the
  entire collapse — can report a clean exit with nine of its ten deletions
  still standing** (F-1, blocker).
- AR-4 established that every accepted remediation needs a phase that can run
  it. It was applied to the harness wiring and not to AR-1's own outcome, so
  **D6 is described in three sections and executed by none** (F-3, major).
- D3 argued, correctly, that a narrow VT-2 "would certify a tree still violating
  the principle the lint exists to enforce." That sentence indicts D3's result:
  **the lint flags four of eleven duplications and none of the seven forked
  bodies**, because every fork wears a different prefix (F-2, major).
- §10 declared that a wrong mechanism matters because it implies a false safety
  condition. R7 then rests I3 on "pure path arithmetic" over three functions
  that walk directories and stat files (F-5, minor).
- §2.2's docstring measurement, load-bearing for R3 and R5, is false for four of
  nine items and inverted for one — R5 as written would delete the only
  docstring `satan-run-mint-id` has (F-4, minor).

The pattern is singular and worth naming: **the design's rigour is deep but
narrow-beam.** Wherever it looked it looked hard; it did not sweep. Two
adversarial findings were fixed at the exact site they were found and nowhere
else, and both classes recur one row down in the same table.

### Ordered penance

1. **Amend §5.4's phase table** — discharges F-1 and F-3's structural half, and
   absorbs F-6(c)'s orphan. P3 gains a zero-hit grep over its own deleted set
   (`satan-broker--(mint-run-id|iso-time-format|prepare|tool-ctx)`, both
   `defcustom` sites, `satan-mcp.el:26`, `satan-tools-hippocampus.el:22`,
   `satan-context.el:21-24`, `satan-mcp--session-active`) plus "exactly one
   `cl-defstruct satan-run` in the tree"; P3's objective names **F7** beside F4;
   P2's exit names the surface it characterises. **Verification:** read the
   amended table against the §2.1 duplication census and the §5.2 rename table
   and confirm every symbol in either appears in exactly one phase's gate.
2. **Qualify the lint's reach** (F-2) — §5.2/§9 state single-definition ≠
   single-implementation; the scope's "must not be re-introducible" names the
   class it truly forbids; `backlog new improvement` for the structural
   body-hash check, related to ADR-018 D4.2. **Verification:** the backlog item
   exists and is linked; §9's VT list contains no claim the lint cannot
   discharge.
3. **Correct the evidential record** (F-4, F-5) — §2.2's docstring claim,
   R3's parenthetical, R5's instruction, R7/I3's mechanism, and a sentence in
   §5.3 stating the leaf performs directory enumeration. **Verification:**
   `satan-run-mint-id`'s docstring survives the collapse; `satan-run.el`'s
   require block after P4 is exactly `cl-lib` / `subr-x` / `satan-custom`.
4. **Four one-line citation fixes** (F-6).

Penance 1 is the only one that gates. It must land **before `/plan`**, because
`plan.toml`'s `EX-`/`VT-` ids are immutable once authored and a vacuous exit
criterion becomes the standard the phase is recorded as having met.

### Standing risks

- **The rehearsal proves less than it claims.** After penance 2 the tree is
  clean and the lint is honest, but ADR-018 D4.2 migrates a *data* table whose
  duplication will look exactly like the seven renamed forks — the half this
  lint cannot see. The check that would matter there is the one deferred to
  backlog. This is a conscious deferral, not an oversight, and it is recorded so
  D4.2 cannot inherit false comfort.
- **P3 and P4 run with no standing check.** The lint is deliberately not wired
  until P5 so `just check` never goes red mid-slice (C4). Correct, but it means
  the two phases doing the actual collapse are guarded only by their own exit
  criteria — which is precisely why F-1 is a blocker and not a nit.
- **`satan-run.el` remains untested until P2.** R2 is downgraded on a structural
  identity argument that this tribunal verified and accepts. The argument holds
  only while the clones remain identical; it expires the moment P3 begins.

### Consciously tolerated

- The lint does not detect renamed clones (F-2, route (b)). Tolerated with the
  limitation on the record and a backlog item, not tolerated in silence.
- `:include` inheritance in accessor derivation stays open as OQ-2 — unused in
  this tree, and the design already refuses to answer it with silence.

> **HERESIS URITOR; DOCTRINA MANET**
