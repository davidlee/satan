# CHR-023: Amend POL-001: Rust is the default daemon language, not the target; most appropriate choice wins

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->
Raised 2026-10-26 by the user, during IMP-055: Rust is a sensible default,
not a hard line. The language policy should be "the most appropriate
choice", as malebolge (TypeScript) and panopticon (Python, plus a JS browser
extension) already show.

POL-001 § (extraction conventions) currently reads "**Rust is the target
language for SATAN-orbit daemons**", with panopticon and the patch runner
kept as workload-fit exceptions. Reword it so Rust is the default and the
most appropriate language wins, with the reasons to prefer Rust (PG +
LISTEN/NOTIFY, `sqlx` compile-time checks, replay determinism) kept as
guidance. Also update the matching line in the SATAN orientation memory
("Rust is the target language for SATAN-orbit daemons").

POL-001 is an accepted policy: amend it through a revision (`doctrine
revision`), with the user's assent recorded.
