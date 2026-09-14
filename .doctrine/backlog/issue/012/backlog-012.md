# ISS-012: motd and morning runs fail at turn 0 on an expired API key; tick runs succeed

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Every scheduled `motd` and `morning` run since late August ends `.FAILED` at
turn 0:

    {"type": "error", "error": "{\"class\": \"auth\", \"detail\": \"Error code: 401 -
     ... 'API key expired.' ...\", \"tokens_total\": 0, \"turn\": 0}"}

e.g. `~/.local/state/satan/runs/2026-09-14/20260914T130956-motd-006d80.FAILED`.
In the same minute `20260914T131029-tick-agent-2f0a48` completed a real model
turn — so the tick modes resolve a different provider/key than motd/morning.

Two things to fix:
1. Renew the key, or point motd/morning at the working provider.
2. Nothing surfaced this for ~3 weeks (`status: invalid` is silent — cf.
   IMP-005). A run that fails on auth should be loud.

Seen in SL-015 PHASE-02 (F-4) and PHASE-03; unrelated to the corpus move.
