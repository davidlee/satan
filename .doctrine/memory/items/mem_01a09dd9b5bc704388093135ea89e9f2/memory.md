# SATAN runtime jail deploys from the GitHub flake input, not the working tree

SATAN's runtime bwrap jail is built from the github:davidlee/satan flake input in ~/flakes, not from ~/dev/satan — a flake.nix bind change needs push + nix flake update satan + home-switch; a raw --bind to a missing path kills every run

## Chain

    Emacs PATH → ~/.nix-profile/bin/jailed-satan-gptel-harness
      ← ~/flakes/modules/home/linux/satan.nix (inputs.satan)
      ← ~/flakes/flake.lock: github:davidlee/satan @ <locked rev>

Building `.#jailed-satan-gptel-harness` in `~/dev/satan` proves the wrapper is
right; it does not deploy it. To ship a `flake.nix` change:

1. commit + `git push origin main` in `~/dev/satan`
2. `nix flake update satan` in `~/flakes`, commit the lock in `~`
3. `just home-switch` (starts stopped units — see
   [[mem.fact.nix.home-manager-switch-starts-stopped-units]])
4. `readlink -f ~/.nix-profile/bin/jailed-satan-gptel-harness` and grep the
   store script for the new bind

## Why it bites

Corpus/state binds are raw `unsafe-add-raw-args --bind "$HOME/…"`. bwrap fails
hard when a bind source is missing, so moving a bound directory before the
switch lands kills every run at spawn. In a relocation, the push/lock/switch is
on the critical path: quiesce timers + patcher across the window.

## Evidence (SL-015 PHASE-03, 2026-09-14)

Lock was at `4ecc741` (2026-07-22) — seven weeks behind the working tree.
Cutover pushed `4ecc741..8a49d16`, bumped the lock (`~` `1aea39ad`),
switched after the Emacs restart; tick `20260914T125539-tick-pulse-c3dce4`
ran clean with the `$HOME/satan/hippocampus` bind.
