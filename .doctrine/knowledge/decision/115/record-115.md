# DEC-115: quotient built-in help: one sectioned source for model and human

<!-- Knowledge record body — context, detail, links. The structured, queried
     fields live in the sister `record-NNN.toml`; this prose is free-form and is
     never structurally parsed (the storage rule). -->


## Amendment 2026-10-22 (devil's-advocate review, operator: "Apply all")

Help sections policy, refusals and form print the normative contract docs verbatim (docs/contract/*); only agent and tool are separate prose. Help directories are protected stores per the DEC-112 amendment.

## Amendment 2026-10-22b (design synthesis, operator: "accept")

- Sections: agent, tool (model-facing prose); result (docs/contract/pi-agent-result-1.md, with refusals as an alias), policy (quotient-policy-1.md), form (form-1.md); profiles, setup, clients, reduce (prose or rendered).
- In v1 the contract sections (result/refusals, policy, form) are not overridable; the others are. Overriding contract sections is a possible later change.
- agent renders the snapshot profiles with the capability pinned by the policy as read at initialize; unreadable policy shows 'unknown (policy unavailable)' and the server still starts.