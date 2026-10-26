# DEC-123: Memory writes attribute their run from the tool-ctx, not the satan-memory-store--current-run-id dynamic var

<!-- Knowledge record body — context, detail, links. The structured, queried
     fields live in the sister `record-NNN.toml`; this prose is free-form and is
     never structurally parsed (the storage rule). -->

Amended 2026-10-26 after an informal Codex (gpt-6.1-sol) review of DEC-121..125; user assent to amended design B and to folding the shape-independent fixes into SL-032.



Amended 2026-10-26 (RV-060 F-5): the earlier choice text gave @satan directives the historical run; the design had nil. Both were wrong against today: @satan directives run as a broker-tick tool (satan-tick.el:121) and emit trace_marked against the consuming run. User chose consuming run for @satan, nil for M-x marks.