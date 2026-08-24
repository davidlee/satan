# Home-manager symlinks hide path consumers from grep -r

Every ~/.config dotfile is a /nix/store symlink: grep -r reports clean over them, and the rendered file is not the edit target — the flake source is.

## Two consequences, both bite path migrations

**1. `grep -r` does not follow symlinks.** Proven on this machine:

```
grep -rn  "notes/satan" ~/.config/systemd/user/                      # 0 hits
grep -rn --dereference-recursive "notes/satan" ~/.config/systemd/user/  # 2 hits
```

A `$HOME` sweep for old paths therefore reports **clean over precisely the
consumers that are hardest to fix**. Any such sweep must use
`--dereference-recursive` (or `-R`), and must also grep `~/flakes` sources
directly — the rendered symlink farm is derived, the flake is the source of
truth.

**2. The rendered file is read-only and not the edit target.** e.g.
`~/.config/systemd/user/satan-patcher.service` →
`/nix/store/…-home-manager-files/…`. Citing it in a plan as "the line to
change" is a category error: the change goes in
`~/flakes/modules/home/linux/<module>.nix`, followed by a home-manager rebuild
and (for units) `systemctl --user daemon-reload`.

Corollary: an option's *effective* value may come from a module default in a
different repo entirely, when the flake module declares the service without
setting that option. Read the flake module's `services.<name>` block before
believing a value in the rendered unit is pinned by anything local.

## Where this bit

SL-015 (SATAN corpus relocation): two consumer surfaces in `~/flakes` were
missing from an otherwise careful design inventory, and one design decision
rested on a systemd "pin" that did not exist. Both were invisible to the
non-dereferencing grep the design specified as its verification.
