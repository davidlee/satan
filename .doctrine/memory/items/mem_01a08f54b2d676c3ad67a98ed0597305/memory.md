# home-manager switch starts every enabled-but-inactive user unit

home-manager activation's reloadSystemd step (re)starts every enabled user unit that is inactive, changed or not — a deliberately stopped timer/service comes back. Quiesce-then-rebuild cutovers must rebuild after the Emacs restart or re-stop timers right after the switch.

## Evidence (SL-015 PHASE-02, 2026-09-11)

After `systemctl --user stop satan-{tick,motd,morning}.timer wpm-archive.timer
satan-attrd.service wpm-daemon.service`, `just home-switch` (only `sway.nix`
changed) printed:

    Starting units: satan-attrd.service, satan-morning.timer, satan-motd.timer,
    satan-tick.timer, stasis.service, wpm-archive.timer, wpm-daemon.service

Nothing fired only because every `Persistent=true` window had passed for the
day. Timers were re-stopped by hand. See [[SL-015]] notes.md PHASE-02 and
[[mem.signpost.satan.orientation]] for the timer-before-Emacs hazard.
