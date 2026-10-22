# DEC-112: quotient configuration resolution, split by authority

<!-- Knowledge record body — context, detail, links. The structured, queried
     fields live in the sister `record-NNN.toml`; this prose is free-form and is
     never structurally parsed (the storage rule). -->


## Amendment 2026-10-22 (devil's-advocate review, operator: "Apply all")

The profile and help directories (both layers) join the existing protected stores of validation step 8 (pi/mcp/childview.ts protectedStores) with tolerance never-writable: a write call whose root contains either is refused view-overlaps-protected. Consequence: write delegates cannot run with a root containing the server's launch dir; in satan they run in worktrees. The profile digest is audit-only (recorded, never compared). A profile name absent from the policy map refuses with the existing profile-not-allowed. The new server's state roots are disjoint from pi-mcp's from the first run.

## Amendment 2026-10-22b (design synthesis, operator: "accept")

- Profile and help layers are protected stores whether or not they exist (canonicalPath handles absent paths); a write delegate cannot create .quotient/ under the launch dir.
- Only an unset QUOTIENT_* var falls through to XDG; a set-but-empty or relative value refuses policy-unavailable. A relative XDG_* is ignored per the XDG spec.
- A missing layer directory is an empty layer. An unreadable layer, or an invalid document in either layer (shadowed or not), refuses start-up (profile-invalid on every call).
- Profile header marker renamed pi-mcp-profile -> quotient-profile, no alias.
- Resolution lives in one pure module, src/config.ts, used by policy, profiles and help.