`doctrine slice verify-vt` decides attribution with a "modified by this slice" heuristic. A row whose `test_file` is `flake.nix` reports `≈ UNATTRIBUTABLE — keyword present but flake.nix not modified by this slice` even when a slice commit does modify `flake.nix` (SL-029 PHASE-09 VT-1, commit bba7d87).

Do not read that as a missing artefact: check the file, the keyword and the commit yourself, and record the gap rather than "fixing" the row. Attribution also follows the phase status flip, not the commit — judge rows after `doctrine slice phase … --status completed`, not before.
