# ISS-062: pi_report prints no report when the reducer fails or stays silent

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->
`pi_report` (`scripts/lib/pi-report.sh`) decides on `command -v` alone. Once the
reducer is on PATH, `|| true` swallows every outcome, so a reducer that fails or
stays silent leaves a header and no report, and `pi_report` still returns 0.

Observed 2026-11-05:

- reducer exits 69: `pi_report` returns 0; header and stderr only, no stream;
- reducer exits 0 and prints nothing (the jail's `quotient`, flakes:ISS-026):
  header only;
- reducer's stdin left open: the jail's `quotient` hangs until killed.

The header's rule, "a noisy report beats a silent one", is broken in all three.

Proposed fix: capture the reducer's stdout, fall back to the tail when it is
empty, and run it with `</dev/null`, since it is given a file. Empty stdout is a
sound signal: `quotient reduce -v` printed 64 B even for an empty stream (exit 1).
Exit 1 with a transcript stays a normal report, because that verdict is the
caller's. Add red-first cases for the failing and silent reducer. Do not change
the `command -v quotient` guard.

**Fixed (2026-11-05).** As proposed: `pi_report` captures the reducer's stdout, falls
back to the tail when it is empty, and closes the reducer's stdin. Exit 1 with a
transcript stays a report. flakes:DEC-122 took the relay out of jails, so a jail
has no `quotient`: it gets the labelled tail, and no `PI_REDUCE` was added. A jail
that enables the relay would need one. `pi-report-test.sh`: 21 of 21 on the host,
16 of 16 in a `jailed-shell` with section 1 skipped; `just check` green in the jail.
