Verified 2026-10-20 (SL-027 RV-038 F-1, jail.nix pin 404e7da).

- jail.nix `set-env` only writes `state.env`. The runtime-closure binds
  (`bind-nix-store-runtime-closure`) come from `additionalRuntimeClosures`,
  `state.argv` and `state.entry` — never env. So
  `(set-env "X" "${pkgs.writeText …}")` hands the jail a path that does not
  exist inside it. Strings in the wrapper/entry (e.g. `${pkgs.socat}/bin/…`
  in a wrap-entry) and `extraPkgs` (`add-pkg-deps`) *are* in the closure.
- Fix: `(readonly "${drv}")` (explicit ro-bind of the store path), or
  `extraPkgs` when it is a package with `bin/`.
- A text-probe check that reads the file on the host passes regardless. Assert
  the path is bound: grep the launcher's
  `exec {RUNTIME_CLOSURE_BIND_ARGS_FD}<…-runtime-closure-bind-args` file
  (`grep -Fa`), or the launcher for `--ro-bind <path> <path> `.
  `malebolge-jail-profile` in satan's flake.nix does both.

Related: [[mem.pattern.nix.text-probe-flake-check-silent-pass]],
[[mem.fact.jail.bind-the-socket-directory-not-the-file]].