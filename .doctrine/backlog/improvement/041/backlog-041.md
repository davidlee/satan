# IMP-041: malebolge: move lint from Biome to typescript-eslint strictTypeChecked

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Why

SL-023 (inq-15) puts the patch runner in `~/dev/malebolge` and asks for
aggressive lint suited to agent-written code. Biome 2.5.15 (checked
2026-10-18 with `biome explain`) lacks the type-aware rules that matter most
there:

- absent: the `no-unsafe-*` family (assignment, argument, return, call,
  member-access), `strict-boolean-expressions`,
  `consistent-type-assertions` (`assertionStyle: never`);
- nursery only, on Biome's own inference rather than tsc:
  `noFloatingPromises`, `noMisusedPromises`, `useAwaitThenable`,
  `useExhaustiveSwitchCases`.

## Shape

typescript-eslint `strictTypeChecked` + `stylisticTypeChecked` with
`projectService`, plus: the unsafe family and promise hygiene at error;
`strict-boolean-expressions` with every `allow*` off;
`switch-exhaustiveness-check`; `no-unnecessary-condition`; type assertions
never; no non-null assertion; explicit return / module-boundary types;
`complexity` ≤ 8, `max-depth` 3, `max-lines-per-function` 80 (off in tests);
`curly`, `eqeqeq`, no nested ternary; import-x order/no-duplicates;
unused-imports; unicorn filename kebab-case, `prefer-node-protocol`,
`no-array-reduce`. Biome may stay as formatter only, or be dropped for one
tool.

## Sequencing

Land before SL-023's runner code, so the runner is written under it rather
than retrofitted.

## Resolution (2026-10-18, SL-023 PHASE-02)

Done in malebolge `239794c`: `eslint.config.js` (strictTypeChecked +
stylisticTypeChecked, projectService, the rule list above), Biome kept as
format check only (`just fmt-check`), `just check` green with zero warnings,
zero type assertions, zero eslint-disable. typescript-eslint 8.71.x needs
TypeScript < 6.1 with the classic compiler API, so malebolge now pins
`typescript@6.0.3` (was the Go-native 7.0.2); CHR-015 tracks the return to
TS 7. Note: the root `eslint.config.js`/`vitest.config.ts` fall outside
Biome's `files.includes` in malebolge's `biome.json` (user-owned, not edited).
