`satan-run-new-ctx` (satan/satan-run.el) seeds the run struct's `prepare`
plist with every placeholder key — `:evidence`, `:percept`,
`:sensor_status`, `:pre_spawn`, `:motive`, `:observer` — set to nil
("present-with-nil"). Later stages of `satan-broker--spawn` fill them.

Consequence: `(plist-member prepare :pre_spawn)` is always true and cannot
tell whether a stage ran; neither can `(not (null prepare))`. RV-012 F-4 hit
this: crash-context `:pre_spawn_completed` over-reported on every
`spawn_failed` run. The fix was an explicit run-struct slot,
`satan-run-pre-spawn-completed`, set as the last binding of the pre-spawn
`let*` in `--spawn`.

When you need "did stage X run?", use an explicit marker (a struct slot),
never key presence in `prepare`. Serialise such booleans as `t` / `:false`;
nil serialises to `{}`.
