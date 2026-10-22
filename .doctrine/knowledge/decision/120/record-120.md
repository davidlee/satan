# DEC-120: quotient cutover and host migration: side by side, then remove

<!-- Knowledge record body — context, detail, links. The structured, queried
     fields live in the sister `record-NNN.toml`; this prose is free-form and is
     never structurally parsed (the storage rule). -->


## Amendment 2026-10-22 (devil's-advocate review, operator: "Apply all")

Cutover is additive: step 2 builds quotient-* forms alongside pi-mcp-*; old links are removed only in step 7. All env renames are listed: PI_MCP_POLICY, PI_MCP_RUN_DIR, PI_MCP_SESSION_HOME, PI_MCP_ACTIVE_SESSION_DIR -> QUOTIENT_*. satan consumes quotient through a local path: flake input until the GitHub push.

## Amendment 2026-10-22b (design synthesis, operator: "accept")

- Step 4 copies the profiles to .quotient/profiles/; the originals go in step 7 (the old server still reads pi/mcp/profiles/).
- just quotient-forms also builds a GC-rooted link ~/.local/state/quotient/bin/quotient (nix-built, node wrapped); .mcp.json and scripts/lib/pi-report.sh use it, so the server no longer needs a direnv-started session. PI_REDUCE becomes a command rather than a path. Home-manager install is a later option.
- pi/mcp/forms.test.ts tests satan's flake, not the server: it stays in satan (renamed), still run by just check.