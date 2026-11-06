# ISS-065: SATAN data estate has no owner: retention and backup policy needed per tier, with a proven restore

## The claim

The data SATAN collects and generates is **concentrated PII, distributed across at least
eight stores, with per-tier retention rules that contradict each other and no overall
plan for storage resilience.** Nothing in either repo answers "what do we keep, for how
long, on what medium, and how do we know it comes back". Retention exists in fragments
(panopticon's tiers, `ISS-064`'s unenforced `retention_json`, day-bucketed files in the
state root); backup exists in exactly two places, neither chosen against a rule: the
corpus got a git remote under `CHR-005`, and the **jail** database has a 30-day rolling
archive — while the **host** database, which holds the authoritative history, has
nothing.

This item is the holistic review: inventory, then a rule per tier, then a restore that has
actually been performed.

## Verified host facts (operator, 2026-11-06)

Recorded because they are not derivable from either repo and they change the picture:

- **Host Postgres, database `satan_memory`:** no backup of any kind. (An earlier note in
  this item said `corpus`; the operator corrected it — production binds `satan_memory`, as
  the code defaults already say.)
- **Jail Postgres:** a database entirely separate from `satan_memory`; 30-day rolling
  archive of raw `pg_dump` output to the operator's own disk. Plain SQL, so restorable in
  principle; never restored.

Consequences are in "Why 'no overall plan' is the accurate description" below. The short
version: the archive covers a database that is not the one holding the history.

## Inventory (2026-11-06; each cell verified in code except where marked)

