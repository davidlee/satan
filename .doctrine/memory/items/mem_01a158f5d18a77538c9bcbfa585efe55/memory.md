`~/flakes` features (README § Feature tree) are selected per profile. Adding
`(import ./satan/malebolge.nix {inherit lib;})` to `features/satan.nix` made
`home-build` green yet produced **no unit** — the generation had no
`malebolge-room.service`. Fix: `feature.satan.malebolge.enable = lib.mkDefault true;`
in `features/profiles/personal-linux.nix`, and add `"satan.malebolge#homeManager"` to
`features-test.nix` `testSleipnirHomeSelection` (red first, then the enable).

How to apply: after adding a feature, check the built generation for its output
(`find -L result/ -name <unit>`), not just that `home-build` passes. SL-028 PHASE-06.
