# Jailed pi keeps its own home; provider keys are op:// refs

jailed-pi's persistent home is /home/agent/jail.nix/home/agent (its ~/.pi/agent settings, sessions, models-store). Provider *_API_KEY env vars on the host are unresolved op:// refs: run under 'op run --', outside Claude Code's sandbox (the 1Password desktop socket is blocked inside it).
