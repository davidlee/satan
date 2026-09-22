# ISS-015: Test suite leaks real side effects: logger and desktop notifications escape the stubs

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Running `just test` writes to the user's **system journal** under the `satan`
syslog tag and fires **real desktop notifications**. Observed 2026-09-23: five
suite runs produced fifteen `budget-exceeded morning … 500000/400000 tokens`
notifications and matching `satan[PID]` journal lines between 08:38:45 and
08:39:17.

## Mechanism

`satan-broker--announce-failure` (satan/satan-broker.el:331) performs two
side effects, neither reliably stubbed:

    (call-process "logger" nil 0 nil "-t" "satan" "-p" "user.warn" line)   ← 1
    (notifications-notify …)                                              ← 2

1. **`logger` is an external process.** Test files that `cl-letf` the symbol
   `notifications-notify` cannot intercept it. It is gated only by
   `satan-failure-syslog`, which tests do not bind.
2. **The notification gate opens *because* of the test harness.** It fires when
   `(= 1 (satan-broker--failure-streak-count satan-runs-dir))`. Tests
   `let`-bind `satan-runs-dir` to a temp directory holding a single failed
   fixture run — so the streak is exactly 1 and the gate opens, where against
   the real runs dir it would usually be suppressed.

The stub coverage is partial and per-file: `satan-broker-test.el`,
`satan-sensor-alerts-test.el`, `satan-tools-notify-test.el` and
`satan-patch-listener-test.el` each stub `notifications-notify` locally. Nothing
covers the syslog path, and nothing covers paths those files do not reach.

## Why it matters beyond the annoyance

SATAN's own diagnostics read this journal. `sleipnir-doctor` counts
`panopticon-sway` errors from it, and this session used `satan[…]` journal
lines as primary evidence. A test suite that writes plausible-looking
operational records into the log being diagnosed **corrupts the evidence
base** — a future investigation can mistake fixture output for production
behaviour.

## Shape of a fix

Prefer a single seam over per-file stubs: route both effects through one
injectable announcer (a variable holding the announce function, or a
`satan-announce-inhibit` bound for the whole batch run in `satan-test`), so
that suppressing them is the harness's job once, not each test's job
repeatedly. Per-file `cl-letf` has already proven to be the wrong granularity —
it is what let this through.

Related: [[ISS-013]] (concurrent `just check` clobbers shared test databases) —
same family: the suite is not hermetic with respect to shared host state.

Distinct from [[mem.fact.satan.green-is-not-green]], which covers the suite
reporting a false *result*; this is the suite producing real *side effects* on
the live host. Same root theme — the suite is not hermetic.
