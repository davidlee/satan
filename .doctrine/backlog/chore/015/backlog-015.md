# CHR-015: malebolge: return to TypeScript 7 once typescript-eslint supports it

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Why

SL-023 PHASE-02 (IMP-041) moved malebolge's lint to typescript-eslint
strictTypeChecked with `projectService`. typescript-eslint 8.71.x declares
peer `typescript >=4.8.4 <6.1.0` and needs the classic compiler API;
`typescript@7.0.2` (the Go-native compiler, malebolge's original pin) ships
only `tsc.js`/`getExePath`/`version`. PHASE-02 therefore pinned
`typescript@6.0.3` for both tsc and eslint (one compiler; all DEC-053 flags
work). Orchestrator choice, 2026-10-18; reversible.

## Done when

typescript-eslint supports TypeScript 7's API; malebolge returns to TS 7 for
both, `just check` green.
