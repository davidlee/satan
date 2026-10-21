# jailed-pi dies with its launching shell: no background/nohup launches

bwrap --die-with-parent means a jail launched in the background dies as soon as the launching shell exits, killing the worker silently. Launch jailed agents in the FOREGROUND inside a single supervisor call, and use --session-id + a stable session dir to resume a chunk that ran out of time under the timeout. Never background-detach a jailed pi run.

## Narrowed (2026-10-21, SL-030)

`--die-with-parent` ties the jail to its *direct parent process*, not to the launching shell's
session. A wrapper launched with `setsid nohup ./run-pi.sh … < /dev/null & disown` (the wrapper,
e.g. `timeout … jailed-pi …`, stays alive as the jail's parent) survived the launching tool call
and completed — six runs, planner/worker/reviewer, up to ~15 min each. What dies is a bare
`jailed-pi … &` whose parent shell exits. Recipe: [[mem.pattern.doctrine.pi-tiered-capsule-execution]].
