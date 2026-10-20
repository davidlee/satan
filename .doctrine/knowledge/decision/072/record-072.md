# DEC-072: Malebolge project-context sources: pi's AGENTS chain to the git root, .pi/APPEND_SYSTEM.md, doctrine boot; 64 KiB each

<!-- Knowledge record body — context, detail, links. The structured, queried
     fields live in the sister `record-NNN.toml`; this prose is free-form and is
     never structurally parsed (the storage rule). -->


## Amended (SL-027, 2026-10-20)

DEC-080 amends this decision's daemon half: the daemon reads project context through its environment (the room's shell in the room profile, from the room user's home), not with node fs at startup. The runner half is unchanged.