| # | Location | Contents | PII | Retention today | Backup today |
|---|---|---|---|---|---|
| 1 | `~/notes` — `satan-notes-root` (`satan-custom.el:56`) | journal, weekly, inbox, denote notes | highest | the user's own policy | the user's own repo — not SATAN's to change |
| 2 | `~/satan-corpus` — git repo | prompts, framing, **hippocampus** (SATAN's memory *of the user*), motives, inbox, proposals | high | unbounded; git history is the record | git remote (`CHR-005`, closed) — **[verify]** remote present and current |
| 3 | `~/.local/state/satan/runs/<date>/<id>/` | `percept.json` (handles + attention segments), `bundle.json` (the full prompt), `transcript.jsonl` (tool calls **and results**), `actions.json`, `final.json` | **high** — copies of notes content, window titles, URLs, model prose about the user | none; unbounded | none found |
| 4 | `~/.local/state/satan/tick-trace-*.jsonl` — `satan-trace-dir` (`satan-trace.el:37`) | per-tick rows + a ledger of **every psql call** (`satan-db.el:121,164`) | low–medium (argv, labels, timings) | none; one file per day, 152,983 rows as of 2026-11-06 | none |
| 5 | `~/.local/state/satan/` cursors — `sensor-content.json`, ingest cursor, `log/wpm/` | watermarks and counters | low | n/a | none; **not rebuildable** if lost (silently re-reads everything, or skips it) |
| 6a | **Host** Postgres — database `satan_memory` on `/run/postgresql` (matches the code defaults: `satan-attribute-database`, `satan-attrd`'s `DATABASE_URL`, `nix/module.nix`'s `databaseUrl`) | `traces` (LLM prose about the user and its work), `trace_handles`, `satan_interventions`, `satan_intervention_outcomes`, `satan_patterns`/`_outcomes`, `satan_attributes`, `satan_attribute_events`, queues | **high** | none — `ISS-064`: `retention_json` is decorative; `satan_attribute_events` is append-only and unbounded | **none** (operator, 2026-11-06) — the only copy |
| 6b | **Jail** Postgres — a database **entirely separate** from 6a (not a copy or fork; operator, 2026-11-06); contents not established here | whatever jail-side runs write | unknown | 30-day rolling archive | **30-day rolling archive** of raw `pg_dump` output to the operator's own disk (operator, 2026-11-06); plain-SQL format, so restorable in principle with `psql` — never tested |
| 7 | `~/.local/state/behaviour/` — panopticon | `raw/` (desktop/firefox events), `segments/`, `histograms/`, `content/` (**full extracted page text** + digests) | **highest per byte** — page bodies, URLs, titles | `raw/` 7 d (gated on the same-day segment), `segments/` 90 d, `histograms/` forever, `content/`+`digest/` **none** (`panopticon/segmentizer/retention.py`; README tier table) | none |

## Why "no overall plan" is the accurate description

- **The roots' own labels disagree with their contents.** `satan-custom.el:26-28` documents
  the state root as **"discardable"**, while `satan-runs-dir` holds "frozen evidence"
  (`satan-run.el:18-21`) *and* is the input to the daily token ceiling
  (`satan-budget-today-total`, `satan-budget.el:56`). Deleting run bundles silently changes
  spend accounting — so "discardable" is false in effect and unenforced in practice.
- **PII is duplicated across tiers with no redaction pass on the copies.** Panopticon
  redacts at capture, twice (`panopticon/docs/privacy.md`); the broker then copies
  attention segments, percept handles and tool results — including notes content — into
  `bundle.json` and `transcript.jsonl`, which have no redaction and no retention. Every
  copy widens the blast radius and lengthens the tail past panopticon's 7/90-day rules.
- **The backup that exists covers a different database entirely, so the authoritative tier
  has zero coverage.** Operator facts (2026-11-06): the jail database — **entirely separate**
  from the host's, not a copy or fork — has a 30-day rolling archive of raw `pg_dump`
  output; the host database `satan_memory` has **nothing**. The archive is therefore not a
  partial substitute, it is a substitute for somewhere else: the irreplaceable history
  (`traces`, interventions, outcomes, attributes, the append-only attribute event log)
  exists in exactly one place. The archive is at least in a real format — plain SQL, so
  `psql` can consume it — but it has never been restored, and 30 days is shorter than the
  retention the system claims elsewhere (segments 90 days, histograms forever, traces
  unbounded), so an archive horizon that matches no declared rule is a coincidence, not a
  policy.
- **Retention is per-producer, so it never composes.** Panopticon prunes; SATAN does not.
  A page whose raw file is deleted after 7 days survives forever inside a run bundle and
  in `content/`, so the effective retention of that URL is "forever, in two places".
- **No restore has been demonstrated.** `satan-attrd rebuild --include-disabled` can
  rebuild the attribute *projection* from its event log; nothing can rebuild the event log,
  and nothing documents what is expected to survive which failure.
- **Host layer is only partly known.** Verified 2026-11-06 by the operator: host database
  is `satan_memory` with no backup; the jail database is entirely separate and archived as
  raw `pg_dump` for 30 days. Still unverified: encryption at rest, the filesystem/disk
  layout, snapshotting, and whether either archive or any dump has ever been restored.

## Wanted

1. **An owned inventory** — the table above, living in the repo (`docs/data-collection.md`
   gains a retention/backup section, or a new `docs/storage.md`), with a named owner per
   tier and a PII class per tier. Keep it current when a store is added.
2. **A retention rule per tier, written and enforced.** At minimum decide:
   - `runs/` — is a bundle evidence worth keeping forever, or does it age out (7/30/90
     days)? If it ages out, fix the `satan-budget` coupling first (sum from a durable
     counter, not from bundles), or the ceiling breaks the day pruning starts.
   - `tick-trace-*` — day-file rotation and deletion; the psql ledger is the bulk of it
     and is already polluted by test traffic (`ISS-018`).
   - `content/` and `digest/` — the tier with the most PII and no rule at all. Note that
     adding one changes the deferral argument in `RFC-021` §5 item 1.
   - `satan_attribute_events` and `traces` — `ISS-064`'s pruner, or an explicit "keep
     forever" with a size budget.
3. **A backup plan with a restore test, not just a job.** Which tiers are
   authoritative (6a, 2, 5-cursors), which are derived (1 is the user's), which are already
   regenerable. The gap to close is narrow but sharp: **the host database has no copy**,
   while the jail database already has a 30-day rolling archive — so the work is to
   (a) establish that the jail archive is **not** a substitute — confirmed 2026-11-06: the
   jail database is entirely separate from `satan_memory`, so the archive covers none of
   the history that matters; (b) add a host-DB `pg_dump` to off-host storage with an
   interval set from the loss tolerance; and (c) **perform one restore** into a scratch
   instance, dated, with steps recorded — including a restore *from the existing jail
   archive*, which is plain SQL and therefore cheap to test, and which has never been
   tested. Also: corpus remote verified current, and panopticon's content tier decided
   (their repo, their item).
4. **A PII decision on the copies.** Either bundles get a redaction pass at write time, or
   they get a shorter retention than the corpus, or the duplication is accepted explicitly
   and written down. Include the open "current-scope title leak" thread
   (`docs/governance.md:530`) in that decision rather than as a separate mystery.
5. **A failure narrative.** For each of: disk loss, accidental `rm -rf`, database
   corruption, corpus repo loss — what is lost, what is rebuilt, and from what. If the
   answer is "everything since the last dump", say so and set the dump interval from the
   tolerance.

## Out of scope

- Changing panopticon's retention (cross-repo; needs their item — this item should cite it
  once it exists).
- Encrypting anything. That is a host/OS decision; this item states the requirement and
  records the current answer.
- Backing up `~/notes`. The user's own policy; SATAN only reads.

## Relations

- `ISS-064` — the `satan_memory` half of the retention rule.
- `CHR-005` — the corpus remote; with the jail archive, one of only two deliberate backups
  in the estate, and the only one covering a SATAN-owned text store.
- `ISS-018` — the test traffic that makes the tick-trace ledger larger than it should be.
- `RFC-021` — the deferral argument in its §5 item 1 assumes content is never pruned.

## Open

- What is the actual data-loss tolerance — is a day of run bundles a loss, or noise?
- What does the jail database actually hold, and is it worth archiving at all? If nothing
  depends on it, the 30-day archive protects the wrong thing and should either move to
  `satan_memory` or be retired.
- Is anything encrypted at rest today? (host fact, unverified)
- Should bundles be written with a retention marker so pruning can be per-run (an expensive
  run kept, a no-op tick dropped)?
