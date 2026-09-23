# DEC-022: Unattended credential policy: per-mode prompt or defer, time-based escalation, attended override

<!-- Knowledge record body — context, detail, links. The structured, queried
     fields live in the sister `record-NNN.toml`; this prose is free-form and is
     never structurally parsed (the storage rule). -->


## Note (2026-09-23, RV-013 F-8): representation

The design (sec-4) represents `(defer :escalate-after DURATION)` as two flat
mode-spec keys, `:credential-policy` (`prompt`|`defer`) and
`:credential-escalate-after` (seconds; defaulting to
`satan-credential-escalate-after`). The substance is unchanged. The flat form is
idiomatic elisp and merges through `satan-mode--apply-profile`.
`satan-mode-register` validates both.
