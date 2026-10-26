# A quit inside a process filter does not cross the C reader

Observed (SL-032 PHASE-05/06, probes in notes `## Execution log`):

- `(signal 'quit nil)` from code running inside a real process filter is
  caught at the C boundary (`read_process_output`), which reports
  "error in process filter: Quit". In batch Emacs that kills the run (no ERT
  summary). Interactively, inference: the quit is swallowed there, so the
  code that called `accept-process-output` never sees it.
- `satan-mcp.el` therefore re-raises a settled quit with
  `satan-mcp--resignal-quit`: signal at filter depth 1, `(setq quit-flag t)`
  in a nested filter (`satan-mcp--filter-depth`), so the enclosing wait
  raises it and the enclosing call settles on it.

Testing: never let a quit escape a real filter in an ERT test. Hand the
chunk to `satan-mcp--filter` directly inside `condition-case ... (quit ...)`
(see `satan-mcp/settle-quit-closes-transport`, `close-quit-*`).
