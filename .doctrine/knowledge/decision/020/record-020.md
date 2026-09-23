# DEC-020: Deferred runs are skipped; credentials are acquired before the run is allocated

<!-- Knowledge record body — context, detail, links. The structured, queried
     fields live in the sister `record-NNN.toml`; this prose is free-form and is
     never structurally parsed (the storage rule). -->


## Note (2026-09-23, RV-014 F-1): the wait is bounded

The context's "a prompt-mode read … already waits for the keeper" and the
choice's "no expiry exists" hold for SATAN, not for 1Password. Its dialog
self-expires after ~1–2 min and `op` reports "authorization prompt
dismissed", so an unattended prompt-mode run records `credential_unavailable`
(DEC-022 (7)) rather than waiting for the keeper (SL-018 PHASE-08, run
`20260923T221713-motd`). The choice stands; the residual, where a prompt-mode
run is lost when the keeper is away, is ISS-023.
