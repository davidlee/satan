
# Extract observer to a daemon (with or alongside memory substrate)

Extraction candidate under [[POL-001]]. **Dependent:** most coherent extracted
alongside the memory substrate (IMPR-007 — shares substrate + JSON shape).
Standalone extraction is also viable if IMPR-007 stays.

Modules in scope: `dl-satan-observer.el`, `dl-satan-observer-classify.el`.

Fit failure: file scan over 24h of `transcript.jsonl`, deterministic predicate
classifier, dedup state file. No editor primitive used.

Care: the verdict-write path touches the motive footer
(`dl-satan-motive-touch-footer`) and the memory store. If extracted, the daemon
must RPC the verdict back to the broker for application (clean) rather than own
those writes (blurs the trust boundary — bad). Default to RPC-back.

**Blocked / trigger:** follows IMPR-007, or acts standalone per POL-001
§Verification.
