Each repo with its own .doctrine corpus numbers ids independently (DEC-, SL-, ISS-...). SATAN work routinely cites oubliette, malebolge-adjacent and ~/flakes records. An unqualified id resolves in the current corpus, so a cross-corpus citation silently points at the wrong record.

Seen 2026-10-19: SL-026 cited 'DEC-052' for the room's base tools (oubliette DEC-052, `~/dev/oubliette/vm/room.nix:119-120`); `doctrine show DEC-052` in satan returns the SL-023 SQLite job-store decision. A research agent caught it.

How to apply: write a foreign id as '<repo> DEC-NNN' (e.g. 'oubliette DEC-052', '~/flakes CHR-022'). When a cited id's `doctrine show` text does not match the claim, check the other corpora before concluding the claim is wrong.