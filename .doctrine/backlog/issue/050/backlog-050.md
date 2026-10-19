# ISS-050: The interactive daemon's coding-tool calls reach no append-only audit

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## What

ADR-017 authority ledger row 4a (append-only audit → run actions, owner
`emacs-client`, `satan-audit-record`) covers calls that pass through the
SATAN MCP dispatch in Emacs (`satan-mcp.el`). The malebolge interactive
daemon's coding tools (`read`, `write`, `edit`, `bash`, `grep`) are pi-durable
extensions (`~/dev/malebolge/src/daemon-extensions.ts`) and never reach that
dispatch. Their only record is the pi-durable transcript
(`~/.local/state/satan/durable/<profile>/session.sqlite`), which is not shown
to be append-only and has no ledger owner. SPEC-001 REQ-003 asks for an
append-only audit of actions.

Pre-existing: true of the daemon's host coding tools today. SL-027 moves those
tools into room `assistant` (vm mode) and neither creates nor closes the gap;
its design §7 T3 names it.

## Shape (open)

Decide whether the transcript is the audit (prove append-only, give it a row
or extend 4b's pattern) or the daemon emits action records to an owned
append-only sink; record the owner in the ledger either way.

## Links

Raised as F-5 on RV-035 (SL-027 design review); user accepted deferral
2026-10-20. SPEC-001 REQ-003; ADR-017 §2–3; ledger rows 4a, 4b.
