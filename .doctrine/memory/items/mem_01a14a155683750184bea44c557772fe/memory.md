# SATAN broker and deployed harness come from different builds

- **Elisp (broker, patch runner):** Emacs loads `~/dev/satan/satan` directly
  (`~/.config/emacs/core/dl-path.el` `my/checkout-lisp-dirs`). A change lands on
  the next load of satan in Emacs (restart / reload), no build.
- **Deployed harness and `jailed-*` on PATH:** built by home-manager from
  `~/flakes`' **locked** `satan` input (`features/satan/harness.nix`), with
  `agents.follows`. `just home-switch` passes `tree_override` (in-tree
  `agents`, `emacs`) and `bin/dev-checkouts override` (goad, panopticon,
  satan-patcher, satan-attrd, fleet) — **not** `satan`.
- **Dev jails in `~/dev/satan`:** direnv `use flake_local agents` → live
  `~/flakes/agents`.

Consequence: a change to the broker↔harness contract has a rollout order.
Make the new harness accept the old broker's env, deploy it (push satan →
`nix flake update satan` in flakes → home-switch), and only then let Emacs
load the new satan. Landing satan first breaks every tick until the switch.
Found in SL-022 review (RV-023 F-2, F-3).
