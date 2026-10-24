# IMP-043: Review a patch job's diff from the Emacs inbox

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

The patch inbox offers only `satan-patch-promote` / `satan-patch-reject`; the
user promotes without seeing the change. The runner's `result` already carries
`commits` and `diffstat` (SL-023 design §5.1 op table) and
`satan-patch-rpc--job-fields` projects them, but
`satan-patch-inbox--body-fields` never renders them.

Proposed:
1. Render diffstat + commit subjects in the inbox entry body.
2. `satan-patch-show`: job id at point → fetch the quarantine ref into the
   incoming ref (reuse `satan-patch-promote--fetch`, no second fetch path) →
   show `base_oid..reviewed_oid` in magit (fall back to `vc-diff`); drop the
   incoming ref after.

Workaround today:
`git --git-dir=/var/lib/capsule/collect/assistant/<repo>.git show <reviewed_oid>`.

Raised 2026-10-19 after the SL-023 PHASE-14 closure run.

## Implementation (2026-10-24)

Design sketch agreed with the user in-session (proposals 1–3 above, with
adjustments). Uncommitted at time of writing.

- `satan-patch-show` / `satan-patch-show-job` (`satan/satan-patch-promote.el`):
  `result` (needs_review + `base_oid` and the promote fields) → fetch into
  `refs/satan/incoming/<id>` → verify == `reviewed_oid` → delete the ref →
  `magit-diff-range base..reviewed` in the real repo, else a plain
  `git diff --stat --patch` buffer in diff-mode. No branch, no disposition,
  entry left unread. Git never runs inside the quarantine (its config is
  runner-owned; `core.fsmonitor`/textconv would execute).
- Refactor, no second fetch path: `--fetch`/`--land` became
  `--with-incoming JOB THEN CALLBACK` (fetch, verify, THEN, always delete
  the incoming ref); `--verify-incoming` split out of `--create-branch`;
  `--reviewable` takes its required-field list.
- Inbox (`satan/satan-patch-inbox.el`): watch summaries lack
  `commits`/`diffstat` (malebolge `views.ts` `summary` vs `resultBody`), so
  a needs_review entry is appended from a timer after a `result` call;
  a refused `result` appends without them. Body gains `Diffstat:` and
  `Commits:` (short oid + subject; continuation lines indented so a message
  cannot open an Org heading).
- Full commit messages: the renderer prefers a commit's `message` field,
  falling back to `subject`. Malebolge side (same day, uncommitted):
  `commitsIn` (`src/runner/git.ts`) now logs `%H %s%x00%B` and each
  `CommitInfo` carries `message` (full, as git stores it; empty allowed),
  recorded in the `collected` event and so in `result`. Additive: SPEC-004
  and the SL-023 design name `commits` without a shape. Live once the
  runner is redeployed from the pushed malebolge input.

Tests: `satan-patch-show/*` (3) in `satan-patch-promote-test.el`,
`satan-patch-inbox/review-entry-shows-diffstat-and-commits`. Full
`just test` green (1313, 0 unexpected); `just lint` clean.
