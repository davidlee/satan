# IMP-052: quotient hostile-audit: one probe per guarantee; a timeout fails rather than skips

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Raised as SL-031 audit finding RV-059 F-7 (`doctrine show RV-059`). Both weaknesses predate SL-031: they came over unchanged from SL-029's pi-mcp
probe into quotient's `scripts/hostile-audit`.

- **F8:** a delegate timeout reports SKIP, not FAIL. A probe that never reaches
  its verdict cannot pass the audit.
- **F9:** the attempt check matches any bash command that names the run root,
  not the append command specifically. A delegate that only lists the root
  counts as an attempt.

Shape: one probe per guarantee (read-only root, append-only audit), each with a
precise attempt matcher and fail-closed on timeout. The code lives in
`~/dev/quotient/scripts/hostile-audit` (github:davidlee/quotient), and satan
runs it through `just quotient-hostile-audit`.
