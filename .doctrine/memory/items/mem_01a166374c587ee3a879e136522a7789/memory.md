# Publishing quotient to npm

Learned in SL-031 PHASE-12 (RV-059 F-1).

- **Check the scope when the name is chosen, before tagging.** The scope is the
  npm *user* (`davlee`), not the GitHub user (`davidlee`). `@davidlee` is held
  by another account, so the planned `@davidlee/quotient` 0.1.0 became
  `@davlee/quotient` 0.1.1. The public tag `v0.1.0` couldn't be reused, which
  cost a re-tag. `npm whoami` gives the user scope; `npm access list packages
  <user>` lists what it owns.
- **Renaming moves `npmDepsHash`.** The lockfile root's name feeds the deps
  hash, so Q's `flake.nix` hash must be updated (the nix build prints `got:`).
- **`pack-check` doesn't prepare the checkout it was run from.** It runs `npm ci`
  in its own copy. A fresh `git worktree` of the tag needs `npm ci` before
  `npm publish`, or `prepack` (tsc) fails with `TS2688 … 'node'`.
- **2FA is browser-based and needs a TTY.** Through an agent's shell or a `!`
  run it fails with `EOTP`, and the URL is masked. The operator runs
  `npm publish --access public` in a real terminal, or passes `--otp=<code>`
  from an authenticator app.
- **A new package returns 404 publicly for a few minutes** (~195 s here)
  after `+ name@version`, while `npm access list packages` already lists it.
  Poll before running `npx`.
