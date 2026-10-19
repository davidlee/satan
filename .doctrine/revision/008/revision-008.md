# REV REV-008 — SPEC-004: project context, doctrine boot and grep in patch jobs (SL-026)

Revision — a pending revise-intent against authored governance/spec
truth. The structured `[[change]]` payload lives in the sister `revision-NNN.toml`;
this prose companion carries the rationale and the free-text before/after excerpts
for prose-body section edits.

## Rationale

<!-- Why this revision: what authored truth needs to change and why, the scope of
     the staged delta, and (for ADR/POL/STD/prose rows) the before/after excerpts
     the structured payload only labels. Seeded at `revision new`. -->

SL-026 (design §4.7) gives patch jobs project context and a `grep` tool.
Drafted at design (2026-10-19); applied at SL-026's `/reconcile`, after
audit, with excerpts finalised against the shipped code. Governing records:
DEC-070, DEC-071, DEC-072, DEC-073.

### §Components — Policy and prompt row

- Before: "the policy ladder, prompt composition (pure)".
- After: "the policy ladder; prompt composition, a pure function of (prompt
  text, resolved policy, job, project context) (DEC-070)".

### §Job contract — append

> Project context read from the job's clone (DEC-072 sources; doctrine's boot
> per DEC-071) is instruction to the model, not policy (DEC-073): it cannot
> set or change the repo, base, allowed paths, mode, model, thinking level,
> ceilings or collection judgement. `preparing` reads it once, after the job
> branch is made; it is composed before the job block in the first input
> message.
> A source the job ran without is recorded as a `context_degraded` job event,
> at least once per admission.

### §Execution environment — tool sentence

- Before: "Tools offered: `read`, `write`, `edit`, `bash`; only `read` is
  replay-safe."
- After: "Tools offered: `read`, `write`, `edit`, `bash`, `grep` (ripgrep in
  the room); `read` and `grep` are replay-safe."

### Audit vocabulary

`job_events` gains `context_degraded` (source, reason): a context source the
job ran without.

## Reconcile narrative

Applied at SL-026 `/reconcile` (2026-10-19), user agreement on the brief.

- [RV-034 brief, Governance/spec]: the four planned excerpts landed as
  drafted at design; the code matches them (malebolge fe7030a + 55f4a68).
- [RV-034 F-3]: `context_degraded` events are at-least-once per admission
  (written before the recorded submit); the job-contract append says so.
- [RV-034 F-1]: the room read mechanism (one `stat -L` per directory from the
  clone root) is design-level detail and stays in SL-026 design §4.2; the
  spec states only what `preparing` reads and when.
