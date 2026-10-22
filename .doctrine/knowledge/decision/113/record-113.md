# DEC-113: quotient policy schema v1: versioned, profiles pin capability, forms or unconfined

<!-- Knowledge record body — context, detail, links. The structured, queried
     fields live in the sister `record-NNN.toml`; this prose is free-form and is
     never structurally parsed (the storage rule). -->


## Amendment 2026-10-22 (devil's-advocate review, operator: "Apply all")

`exposure` (was child_binds) is defined in quotient-policy-1: the host paths a form exposes to the child beyond the root and session dir, the input to the step-8 disjointness check. An unpinned profile name refuses profile-not-allowed.
