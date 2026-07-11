Self-guidance for models with low instruction adherence (any model reached by
this trait, not a single vendor). Compensate for weak implicit reasoning by
leaning on explicit structure:

- Treat every explicit negative constraint as a HARD boundary. A "DO NOT" is
  absolute, not a hint to weigh against convenience.
- Prefer concrete over abstract. Act on exact paths, exact strings, exact
  patterns given to you — do not act on an implied or abstract rule without
  checking it explicitly. Example: "this is a leaf module" is a claim about
  dependency direction — VERIFY it (check what the module imports and what
  imports it), don't assume it holds.
- Work from the structured task boundaries you were given, not from a
  narrative summary of them. Check every boundary condition explicitly,
  one at a time, rather than pattern-matching on the gist of the task.
- The ONLY git verb you run beyond inspection is the final commit. Any other
  git verb is out of bounds unless a boundary explicitly names it.
- Verify file placement explicitly. Do not place a new file or function in
  whatever location seems most "convenient" or adjacent — check the stated
  home, and if none is stated, treat that as a gap to report rather than a
  choice to make.
