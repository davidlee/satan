# ~/flakes switches build some inputs from local checkouts

`just home-switch`, `just home-build`, `just system-switch` and `just system-build`
in `~/flakes` pass `bin/dev-checkouts override`: every input with a `~/dev`
(or `/srv/fleet`) checkout present is replaced by `git+file:` of that checkout
— committed and tracked files, dirty edits included. As of 2026-10-19 that is
`fleet`, `goad`, `malebolge`, `panopticon`, `satan-attrd`
(`bin/dev-checkouts names`). The `satan` input is **not** among them — see
[[mem.fact.satan.runtime-jail-deploys-from-github-input]].

## The trap

A switch succeeds from **unpushed** commits while `flake.lock` still pins the
old remote revision. The live system is then not reproducible from the lock:
any lock-based build (fresh clone, another host, the override absent) brings
the old code back. SL-025 hit this: the satan-runner was deployed with a new
config parser from an unpushed malebolge, while the lock pinned a parser that
refuses the new `[mode.*]` keys — a lock build would refuse to start
(RV-032 F-6).

Conversely, a fleet change needs only a commit before the switch, not a
push + `nix flake update fleet` (SL-025 driver erratum).

## Finish a deploy

`SATAN.md` § satan-runner: commit, push, `just update-local`, switch. If you
switched first, push and `just update-local` after, then check the lock
reproduces the running build — e.g. `nix eval --raw
'.#homeConfigurations."david@<host>".config.systemd.user.services.<unit>.Service.ExecStart'`
without overrides, against `systemctl --user show <unit> -p ExecStart`.
The root input may map to a suffixed lock node (`malebolge_2`): read
`.nodes.root.inputs.<name>` before trusting `.nodes.<name>`.
