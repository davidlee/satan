Verified in SL-026 design review (RV-033 F-2, F-7).

- `rg --json` emits the whole matching line and every submatch whatever
  `--max-columns` says, so a parser must bound its line carry and truncate at
  parse — malebolge `boundedLineSplitter` (`src/ndjson.ts`), `src/grep.ts`.
- rg exits 2 when any file errors, even after matching: exit 2 with matches is
  partial success, not failure.
