# Doctrine policy status vocabulary: 'active' is not one, and boot silently omits it

`doctrine policy status --status` accepts exactly:

    draft | required | superseded | deprecated | retired

`active` is **not** in that set. A policy carrying it — POL-001 did, inherited
from the pre-doctrine `spec-driver` era — is reported by `doctrine policy list`
without complaint, passes `doctrine validate` clean, and is then **silently
dropped from the boot snapshot's "Active Policies" section**, which renders
`<!-- No active policies yet -->`.

The consequence is quiet and expensive: the boot snapshot is loaded into every
agent session's system prompt, so a policy in that state is invisible to every
agent that routes correctly. POL-001 — SATAN's only standing policy, and the
gate on module extraction — was invisible this way until 2026-07-22.

**Rule of thumb:** if a governance entity looks absent from the boot snapshot
but `<kind> list` shows it, do not assume a renderer bug. Check its status
against the CLI's own enum first:

    doctrine <kind> status --help    # prints the legal values

`status` is a lifecycle field held in the entity's `.toml`, so a legacy value
travels intact through an import. Corpora imported from another tool — or from
an older doctrine — are where this bites.

Related: [[mem.fact.doctrine.cli-source-of-truth]],
[[mem.concept.doctrine.boot-snapshot]].
