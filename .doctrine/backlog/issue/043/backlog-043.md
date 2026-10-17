# ISS-043: satan-attrd jail forwards provider keys on argv

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Split from ISS-029 by SL-022 (which closes ISS-029 for `~/dev/satan` only).
`~/dev/satan-attrd/flake.nix:66` (line as cited by ISS-029 on 2026-09-25)
forwards provider keys into its jail with `try-fwd-env`, which puts them on
bwrap's argv (REQ-016 criterion 3). Likely fix: the agents gateway mode
(`gateway = jailLib.gatewayClient "<client>"`), as SL-022 does for satan's
jails — if attrd still needs a model at all.
