# A generated jail wrapper can bind a run-time path via raw args and an env var

The flakes/agents wrapper is a shell script whose bwrap raw args expand at run time, so a path the flake cannot know at build time can still be bound: satan's own flake binds "$SATAN_RUN_DIR" this way (flake.nix:161). Consequence: a persistent session home (or run dir) outside the jail's static bind set is expressible with --bind "$VAR" + --setenv, which is how a jailed delegate keeps a session across runs without the repo hosting it.
