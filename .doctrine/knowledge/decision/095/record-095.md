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
