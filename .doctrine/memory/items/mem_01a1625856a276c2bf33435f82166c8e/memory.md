**When:** you want an external adversarial reviewer (gpt-6-sol, per the operator's global instructions) and the `codex` MCP server fails to connect, which it did in two SL-031 sessions.

**How (worked on RV-058, 2026-10-22):**

- Round 1: `codex exec -m gpt-6-sol -s read-only -C <repo> -o <out.md> - < prompt.md`, run in the background; it takes minutes. The read-only sandbox lets it read the repo and the code it cites; it edits nothing.
- In the prompt, name the files to read and ask for a fixed block per finding (severity, location, claim, evidence, repair) plus a "Not checked" list. This lets the blocks be split mechanically into `doctrine review raise --detail @file`.
- Verify rounds: `codex exec -m gpt-6-sol -s read-only -C <repo> -o <out.md> resume <session-id> -`, with the stdin carrying `doctrine review show RV-NNN -f F-n` for each answered finding. The reviewer keeps its own context and answers "F<n>: verified" or "not resolved — reason", and raises only new defects. The session id is in the stderr header.
- Its "not resolved" verdicts are real contests: record them with `review contest` and re-dispose. Two of them were correct on RV-058.

**Gotcha:** the design-run lock refuses severe (blocker/major) findings without a `--route`. Set the route at the first dispose. Adding it after verify means a reopen, a re-dispose and a re-verify for each finding, and then concluding again.
