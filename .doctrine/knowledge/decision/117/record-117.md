# DEC-117: quotient build and npm packaging

<!-- Knowledge record body — context, detail, links. The structured, queried
     fields live in the sister `record-NNN.toml`; this prose is free-form and is
     never structurally parsed (the storage rule). -->


## Amendment 2026-10-22 (devil's-advocate review, operator: "Apply all")

One packageRoot module derives package.json and help/ from import.meta.url, tested from dist/. package-lock.json is committed (buildNpmPackage needs it and npmDepsHash). Pack verification adds one real pi_agent call against the installed tarball through a stub form. engines covers the built .js; dev and tests need a Node with type stripping. npm scope ownership is checked before publish.


## Amendment 2026-10-23 (SL-031 reconcile, RV-059 F-1; operator: "proceed with reconcile")

The package is `@davlee/quotient`, the operator's npm user scope; the `@davidlee` scope is held by another account. The first publish is 0.1.1, from tag `v0.1.1` (`3395eab`). `v0.1.0` (`6c31180`) stays a GitHub-only tag and was never published. The rename changed the lockfile's root name, which moved `npmDepsHash`. The scope-ownership check ran only at publish time, after the name had been tagged and pushed, which cost a re-tag. Run it when the name is chosen.
