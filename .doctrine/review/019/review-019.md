# Review RV-019 — design of SL-020

Adversarial-review ledger (ADR-007). Structured findings live in the sister
ledger toml; this prose companion carries the reviewer's framing.

## Brief

**What this pass probes.** A six-section design for two read-only broker tools
over the user's notes corpus (`notes_read`, `notes_grep`). Self-conducted pass by
the author, before any human section review — so read it as a first attacker, not
as independent assurance. What independence exists comes from the fact that the
sections were written before the attack, and the hostile questions below were not
asked during drafting.

**Invariants the design must hold to.**

- The notes root is the user's and read-only to SATAN (three-roots rule; SL-015
  I3). No write path may exist, and no read may escape the root.
- The mode `:tools` allowlist is the authority for what a model may call; a
  registered-but-disallowed tool must be unreachable, and a
  registered-and-disallowed tool must still not break startup.
- The corpus description files are load-bearing (a missing one signals at
  manifest build *and* at MCP startup), so registration and description must be
  one atomic act.
- No new row in the ADR-017 §3 authority ledger: read-only, no capability.
- The harness tier ladder bounds context spend; an unclassified tool is
  available at every tier.

**Where the bodies are likely buried.**

1. **The refusal taxonomy.** The design states refusals in two places (the §2
   table, the §4 resolver) and they are grouped differently. Either one may be
   incomplete, and the failure modes they hide are misleading diagnostics — a
   *wrong* message costs the model a wrong remedy.
2. **The escape hatch.** Containment is claimed to cover symlinks, `..` and the
   root itself via one truename test. The obvious attack is a path whose
   *requested* extension passes the shape filter while its *resolved* target is
   something else, or vice versa. §4 claims the extension is read off the
   requested name; that claim needs to be the design's stated invariant, not a
   parenthetical.
3. **Silent truncation.** Two caps emit flags the design names (`:truncated`),
   and at least one rg flag truncates without a flag of its own
   (`--max-columns`). A design that says "capped honestly" must not leave a
   silent one.
4. **The coupling web.** §5 draws three registries and two doc mirrors. The
   attack is a fourth that was missed — the test fixtures that mirror the
   `morning` manifest, or a surface where the tool name appears.
5. **Cost.** `:chars`/`:truncated` bound one read; nothing bounds a *sequence* of
   reads except the tier ladder, which is the thing CON-001 was created about.

**Not in scope for this pass.** Implementation correctness (no code exists yet);
the `docs_*` rename; pagination (QUE-002, knowingly deferred).

## Synthesis

**Judgement.** Heresy found, and of the load-bearing kind: the design was
**wrong about its own mechanism**, twice, and the wrongness sat exactly where the
consequences are worst.

Seventeen findings were raised in two passes — four by the author before the
tribunal convened (F-1..F-4), thirteen by an independent Inquisitor on a fresh
context (F-5..F-17). All seventeen were disposed `fix-now` and verified. No
finding was a `blocker`; five were `major`, and the five majors were all the same
species of sin — **a claim in the design that the code or the toolchain
contradicts**:

- **F-6 — the security invariant was false.** §4 asserted that
  `file-in-directory-p` "covers `..`, symlinks and the root itself in one test".
  A directory is inside itself, so it covers the root not at all; and `.` was
  promised to fail as an escape when it fails as hidden material. The Inquisitor
  executed the resolver as printed to prove it. The confinement rule is the
  slice's only security-relevant decision, and its stated mechanism did not
  match its stated outcome.
- **F-9 — and the confinement had no test.** The suite would have passed against
  a resolver with the containment check deleted, provided the handler's
  `file-regular-p` remained. The one check that actually resolves symlinks was
  the one check nothing exercised.
- **F-7 — the honesty claim was false in the other direction.** §3 promised that
  a truncated match would end in rg's ellipsis marker. rg 15.2.0 replaces the
  whole line with `[Omitted long matching line]`; the matching phrase is
  unavailable. Fixed not by documenting the loss but by taking up
  `--max-columns-preview`, verified to keep the phrase and mark the cut.
- **F-8 — a silent false negative.** `--max-count 10` per file with no flag,
  against the design's own "a short answer that says it is short" rule: a note
  with fifteen hits would have returned ten and `:truncated nil`. The flag is
  gone; the total cap, which is flagged, was always sufficient.
- **F-5 — the central safety mechanism could not be implemented as written.**
  `--read-capped` was called with one argument and defined with two. The cap that
  R1 depends on had no path from its defcustom to its use.

Add to that three `major`s of omission and one of framing: **F-10**, the
coupling section sold itself as the complete touch-set while missing three tool
enumerations (the resilience §3 per-tool inventory, the governance File map row,
and the `ruminate` prompt in the very mode the tools were being added to);
**F-11..F-17**, seven smaller taints of the same character — citations drifted off
their lines, a count that was a test count rather than a call-site count, an
example plist the parser cannot produce, a claim of "exactly" where the guarantee
is one-way and rg's ignore rules narrow the search set, a promised refusal string
with no mechanism to produce it, and a byte cap wearing a character's name.

**Penance, ordered.** All discharged before this pass concluded; the design is at
revision 31, materialised.

1. Correct every false claim about mechanism — the containment/root/`.`
   behaviour (F-6), the rg truncation marker (F-7), the fd/rg "one rule"
   overstatement (F-15) — so the design describes what the code will do.
2. Restore the missing wiring and the missing flags (F-5, F-8, F-16, F-17): the
   cap passed at the call site; no per-file cap; `:bytes`/`:total-bytes` named for
   their unit; an explicit program-resolution step so `not found on PATH` is
   producible.
3. Make the door and the search set one source (F-13), and state the guarantee in
   the direction it holds (F-14) — with DEC-033 amended in place, since a durable
   claim belongs in the record that owns it.
4. Complete the coupling inventory (F-10) and take the `ruminate` prompt into
   scope: adding tools to a mode whose own instruction does not name them leaves
   the capability unusable, which is the gap this slice exists to close.
5. **Verification the penance requires:** a symlink-escaping-the-root test
   (F-9), a root-absent test (F-6), a 15-hits-in-one-file test (F-8), a
   globs-derived-from-the-defconst assertion (F-13), and an rg-absent test (F-17).
   The §6 table now carries all of them; without F-9 in particular the trial
   would not have been worth holding.

**Standing risks (tolerated, with reasons).**

- The DEC-032 equivalence sentences and the `--max-columns-preview` marker are
  settled by prose and review, not by a test — the suite stubs `call-process`, and
  testing prose pins wording nobody can then improve (R5).
- rg's ignore rules make the search set a strict subset of the openable set. Kept,
  because it is the same filter `notes_recent` applies; now disclosed in the
  contract and the description rather than implied away by the word "exactly".
- QUE-002 (pagination) stands open by the user's own instruction.

**Taint consciously not pursued.** The dead `/satan/notes` ro-bind
(`flake.nix:145`) is left in place: the tools run broker-side and never read it,
and removing a bind that costs nothing is a separate cleanup with its own blast
radius. Recorded here so it is a decision rather than an oversight.

**Word to the implementer.** The design now says what the code will do, and the
tests it names are the minimal set that would have caught these heresies. Do not
simplify the resolver back to a string check, and do not delete the containment
test: it is the only thing standing between a model-supplied path and the rest of
the user's home.

> **HERESIS URITA SUNT; DOCTRINA MANET.**
