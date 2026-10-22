# DEC-116: quotient ships the form contract; satan keeps this host's forms

<!-- Knowledge record body — context, detail, links. The structured, queried
     fields live in the sister `record-NNN.toml`; this prose is free-form and is
     never structurally parsed (the storage rule). -->


## Amendment 2026-10-22 (devil's-advocate review, operator: "Apply all")

form-1 adds a guarantee: the form dies with its parent (bwrap --die-with-parent or the mechanism's equivalent). Operator kept contract-only for v1: strangers on Linux get unconfined write until generic forms ship; the README says so.

## Amendment 2026-10-22b (design synthesis, operator: "accept")

The literal 'nothing reachable beyond exposure' is unachievable (pi needs node, libc, certs, the gateway) and is replaced by:
- G5: the child can write only the root (write capability), the session dir, its private temp, and exposure; anything else visible is read-only.
- G6: the run dir and session home (except this call's session dir) are neither readable nor writable; the policy file and the profile and help layers are not writable.
What the child may read beyond that is the mechanism's choice; form-1 does not promise read confinement of other host secrets.
The root is conveyed by the working directory, so later roots can arrive as new arguments (multi-root is a follow-up backlog item). hostile-audit is generalised (--capability, --model, --exposure; writes its own probe profile; host prerequisites such as the gateway move to satan's wrapper); v1 conformance probes G6's write denial, and G1-G5, G7 are asserted by the implementer.