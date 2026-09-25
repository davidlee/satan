# A stub is a claim about a foreign program — check the claim

SL-020 shipped `notes_read` and `notes_grep` over the notes corpus with 28 green
tests, and two defects survived a design review, a 17-finding adversarial
review, and the whole suite. A **live round trip against the host's `~/notes`**
found them in minutes.

## The instance

`satan-tools-notes-test.el` stubs `call-process` globally and hands back
hand-written stdout. Every fixture emitted **bare file names** (`old.org\0`).
Real `fd` does not print that:

```
fd -t f --changed-after 1h --print0 --base-directory /tmp/fdt
  -> ./journal/2026-09-25--x.org      # ./-prefixed
fd -t f --changed-after 1h --print0 --absolute-path --base-directory /tmp/fdt
  -> /tmp/fdt/journal/2026-09-25--x.org
```

So `notes_recent` emitted `./journal/…` as `:path`, and `notes_read` — whose
resolver refuses any leading-dot component as a hidden path — refused the exact
string its sibling had just produced. The `notes_recent → notes_read` contract
was never tested; the stub asserted a fiction and the suite agreed with it.

## The rule

- When a fixture stands in for an external binary, **at least one test must emit
  the shape the binary actually emits**, taken from the binary itself — run it
  once, paste the bytes.
- Prefer asserting the round trip over asserting the parts: feed one tool's
  output into its partner and require success. Field-level tests of each end
  cannot see a disagreement about the middle.
- `--base-directory` (fd) changes the **output form**, not just the search
  scope. A flag's side effects on the format are as load-bearing as its filter.
- Sibling trap: a shared result builder that serves two contracts leaks its
  private keys into the consumer that does not need them (`:_sort` is right for
  `notes_recent`, which sorts on it, and wrong for `notes_read`). Strip at the
  boundary with one named helper rather than duplicating the strip per caller.

See also [[mem.fact.satan.green-is-not-green]] — "the suite is green" names a
claim about the suite, never about the system.
