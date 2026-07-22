# Codex external review round-trip over the RV ledger

External adversarial review via codex MCP: unsandboxed session raises findings on an RV ledger, responder disposes, codex-reply verifies — full round-trip

## Workflow (proven on RV-010 / SL-012)

1. Responder opens the ledger: `doctrine review new --facet <facet> --target SL-NNN --raiser codex`.
2. Author a self-contained hostile prompt (artifact list, attack-surface probes,
   evidence rules, "probe N: clean" required) — hand it to codex via the
   `mcp__codex__codex` MCP tool.
3. Codex needs **write access to raise findings**: `sandbox: danger-full-access`,
   `approval-policy: never`, cwd = repo root. It runs
   `doctrine review raise RV-NNN --severity … --title … --detail …` per finding.
4. Responder adjudicates each finding on evidence (/feedback conduct), fixes
   artifacts, disposes: `doctrine review dispose RV-NNN --finding F-N …`.
5. Close the loop with `mcp__codex__codex-reply` (same `threadId`): codex
   re-reads the fixes and runs `doctrine review verify` (or `contest`) per
   finding. Ledger reaches `done · await=none`.

## Sharp edges

- **Jail reservation remote unreachable** — every id-allocating doctrine verb
  (review new/raise) needs `DOCTRINE_RESERVATION_FALLBACK=1` prefixed.
- **Unsandboxed codex may stage files** (`git add`-happy). After a codex
  session, check `git status` before committing — an RV-010 session left
  `.dispatch/SL-11/**` (a git worktree, 604 files) staged; commit swept it in
  and needed a soft-reset + surgical recommit. `.dispatch/` is now gitignored.
- Codex finding details can arrive with mangled evidence (backticks eaten by
  shell interpolation in --detail). Substance survives; verify claims yourself
  against the tree before disposing.
