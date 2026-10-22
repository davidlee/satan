# DEC-117: quotient build and npm packaging

<!-- Knowledge record body — context, detail, links. The structured, queried
     fields live in the sister `record-NNN.toml`; this prose is free-form and is
     never structurally parsed (the storage rule). -->


## Amendment 2026-10-22 (devil's-advocate review, operator: "Apply all")

One packageRoot module derives package.json and help/ from import.meta.url, tested from dist/. package-lock.json is committed (buildNpmPackage needs it and npmDepsHash). Pack verification adds one real pi_agent call against the installed tarball through a stub form. engines covers the built .js; dev and tests need a Node with type stripping. npm scope ownership is checked before publish.
