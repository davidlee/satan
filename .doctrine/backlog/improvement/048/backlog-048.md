# IMP-048: pi-mcp child_binds: declare exposure per bind and check the policy against the generator baseline

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

From SL-029 reconcile (RV-053 F-3, RV-055 F-6; design sec-3, "Two consequences").

Two gaps in one fact:

1. **No exposure half.** `child_binds` is `string[]` (`pi/mcp/policy.ts`), and
   the child-view check reads every member as read-write (`pi/mcp/childview.ts`).
   The form's fixed mounts are mostly read-only, so a policy cannot declare one as
   such. The "policy file is never writable" rule then over-refuses a read-only
   mount that contains the policy file, where a read-only *root* containing it is
   tolerated.
2. **Policy-vs-form is unchecked.** `pi-mcp-forms` proves form = generator
   baseline + root + session (form-vs-generator). Nothing proves that a policy's
   `child_binds` covers the baseline's host-visible binds, so a bind the generator
   adds and the policy omits stays outside the server's child-view check.

Shape: `child_binds: {path, exposure: "read"|"read-write"}[]`, and a check
(flake-side or a server start-up probe against the configured form) that the
declared set covers the baseline's host paths. Keep the release-independence
constraint: compare against a derived baseline, never a copied bind list.

**Concrete trigger (acceptance must cover it).** The generator always binds the
persisted home `~/.local/share/jail.nix/home/agent` read-write at `~`. An
operator who sets `PI_MCP_RUN_DIR` (or `PI_MCP_SESSION_HOME`) under that path
and publishes a minimal `child_binds` that omits it gets no refusal:
`checkChildView` builds the child view only from the policy's `child_binds`
(`pi/mcp/childview.ts`), so no member contains the run directory, and the child
can write the audit. That is two lines of operator configuration and a total
audit bypass. Acceptance: this configuration is refused before spawn, whether the
policy declares the bind or not.

## Update 2026-10-27 (nix-config CHR-023)

Gap 2 is closed upstream: satan's forms are now built by quotient's
`mkFormFamily` (through the agents lib's `quotientFormFamily`), and
`checks.quotient-forms` is quotient's `checkFormFamily`, whose rule (g)
refuses a baseline that writes a host path the family's `exposure` does not
list. The forms carry no persisted home, so the host policy's `exposure` is
`[]`. Gap 1 (`child_binds` → `exposure` without a per-bind read/read-write
half) is quotient's to decide; the `PI_MCP_RUN_DIR` trigger in the
acceptance above names the old server and should be re-read against
quotient's run-dir rules before this item is closed.
