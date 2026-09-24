# ledger

A very small money utility: amounts are integer cents, never floats.

```
npm run build     tsc → dist/
npm run clean     rm -rf dist
npm test          node --test (Node strips the types; there is no build step
                  in front of the tests)
npm run lint      tsc --noEmit
npm run format    trailing whitespace and final newlines
```

No dependencies. `node` and `tsc` come from the environment.

`build` and `lint` cover the library only — `tsconfig.json` excludes
`*.test.ts`. The tests import `node:test` and `node:assert`, which `tsc` cannot
resolve without `@types/node`, and pulling that in would mean a `node_modules`
and a network round-trip for a project that otherwise needs neither. The tests
are type-stripped and run by Node directly, so nothing type-checks them and
nothing needs to.
