# ASM-002: A read inside a live 1Password session never prompts

<!-- Knowledge record body — context, detail, links. The structured, queried
     fields live in the sister `record-NNN.toml`; this prose is free-form and is
     never structurally parsed (the storage rule). -->


## Watch armed — SL-018 PHASE-08 (2026-09-23)

SL-018 is live in the keeper's Emacs. The watch in the validation plan is now in
force; slice closure does not wait on it.

**Evidence to capture when it trips.** The 1Password dialog shows no context.
The label is in the D-Bus "1Password read" notification that dl-secret raises
on a cache miss (body `<context> → <ref>`). Record the notification's time and
body, the run id (under `~/.local/state/satan/runs/<date>/`), and whether
`op whoami` exited 0 just before. A trip is a context of `satan broker/<mode>`
with no "(escalated: …)" suffix, from a defer-mode run (tick-*, anything but
morning/motd), with `op whoami` live.

**Rollout observations (not validation).** Every dialog seen in PHASE-08 came
from an escalated tick-pulse run or from motd (prompt policy), each time with
`op whoami` exiting 1. None matches the trip. Separately: 1Password's dialog
expires after about 1–2 minutes, and `op` reports that as "authorization prompt
dismissed", so a trip would be recorded as a `credential_unavailable` run, not
as a hang.
