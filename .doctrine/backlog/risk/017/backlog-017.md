# RSK-017: Niri desktop-event pin lines are derived, not captured; niri shape drift goes unseen

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

SL-021's VT-7 pins the `raw/desktop-<date>.jsonl` event shapes the
`satan-desktop.el` reader depends on. The umbriel lines are sanitised
captures; the niri lines are derived by hand, because umbriel is the live
WM and there is no live niri source (RV-022 Synthesis).

Risk: if panopticon's niri producer changes its event shape, the pin test
keeps passing and `current_window` silently degrades to `malformed` /
`missing` once niri is in use again.

Mitigation: when niri is next run, capture real lines and replace the
derived fixtures.
