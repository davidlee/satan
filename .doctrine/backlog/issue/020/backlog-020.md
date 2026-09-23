# ISS-020: Broker sentinel leaves spawn-running set when finalize signals

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

`satan-broker--make-sentinel` (`satan/satan-broker.el:420-430`) calls
`satan-broker--finalize` and then `(setq satan-run--spawn-running nil)` with no
`unwind-protect`. Any signal from finalize (output handler bookkeeping, audit
close, rename, announce) leaves the flag set. The MCP server then refuses every
interactive session (`satan-mcp.el:157`, `:434`), and after SL-018's `run_busy`
gate (DEC-023) every scheduled run is refused too, until Emacs restarts.

Fix: wrap the finalize call in `unwind-protect` so the reset always runs.
Surfaced by RV-013 F-5 (SL-018 design review); predates SL-018, so it is
outside that slice. DEC-023 raises the severity, and SL-018 may absorb it
cheaply.
