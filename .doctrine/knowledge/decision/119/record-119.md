# DEC-119: quotient standalone docs and contract drift tests

<!-- Knowledge record body — context, detail, links. The structured, queried
     fields live in the sister `record-NNN.toml`; this prose is free-form and is
     never structurally parsed (the storage rule). -->


## Amendment 2026-10-22 (devil's-advocate review, operator: "Apply all")

The result-contract drift test asserts key-set equality in both directions at every nesting level. Help prints contracts verbatim (DEC-115 amendment), so there is no separate help copy to drift.

## Amendment 2026-10-22b (design synthesis, operator: "accept")

The refusal-token drift test checks the result contract (help section result, alias refusals). Add a drift test that docs/ contains no doctrine ids (SL-/DEC-/RV-/ADR-/REQ-/POL-NNN).