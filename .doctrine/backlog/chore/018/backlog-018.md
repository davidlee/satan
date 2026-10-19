# CHR-018: Move jailed-malebolge out of ~/notes/flake.nix

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

`jailed-malebolge` is defined in `~/notes/flake.nix` (jailPkgs block, shared
`mkJail` helper) but nothing in it is notes-specific: it runs SATAN's session
daemon from `~/dev/malebolge` and binds `~/satan-corpus` plus SATAN runtime and
state dirs. Candidate homes: `~/dev/satan/flake.nix` (already has gateway
clients) or malebolge's own flake (needs `mkJail` as an input; overlaps
CHR-017).

Custody constraint (SL-023 PHASE-18, malebolge 8c93902): the daemon reads its
gateway key only from a file (`~/.config/llm-gateway/keys/malebolge`, override
`MALEBOLGE_GATEWAY_KEY_FILE`) and its catalog from
`~/.config/malebolge/gateway-models.json` (override `MALEBOLGE_GATEWAY_CATALOG`).
`gatewayClient` passes `LLM_GATEWAY_KEY` by env, which the daemon ignores — the
jail must bind both files read-only and set the two env vars.

The gateway switch itself is another agent's work (user ruling 2026-10-19,
outside SL-023); this chore is the relocation.
