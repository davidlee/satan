## Decision

The server grants only roots from an operator-configured allowlist (`roots` in the policy artefact, inq-12), never "any directory the host user can read".

- Each requested root is canonicalised (`realpath`, symlinks resolved) and must be an existing directory.
- It must lie inside exactly one allowlist entry, compared on path **components**, not string prefix.
- `/` and `$HOME` are never allowed implicitly; they may be allowlisted only explicitly, which then shows in the policy file and in the audit record.
- Named refusals: `root-not-allowlisted`, `root-missing`, `root-not-a-directory`.

## What the server does not authorise

The wrapper may bind sibling mounts the server knows nothing about (`workspaceDeps` at the flake). The server authorises the *root*; the flake decides the rest of the reach. That split is stated rather than implied, and it is the honest limit of the server's authority claim.

## Why

A validity grammar (absolute, existing, not `/`, not `$HOME`) catches accidents and is not a control: a client can still name another sensitive directory the user can read. The product question (reach for any readable directory, or an operator set?) is answered here as the operator set, because the server hands out agent execution to a caller it does not authenticate.

## Consequence

The policy artefact (inq-12) is doubly load-bearing: it carries the ceilings and the root allowlist. Absent policy fails closed, which is also the root-authorisation story.

## RV-043 F-1 (indirect exposure): a broad allowlist entry does not override the protected stores

Allowlisting `$HOME` or `/` remains permitted, and now has a stated cost: the child-view disjointness check refuses `view-overlaps-protected` while such a root reaches the evidence stores or another session's directory (any exposure at all), or the policy file (a writable exposure — this root as `write`, or a rw fixed bind). Broad reach and reachable control stores are not both grantable; the operator narrows the root or relocates the stores, and the refusal names the path. Masking the store instead of refusing would mean the server authoring bwrap args (SPEC-001 REQ-009), which is the split this decision already refuses.

The tracked profile documents are deliberately **not** in the protected set: a write-capable root already confers authority over the server's own code and flake forms, so guarding them would be theatre.
