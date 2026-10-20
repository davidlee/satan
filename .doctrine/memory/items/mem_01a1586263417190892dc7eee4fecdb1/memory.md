# jailed-pi dies with its launching shell: no background/nohup launches

bwrap --die-with-parent means a jail launched in the background dies as soon as the launching shell exits, killing the worker silently. Launch jailed agents in the FOREGROUND inside a single supervisor call, and use --session-id + a stable session dir to resume a chunk that ran out of time under the timeout. Never background-detach a jailed pi run.
