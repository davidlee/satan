# ISS-001: Evidence truncation cap is never enforced: the pass chain has no final reducer

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

`satan-memory-evidence--truncate` runs a fixed set of exhaustible passes and
stops, whether or not the result fits `budget_hard_cap_bytes`. There is no
final reducer, so an evidence object whose excess lies outside the passes'
reach returns oversized.

## Post-SL-002 inventory (updated 2026-07-22)

SL-002 removed the bough integration, which **narrowed the chain further**:

- **Passes 1, 4 and 5 are gone** — they shrank `bough_day` bodies, `bough_active`
  annotations, and dropped `:bough_recent` entirely. Pass 5 was the "last
  resort", and it was the only pass gated on the cap rather than the target.
- **Passes 2 and 3 survive**: middle-drop of `browser_segments` and
  `focus_segments`. Both are TARGET-gated. Nothing is cap-gated any more, so
  `hard-cap` is now an unused parameter on `--truncate`, kept as the attachment
  point for the fix.
- Excess in `content_recent`, `git_commits`, `current_window`, `git_state` or
  `fs_state` is unreducible, as before — but now excess in *any* field beyond
  the two segment lists is too.

Documentation is reconciled: five surfaces that asserted a mandatory/enforced
cap now say last-resort/best-effort, and
`satan/test/satan-bough-removal-gate-test.el` carries a repo-wide gate against
a sixth appearing. `satan-memory-evidence/truncate-runs-passes-2-3-only`
asserts label honesty and explicitly asserts the object stays **oversized** once
the passes are exhausted — the honest current behaviour.

**This issue is not closed by that.** The fix is still a general final reducer
(or a redesigned pass chain) that guarantees the cap, plus a test asserting
encoded output bytes ≤ the cap.

Originally surfaced by the SL-001 design inquisition round 2 (RN-7, codex;
adjudicated D7).

Pointers: `satan/satan-memory-evidence.el` (`--truncate`, and the unused
`hard-cap` parameter), `satan/test/satan-memory-evidence-test.el`,
`.doctrine/slice/001/design.md` §10 RN-7 / D7, `.doctrine/slice/002/design.md`
§5.5 (the five reconciled surfaces).
