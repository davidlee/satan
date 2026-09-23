# ISS-023: Prompt-mode runs (motd, morning) are lost when the keeper is away: 1Password's dialog expires in ~1-2 min

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Observed

SL-018 PHASE-08 (2026-09-23): the 1Password authorization dialog closes itself
after ~1–2 minutes, and `op` reports that as "authorization prompt dismissed".
Run `20260923T221713-motd` → `credential_unavailable`, `.FAILED`, pop.

## Consequence

motd and morning use the `prompt` credential policy (DEC-022). When they fire
(08:15 / 09:15) with no 1Password session and nobody at the desk, the dialog
expires, the run fails loudly, and nothing re-fires it (DEC-020: skip, no
retry). That day's run is lost, though it is now labelled and announced
rather than a silent `KEY not set` (ISS-012).

This breaks the premise DEC-020 recorded ("a prompt-mode read already waits
for the keeper"). The code does what the design says; the premise was wrong.
Surfaced by RV-014 F-1; the keeper accepted it for SL-018's close.

## Options (not yet weighed)

- Prompt, and on `credential_unavailable` fall back to deferral with a retry
  when the next session is live (needs a trigger; see DEC-020's rejected
  "fire-on-warm").
- systemd `Restart=` / a later retry timer for the daily units.
- Accept: the pop is the signal, and the keeper runs motd by hand.
