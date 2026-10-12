# ISS-036: Tests depend on the host time zone: canon day handles and id formats use host local time

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Observed

Found by the SL-021 audit (RV-022). The suite passes only on a +10/+11 host.
Full-suite runs with `TZ` overridden fail on both the pre-SL-021 tree
(`87a9757^`) and HEAD — so it predates SL-021:

- `TZ=UTC`: 19 failures — observer, intervention-mark, memory-store and
  patch-store id formats; evidence `bounds-no-run-started`,
  `bounds-run-started-earlier-loses`, `canon-eats-output-minimal`; percept
  `build-empty-sources-yields-only-ctx-handles`.
- `TZ=America/Los_Angeles`: 32 failures.

One root cause: `satan-memory-canon.el` `time.day_week` rule (~436-441)
formats via `date-to-time` in host local time (SL-012 vintage). It could use
`satan-memory-canon-local-date` (SL-021 PHASE-01) with a zone seam, as
`satan-desktop--zone` does. SL-021's own tests pin the zone and pass under
LA / UTC / Kiritimati.

Related, not a duplicate: ISS-021 (observer midnight guard compares UTC row
dates).
