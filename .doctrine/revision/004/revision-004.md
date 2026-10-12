# REV REV-004 — reconcile SL-021

Revision — a pending revise-intent against authored governance/spec
truth. The structured `[[change]]` payload lives in the sister `revision-NNN.toml`;
this prose companion carries the rationale and the free-text before/after excerpts
for prose-body section edits.

## Rationale

<!-- Why this revision: what authored truth needs to change and why, the scope of
     the staged delta, and (for ADR/POL/STD/prose rows) the before/after excerpts
     the structured payload only labels. Seeded at `revision new`. -->

ADR-001 Amendment §2 recorded that the percept fuses replayable segment series
with present-tense live reads (`current_window`, `git_state`, `fs_state`) and
that IMPR-013 would make premise (2) true. SL-021 delivered IMP-013's
`:current_window` move, so the ADR should say so. Append-only: a dated
Amendment §3; §1–§2 are left as written.

**After (appended to ADR-001, after Amendment item 2):**

> 3. **`current_window` is replayable (2026-10-12, SL-021).**
>    `:current_window` — in the evidence window, the sensor-alert causes and
>    `activity_read`'s `current` scope — is now a function of panopticon's
>    durable desktop event series at an instant: `satan-desktop-at ROOT TIME`
>    replays `raw/desktop-<date>.jsonl` (at most two local days) and returns
>    a status (`ok` / `disconnected` / `missing` / `malformed`) and the
>    focused state with `:since`. Nothing reads `current/desktop.json` or
>    judges freshness by mtime. `git_state` / `fs_state` were dropped rather
>    than promoted (IMP-034), so of the inputs §2 named, bough is the one
>    that is still not replayable from a watermark.

## Reconcile narrative

- [RV-022 Reconciliation Brief, "Governance/spec"]: ADR-001 Amendment §2's
  premise-(2) gap is closed for `current_window` by SL-021 (DEC-034..DEC-040).
  Recorded as Amendment §3 above.
- Not REV rows (recorded on the RV outcome): DEC-037 rationale (knowledge edit,
  RV-022 F-7); IMP-013 body (backlog prose).
