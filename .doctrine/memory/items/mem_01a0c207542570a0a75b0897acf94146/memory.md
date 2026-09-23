# Driving a `doctrine design` run: four defects in 0.44.3

Hit while driving SL-016's design run (`dr-01a0c179`) end to end, exploring →
reviewing. All four are in the CLI, not in this repo. Each cost a turn to
diagnose; none has a fix in-tree, so plan around them.

## 1. `explore.research`'s check is unrunnable

Discharging that step runs a check that shells out to a **top-level `doctrine
verify`**, which does not exist:

```
Error: step `explore.research`'s check exited 2, so the step is not discharged:
error: unrecognized subcommand 'verify'
Usage: doctrine [OPTIONS] <COMMAND>
```

The step therefore **cannot be attested**, however completely it is performed.

**Workaround:** discharge `outcome: "skipped"` and put the full substance of
what was actually done in `reason`. Do not let "skipped" read as "not done" —
say so in the first line.

## 2. Runbooks are strict sequences with no useful error ordering

A runbook step refuses if it is not the one at the cursor:

```
Error: step `explore.canon` is not the one at the cursor —
this runbook is a SEQUENCE and expects `explore.research` next
```

**Workaround:** discharge one at a time, re-reading `known_revision` between
each. Batching a loop over all steps wastes the whole batch when one fails.

## 3. `discharge` accepts any `reason`, including a placeholder — and is one-shot

Submitting a step with a throwaway reason to *probe* whether it is gated will
**discharge it**, and re-discharge is then refused:

```
Error: step `review.passes` cannot be discharged:
every step of this runbook is already discharged against its current definition
```

**Workaround:** never probe with a real payload. Probe by attempting the *stage
transition* instead — that refusal lists the outstanding steps without
consuming anything. If a bad reason does land, record the correction in the
nearest subsequent `acceptance.basis`, which sits beside it in the record.

## 4. Two of the four review policies are unsubmittable

`ReviewPolicy` documents four values, and the payload label bound is 16 bytes:

```
Error: payload label term is 22 bytes, over the 16-byte admission bound:
`adversarial-then-human`
```

`adversarial-then-human` and `human-then-adversarial` are both 22 bytes. Only
`human-only` (10) and `adversarial-only` (16) are reachable.

**Workaround:** `adversarial-only` loses little, because `design-accepted`
remains a user act the lock gate requires under every policy — so the effective
shape is still an adversarial pass followed by user sign-off. What is lost is
the user's per-section `section-reviewed` act, not their acceptance.

## 5. `design materialise` orders sections lexically

`sec-10` renders **second**, between `sec-1` and `sec-2`. Sections also cannot
be pruned — `lifecycle` is inert on a `sec-` subject, honoured only for `inq-`
— so minting zero-padded `sec-01..sec-10` (which *are* accepted) leaves the ten
unpadded ones behind as orphans.

**Workaround:** either keep to nine sections, or assign section bodies to
**lexical slots** — reading position *i* goes to `["sec-1","sec-10","sec-2",
"sec-3",…,"sec-9"][i-1]`. The rendered document is then correct and the ids are
slots rather than reading positions. Say so in the drafting-ready basis, or the
next reader will think the numbering is a mistake.

## Two more worth knowing (not defects)

- **Field applicability is subject-keyed and strict.** `body` is honoured only
  for `sec-`; `lifecycle` only for `inq-`; `resolution` only for `fnd-`;
  `dispose` only for `cp-`. An inquiry is **resolved by a checkpoint that
  disposes it** — `{"subject":"cp-N","disposes":"inq-N","dispose":{"form":
  "create",…}}` — not by setting lifecycle on the node.
- **Enums are internally tagged where the contract says so.** `Provenance` is
  `internal("provenance")`, so it is `{"provenance": {"provenance":
  "agent-proposed"}}`, not a bare string. Read `doctrine design contract
  --format prompt` before the first apply; it is the only place this is stated.

## Related

- [[mem.pattern.doctrine.declare-design-targets-at-lock]] — selectors are
  declared at design lock, not at audit. The design run's `draft.selectors`
  step is where that happens, and `doctrine slice selector doctor <ID>` is the
  check worth running before discharging it.
- [[mem.signpost.doctrine.lifecycle-start]] — where the design run sits in the
  slice lifecycle.

## 6. Hand-editing `design.md` blocks `apply` until you re-adopt — format undocumented

Editing `design.md` directly (easier than JSON-escaping whole section bodies)
makes the next `apply` refuse: `design.md has been edited outside this run —
the watermark says … and Doctrine reads <HASH>`. The refusal names the
`adopt_authored` declaration, but neither the contract nor
`design-payload-contract.md` says what its `sections` map holds.

**Verified shape (0.44.3, SL-017, 2026-09-23):**

- `fingerprint` = sha256 of the whole current `design.md` (the `<HASH>` the
  refusal prints).
- `sections` = **every** `sec-N` (a partial map is refused: "N missing"), each
  value = sha256 hex of that section's body, where body = the text after its
  `<!-- doctrine:section sec-N -->\n` marker, `.strip()` + `"\n"`. Raw text or
  the body itself is refused as "mismatched".

The run then logs `section_fingerprint_changed` for the edited sections and
absorbs their bodies. `design materialise` afterwards should produce a
byte-identical file — diff to confirm. Edited sections' attestations go stale,
as with any body change.
