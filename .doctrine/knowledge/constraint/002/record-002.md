# CON-002: Brokered-authority packages must accept generated JSON config that maps to the SATAN authority model

<!-- Knowledge record body — context, detail, links. The structured, queried
     fields live in the sister `record-NNN.toml`; this prose is free-form and is
     never structurally parsed (the storage rule). -->

Bound by SPEC-001 REQ-006: policy is published once, read-only, and every
surface reads it rather than restating it. The ADR-017 §3 ledger is also bound
by REQ-009 (no dual enforcement).

Therefore, when evaluating adopt-or-build options for `auth-gateway` and
`git-broker` (RFC-018 OQ-1), an option qualifies only if **we can generate its
configuration (JSON, per ASM-003) from our policy artifact**, mapping onto our
authority model:

- session/principal → the grant that package enforces;
- capability → the package's permission vocabulary (models and providers,
  token cap for ledger row 5b; git subcommand + argument shapes and permitted
  refs for rows 9–10);
- credentials are referenced by name; they never appear in the generated file.

A tool whose permissions can only be hand-edited, or whose vocabulary cannot
express a grant we need, fails this constraint. It would force a second,
hand-maintained copy of policy.
