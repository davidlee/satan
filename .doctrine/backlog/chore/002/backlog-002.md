# CHR-002: Declare [verification] cadence commands in doctrine.toml so doctrine check gate resolves

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Context

Surfaced by [[SL-013]]'s reconciliation audit (RV-003 F-11). The `/audit` skill
mandates running `doctrine check gate` as part of evidence gathering. In this
repo it exits non-zero:

```
$ doctrine check gate
error: justfile does not contain recipe `gate`
```

`.doctrine/doctrine.toml` declares no `[verification]` section, so `doctrine
check gate` falls back to its unconfigured default of `just gate` — which this
project does not define. The project's actual gate is `just check` (lint + test,
tests interpreted via `emacs --batch`), recorded in the governance block.

## Why it matters

No verification was skipped in SL-013 — every phase ran `just check` directly —
so this is not slice drift. But it leaves a documented, mandated audit step
permanently broken for **every** slice audit in this repo, which trains the
reader to skip it. The cost is one config block.

## The fix

Add to `.doctrine/doctrine.toml`:

```toml
[verification]
commit = "just check"
gate   = "just check"
```

`quick` may stay unconfigured (its unconfigured default is an owned no-op that
never fails a hook). `prove` should only be declared if a non-mutating
assert-clean recipe exists — `just check` is not one if it formats in place.
Check the justfile before declaring `prove`.

## Related

- [[SL-013]], RV-003 F-11.
- `doctrine check --help` — cadence resolution and the POL-002 note that host
  conventions are informative, never correctness.
