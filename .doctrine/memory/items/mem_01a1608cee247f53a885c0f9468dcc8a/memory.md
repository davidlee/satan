Method used for CHR-021, CHR-022, IMP-050 and IMP-049 (2026-10-21 to 2026-10-22).

**Worker:**
- `doctrine worktree fork --base HEAD --branch <b> --dir ../satan-<x>`. As of
  2026-10-22 it provisions nothing ("0 copied"; no `.worktreeinclude`).
- Then `mkdir -p <wt>/.pi && cp -rL .pi/agents <wt>/.pi/`. `.pi/` is gitignored,
  and `dispatch-worker.md` is a symlink into the gitignored
  `.doctrine/agents/pi/`, so `-L` is required. The operator plans to add both to
  `.worktreeinclude` upstream; when the fork reports copies, drop this step.
- Run the worker from the worktree cwd, in the background:
  `PI_BIN=jailed-pi PI_MODEL=llm-gateway/deepseek-flash PI_BACKSTOP=2400 ./scripts/pi-agent dispatch-worker --think low < prompt.md > out 2> err`
- The prompt must say: edit only the named paths; don't commit; don't touch
  `.doctrine/`; git does not work in the jail (the main repo's
  `.git/worktrees/` is not mounted).
- Import the result into the main tree with `git add -N <new files>` and
  `git diff > p` in the worktree, then `git apply p` in the main tree. Remove the
  fork with `git worktree remove --force` and `git branch -D`.

**Reviewers:**
- Use `pi_agent` (`read` or `research` profile) in the main tree only. The policy
  roots exclude worktrees, so import the diff first.
- The policy allows `requests: 6`. Give the reviewer an exact first command that
  batches every read it needs, plus a hard budget of 4–5 tool calls. If a run
  ends `final: false` at the request ceiling, continue it via `session` with "no
  more tool calls, answer now".
- `research` (thinking low) costs about $0.02 a review and found a real error in
  both IMP-049 and IMP-050.

**Check worker output.** Each worker produced a hand-maintained list or a
shortcut that the code could supply instead. In IMP-049 the refusal list was
hand-copied, and was replaced by a source scan. In CHR-022 `converse` dropped an
unterminated final record, and was fixed with a raw `send`.
