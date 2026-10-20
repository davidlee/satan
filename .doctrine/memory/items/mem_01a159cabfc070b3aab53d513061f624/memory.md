`doctrine review raise|dispose|verify|conclude` take a per-review lock. Issuing two in the same shell block (or two subagents raising into one RV concurrently) fails the second with `RV-NNN: busy (another `review` invocation holds the lock)`; a stale lock from a hard kill clears with `doctrine review unlock`.

Consequence for delegation: a review ledger needs a single writer. Fan reviewers out read-only and have them return findings, then raise on the ledger from one place — or serialise the invocations explicitly.

Note also: `doctrine review findings` takes no positional review ref; filter with `-r '^RV-NNN$'` (and `-a` to see terminal states).
