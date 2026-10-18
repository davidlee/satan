# ISS-045: Gateway launcher refusal hint names the jail, not the issued key alias

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Context

Found in SL-022 PHASE-08 VH-3 (RV-024 F-9). With `keys/satan` moved aside, the
harness launcher's refusal reads:

    Issue one: llm-gateway issue satan-gptel-harness --models <a,b> --budget <usd> --out ".../keys/satan"

The issued alias is `satan` (the keyFile basename); the hint uses the jail
name. Cosmetic, but it misleads whoever follows it.

## Owner

Not this repo: the text comes from the jail library's gateway key check in
`~/flakes/agents/jailed-agents.nix` (`gatewayOuter`). Fix there (derive the
alias from the key file name), then re-lock `agents` here. The test fixture
`satan-broker-test--launcher-refusal` mirrors the text; update it if it changes.

## Resolution

Duplicate of flakes:IMP-037 (minted at SL-022 design; same defect, owned in ~/flakes).
