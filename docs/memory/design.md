---
name: satan-memory-design
description: SATAN memory substrate design — grammar, canonicalizer, evidence window, persistence schema
metadata:
  type: design
  topic: satan-memory
  status: canon
  updated_at: 03398479
  verified_at: 03398479
---

# SATAN — Memory Substrate (Design)

Status: design draft, pre-implementation.
Prerequisites:

- `~/.emacs.d/memory.brief.md` — substrate principles and addressing rules
- `~/.emacs.d/docs/satan/governance.md` — broker invariants and ownership model
- `~/notes/20260519T003129--satan__agent_emacs_project.org` — organism framing

This document is the more-grounded plan that follows the brief and the
persistence addendum. It does not restate them; it commits to the bets
they leave open.

---

## 0. Settled decisions

1. **SATAN canonicalizes deterministically.** Handles are assigned by
   pure functions over structured inputs. No LLM inference in the
   canonicalize step. The model may supply *typed hints*; the
   canonicalizer alias-maps and validates them. The model does not
   author handles.

2. **Traces may originate from the LLM or from deterministic
   auto-markers.** The `memory_mark` write path is the same regardless
   of originator. The substrate admits three origin classes
   (`trace_origin`):

   - `llm_mark` — the model called `memory_mark`.
   - `auto_rule` — a broker-side rule observed a strong-signal pattern
     and emitted a mark.
   - `external` — manual import, backfill, future bridges.

   v1 ships only `llm_mark`. `auto_rule` slots in by writing through
   the same canonicalizer; no schema change required. There is no
   auto-marker scanning every focus segment in v1 and none planned —
   auto-marking is reserved for sparse, high-signal events (bough
   status changes, explicit user keystroke, known editor
   compile/test failures).

3. **Hippocampus directory is empty — clean slate.** No migration.
   The existing prose-org `hippocampus_write` surface coexists as a
   separate concern (curated semantic notes, not the trace substrate).

4. **Storage: PostgreSQL, new database `satan_memory`.** Owner
   `david`, socket `/run/postgresql`. Schema follows the addendum's
   relational shape. No FDW into bough in v1.

5. **Bough is read-only, via the `bough` CLI.** No parallel read
   logic. No direct connection to `bough_production` or `bough_agent`
   from satan code. Bough is a primary integration surface; traces
   address bough nodes by nanoid.

6. **Grammar evolves at boundary.** Per brief §14. Every trace stores
   the `grammar_version` that was current at write time; aliases and
   weights are also versioned; existing traces are re-normalizable
   from `metadata_json` + per-handle `source`.

## 1. Concepts

The substrate composes the brief's affordances minimally:
*mark → address → store → cue → resonate → weight → fade → show.*

Trace **kinds** (closed enum, fixed at v1):

| kind         | meaning                              | v1 emission                              |
|--------------|--------------------------------------|------------------------------------------|
| observation  | "this happened, here is what I saw"  | yes — via `memory_mark`                  |
| intervention | a thing SATAN did                    | schema-only; not emitted in v1           |
| prediction   | forecast about future state          | schema-only; not emitted in v1           |
| outcome      | scoring of a prior prediction        | schema-only; LLM may emit if it chooses  |

Trace **origin** is orthogonal to kind and recorded separately
(`traces.trace_origin`). See §0.2 for the enum. The combination
(`kind`, `trace_origin`) gives the audit answer to "why does this
trace exist": *what was observed* × *who decided it should be
remembered*.

`note` (pure semantic, no observational evidence) is deferred. The
existing `hippocampus_write` org-file surface already serves that
shape; promoting it to a structured trace is a v2 decision.

## 2. Grammar

### 2.1 Namespaces

Inventory plus their world type and where values come from. Closed-world
namespaces have enumerated values (§2.2); open-world namespaces accept
any normalized slug.

| namespace             | world  | primary source                                  |
|-----------------------|--------|-------------------------------------------------|
| `app`                 | open   | panopticon (sway / firefox)                     |
| `surface`             | closed | derived from `app`                              |
| `project`             | open   | cwd / git remote / org filetags                 |
| `repo`                | open   | git remote slug                                 |
| `domain`              | open   | panopticon (firefox tab segments)               |
| `domain_kind`         | closed | derived from `domain` allowlist                 |
| `file_kind`           | closed | cwd extension / org filetags                    |
| `event`               | closed | rule-derived from raw stream                    |
| `surface_transition`  | closed | rule-derived from focus_segments deltas         |
| `event_transition`    | closed | rule-derived; pairs event with destination      |
| `domain_transition`   | closed | rule-derived from browser_segments deltas       |
| `artifact`            | closed | observed write (file / git / bough)             |
| `phase`               | closed | LLM hint only                                   |
| `intervention`        | closed | SATAN-emitted; v2+                              |
| `outcome`             | closed | bough / git / file-derived                      |
| `topic`               | open   | LLM hint only (array)                           |
| `bough_kind`          | closed | `bough_read`                                    |
| `bough_status`        | closed | `bough_read`                                    |
| `bough_event`         | closed | `bough_read recent_changes`                     |
| `bough_node`          | open   | bough nanoid; *downweighted*                    |
| `bough_project`       | open   | parent project nanoid                           |
| `workspace`           | open   | bough workspace slug                            |
| `queue`               | open   | bough queue name                                |
| `week`                | open   | ISO week                                        |
| `day`                 | open   | YYYY-MM-DD                                      |
| `mode`                | closed | SATAN run mode                                  |

### 2.2 Initial closed-world values (v1 grammar)

These are *grammar entries*. The substrate may admit a value before any
emission rule produces it (so the schema doesn't churn when an emitter
lands later).

```text
surface:        browser | editor | terminal | desktop | chat
domain_kind:    docs | learning | reference | social | search | tooling
              | repo_hosting | unknown
file_kind:      org | source | config | data | binary | doc | unknown
event:          command_error | command_ok | idle_begin | idle_end
              | desktop_switch | tab_open | tab_close
              | window_focus_change
surface_transition:
                terminal->browser | editor->browser | browser->editor
              | idle->editor
event_transition:
                command_error->browser | command_error->docs
domain_transition:
                docs->editor
artifact:       none | file_edit | commit | note
              | bough_status_change | bough_task_created
              | bough_annotation
phase:          orientation | execution | recovery | post_failure | review
intervention:   ask | accuse | delay | dim | pin | quarantine | surface
              | withhold | summon | annotate | reward
outcome:        unknown | returned_to_editing | continued_drift
              | produced_artifact | abandoned_context | bough_progress
bough_kind:     task | group | project | note
bough_status:   todo | active | done | dropped
bough_event:    created | status_changed | annotated | described
              | moved | linked | archived
mode:           morning | motd | tick-pulse | self-edit-mech | self-edit-mind
```

Some values have no current emitter (e.g. `event:command_error` —
panopticon does not see terminal exit codes today; see §10.8). Those
entries are admitted now to keep the grammar stable across future
emitter additions.

### 2.3 Aliases (v1 seed)

```text
reference     -> domain_kind:docs
manual        -> domain_kind:docs
documentation -> domain_kind:docs
tutorial      -> domain_kind:learning
guide         -> domain_kind:learning
howto         -> domain_kind:learning
```

LLM hints flow through this map before validation. Stored in
`handle_aliases`; new aliases require no code change. Bump policy in
§7.1.

### 2.4 Initial weights

Per brief §11, with bough and split-transition additions. Stored in
`handle_weights(namespace, value, weight, grammar_version)`. A row with
`value = '__default__'` is the namespace default; per-value overrides
permitted.

```text
project              1
surface              1
app                  1
mode                 1
domain_kind          2
file_kind            1
event                2
surface_transition   3
event_transition     3
domain_transition    2
artifact             3
phase                2
intervention         2
outcome              3
topic                1
bough_kind           1
bough_status         2
bough_event          2
bough_project        1
bough_node           0   # present for audit/show; never dominates scoring
workspace            1
queue                1
day                  1
week                 1
```

### 2.5 Handle syntax (locked)

Canonical handles match the regex

```text
^[a-z][a-z0-9_]*:[A-Za-z0-9][A-Za-z0-9_.+>-]*$
```

Namespace is lowercase (controlled vocabulary). Value side admits
uppercase to accommodate external IDs (bough nanoids use mixed case).
Transitions use `->` literally inside the value (`terminal->browser`).
Enforced both in the canonicalizer and as a DB `CHECK` constraint on
`trace_handles.handle` and `handle_aliases.canonical_handle`.

## 3. Canonicalizer

Pure function:

```text
canonicalize(evidence_window, hints, ctx)
  -> (handles[], handle_sources{}, rejected[])
```

### 3.1 Inputs

**`evidence_window`** — deterministic structural snapshot, assembled by
the broker (§4):

```text
current_window      panopticon current/sway.json
focus_segments[]    panopticon segments/focus-<day>.jsonl tail
browser_segments[]  panopticon segments/browser-<day>.jsonl tail
bough_recent[]      bough_read recent_changes since window_start
bough_active[]      bough_read active
bough_day           bough_read day
git_state           HEAD short ref, dirty/clean, last 5 commits (cwd-derived)
fs_state            cwd, recently-edited files (cheap heuristic)
window_start_at
window_end_at
```

**`hints`** — LLM-supplied, typed, optional. Hints are *candidates*,
not handles; they pass through alias map and closed-world validation:

```text
kind:              observation | intervention | prediction | outcome   (default: observation)
phase:             <closed-world phase value>
topic:             array of open-world slugs; max 5; dedup after normalization
focal_app:         <open-world app slug>
focal_bough_nanoid: <nanoid>
valence:           positive | negative | neutral | mixed | unknown
outcome_for:       <trace_id>   # only when kind = outcome
```

Unknown closed-world hint values are **rejected** with a useful alias
suggestion list. Unknown open-world hints are normalized to slug form
and accepted.

**`ctx`** — SATAN-supplied:

```text
run_id
mode_name
time_now
current_grammar_version
trusted_workspace_slug
```

### 3.2 Outputs

```text
handles[]           canonical "namespace:value" strings; typically 5–12 per brief §9
handle_sources{}    per-handle provenance (see below)
rejected[]          unknown closed-world hint inputs to surface to caller
```

**`handle_sources`** — one JSON object per emitted handle, stored
verbatim in `trace_handles.source`:

```json
{
  "rule_id":          "panopticon.surface_transition",
  "origin":           "observed|derived|hint|ctx",
  "evidence_pointer": "/focus_segments/3..5",
  "hint_field":       null,
  "confidence":       1.0,
  "grammar_version":  1
}
```

`origin` classifies how the handle arose:

- `observed` — direct sensor fact (panopticon raw, bough event).
- `derived` — computed from observed input (e.g. `surface` from `app`).
- `hint` — supplied by the LLM; `hint_field` records which.
- `ctx` — SATAN runtime context (mode, day, week).

`evidence_pointer` is a coarse JSON-pointer-style reference into
`metadata_json.evidence` — enough for a human or a re-norm pass to
locate the inputs that produced the handle. `null` is acceptable for
`ctx` origin.

### 3.3 Rules

Each rule is a named pure predicate over `(evidence_window, hints,
ctx)`. Rules emit zero or more handles. Rules live as individual
defuns in `satan-memory-canon.el` and are individually testable.

Initial rules (illustrative, not exhaustive):

| rule_id                          | emits                                                       |
|----------------------------------|-------------------------------------------------------------|
| `panopticon.current.app`         | `app:<id>` + `surface:<derived>`                            |
| `panopticon.surface_transition`  | `surface_transition:<from>-><to>` from focus_segments       |
| `panopticon.event_transition`    | `event_transition:<event>-><surface>` (inert in v1)          |
| `panopticon.domain_transition`   | `domain_transition:<from>-><to>` from browser_segments      |
| `panopticon.docs_visit`          | `domain_kind:docs` if any browser segment matches allowlist |
| `bough.recent_status_change`     | `bough_event:status_changed`, `artifact:bough_status_change`|
| `bough.active_focus`             | `bough_node:<nanoid>`, `bough_project:<nanoid>`             |
| `cwd.project`                    | `project:<slug>` from cwd / git remote                      |
| `cwd.file_kind`                  | `file_kind:<value>`                                         |
| `ctx.mode`                       | `mode:<mode_name>`                                          |
| `time.day_week`                  | `day:<YYYY-MM-DD>`, `week:<iso-week>`                       |
| `hint.topic`                     | `topic:<slug>` (one per array entry) post-alias             |
| `hint.phase`                     | `phase:<value>` after closed-world validation               |
| `hint.kind`                      | sets trace `kind` (not a handle)                            |

Rules are explicit and small. A long `cond` in one function is forbidden.

### 3.4 Determinism guarantees

- Same `(evidence_window, hints, ctx)` → same handles. Verified by
  golden fixtures under `test/canon-fixtures/`.
- Wall clock is consulted only via `ctx.time_now`.
- No file or network IO inside rules; all evidence loaded by the
  caller in §4.
- Random identifiers (`trace_id`) allocated outside the canonicalizer.

### 3.5 Purity boundary

The three concerns are strictly separated:

```text
evidence assembly  (§4)  impure, time-sensitive, IO-heavy
canonicalization   (§3)  pure, deterministic, fixture-testable
storage            (§6)  transactional
```

Rules in `satan-memory-canon.el` must **not** call `bough`, shell
out, read files, consult the system clock except via `ctx.time_now`,
or touch the network. A grep-lint in the test suite enforces this
(forbidden symbols: `shell-command`, `call-process`,
`insert-file-contents`, `url-retrieve`, `current-time`, `current-time-string`,
direct `bough` invocations).

### 3.6 Handle count

Brief §9: traces should normally carry 5–12 handles. The canonicalizer
does not refuse counts outside this band; it warns. A trace with two
handles is allowed (it just won't resonate well); a trace with thirty
is allowed (it will resonate too well — surface to the caller).

## 4. Evidence window

The window is the bounded snapshot that backs one `memory_mark`.

### 4.1 Bounds

```text
end_at      = ctx.time_now
start_at    = max(end_at - 10 minutes, mode_run.started_at)
seg_limit   = 10 segments per source (focus, browser)
bough_limit = 50 recent changes (deduped by nanoid)
```

If the mode-run is shorter than 10 minutes, the window does not extend
before run start. A fresh tick-pulse should not be credited with the
previous session's evidence.

### 4.2 Sources

| Source                | Path / call                                                          |
|-----------------------|----------------------------------------------------------------------|
| panopticon current    | `~/.local/state/behaviour/current/sway.json`                         |
| panopticon focus      | `~/.local/state/behaviour/segments/focus-<day>.jsonl` (tail)         |
| panopticon browser    | `~/.local/state/behaviour/segments/browser-<day>.jsonl` (tail)       |
| bough recent_changes  | `bough --json … recent_changes --since <start_at>` (or composed)     |
| bough active          | `bough --json task list --status active`                             |
| bough day             | `bough --json day get`                                               |
| git state             | `git -C <cwd> log -n 5 --oneline` + `git status --porcelain` (capped)|
| cwd                   | `default-directory` of active Emacs buffer, or `pwd` if from tty     |

The exact bough invocations track the bough-cli surface; see §10.2.

### 4.3 Snapshot semantics

The full snapshot is stored in `traces.metadata_json` alongside the
trace. This is the audit + re-normalization payload.

Size budget: target ~16 KB per trace, hard cap 64 KB. Oversize triggers
deterministic truncation; the fact of truncation is recorded under
`metadata_json.truncated_at` with what was dropped.

**Truncation priority** (deterministic so audit quality does not depend
on incidental JSON ordering):

Always retained, never truncated:

```text
ctx
hints
canonical-derived identifiers (cwd, git HEAD short, focal_bough_nanoid)
truncation note
```

Retained if budget permits, in this order:

```text
current_window
first 3 + last 3 of focus_segments (middle dropped)
first 3 + last 3 of browser_segments (middle dropped)
git status summary (short)
bough_active (limit 10, newest first)
bough_recent (limit 10, newest first)
bough_day (linked items only; bodies excluded)
```

Truncated first when budget is exceeded:

```text
long browser session bodies / titles (older middle dropped before first/last)
large bough annotation bodies (replaced with "…" placeholder + `len_original`)
full git log text beyond short refs
fs_state file lists beyond limit
```

## 5. Tool surface

Four new tools, all broker-owned, all schema-validated against
`~/notes/satan/tools/<tool>.md` model-facing descriptions.

### 5.1 `memory_mark`

```text
risk:        low (writes only to satan_memory)
capability:  memory-write
modes:       morning | motd | tick-pulse   (initial)
args:
  payload    string, required        # display prose, ~1–4 sentences
  hints      object, optional        # see §3.1
  valence    enum, optional          # positive|negative|neutral|mixed|unknown
  links      array, optional         # [{relation, target_trace_id}]
returns:
  ok    { trace_id, handles[], rejected[] }
  error STRING
```

The broker resolves the evidence window at call time. The LLM does not
pass evidence; it cannot lie about it. The broker stamps
`trace_origin = 'llm_mark'` (the handler is identified by tool dispatch,
not by an arg). Canonicalizer runs; `traces` + `trace_handles` + any
`trace_links` are written in one transaction.

### 5.2 `memory_resonate`

```text
risk:        read
capability:  none
modes:       morning | motd | tick-pulse | self-edit-mech | self-edit-mind  (initial)
args:
  cue        object, optional
    handles[]                        # explicit handle list, optional
    hints                            # same shape as mark hints
  limit      integer, optional       # default 5, max 25
  kinds[]    array, optional         # restrict to kinds
  min_score  float, optional         # default 0
returns:
  ok { matches[ { trace_id, score, matched_handles[], trace } ],
       cue_handles[] }
```

If `cue` is absent, the broker derives it via the same canonicalizer
with `hints = nil`. Resonance is weighted overlap × trace strength ×
recency decay (§6.4); both score and matched handles ride along so the
LLM can quote them ("this rang because: command error, browser
transition, no artifact").

v1: **purely read-only**. `memory_resonate` does not mutate
`access_count` or `last_accessed_at`. Touching is explicit and
deferred to a v2 surface (`memory_touch_traces` and/or
`memory_reinforce`). Read idempotence makes audit and replay
tractable.

Driver: **explicit LLM call only in v1.** Auto-injection of top-k
matches into tick-pulse system prompts is a v2 layer (it composes; the
substrate does not need to know).

### 5.3 `memory_show_trace`

```text
risk:        read
capability:  none
args:
  trace_id   string, required
returns:
  ok { trace, handles[], handle_sources{}, links[], strength_fields }
  error STRING
```

For audit and LLM follow-up after a resonance hit. `metadata_json`
included but large blobs truncated with a recorded note. Also
read-only in v1.

### 5.4 `bough_read`

Companion read tool. Shell-out wrapper around the `bough` CLI; same
output shape per scope. This tool is the **only** path SATAN uses to
read bough — both LLM-facing calls and the canonicalizer's internal
queries go through it. No direct PG access to `bough_*` databases
from satan code.

```text
risk:        read
capability:  none
modes:       morning | motd | tick-pulse | self-edit-mech | self-edit-mind
args:
  scope    enum, required
  …        scope-specific args (nanoid, since, limit, workspace)
returns:
  ok { scope, … payload from `bough --json …` }
```

Scopes (v1, nominal):

```text
node              by nanoid; full node + annotations + parent chain
recent_changes    transitions in a time window
active            current active tasks (optional workspace)
day               today's day_entry + linked items
week              current week
project_subtree   by project nanoid, depth-limited
```

Implementation: subprocess `bough --json --workspace <ws> <scope> …`,
parse JSON, return as plist. Standard timeouts and size caps.

(Write surfaces — `bough_propose_*` — are out of scope for the memory
design. When added, stage as proposals per [[satan-governance]].)

## 6. Persistence

### 6.1 Database

- Database: `satan_memory`
- Owner: `david`
- URL: `postgres:///satan_memory?host=/run/postgresql`
- No FDW or replication into bough in v1.

Migrations: numbered SQL files under
`~/.emacs.d/satan/memory/migrations/NNNN_<slug>.sql`. Forward-only,
additive where possible. Applied by `satan-memory-migrate`.

**R3 decided 2026-05-19: `psql` subprocess** for both migration runner
and runtime store. Verified `psql 18.4` at
`/run/current-system/sw/bin/psql`; socket auth at `/run/postgresql`
works as user `david`. Rationale:

- Migrations are already `.sql`; `psql -v ON_ERROR_STOP=1 -1 -f FILE`
  is a one-line invocation, atomically applied per file.
- No new emacs package or `home-manager switch` required.
- Matches surrounding shell-out pattern (`satan-tools-sway.el`,
  `satan-tools-bough.el`).
- Runtime throughput is human-paced (mark/resonate), so per-call
  subprocess latency (~20 ms) is invisible.
- Multi-step transactions live in SQL as PL/pgSQL functions
  (`memory_mark(...)` returning `trace_id`); elisp side stays a
  one-liner. Parameter binding via `psql -v key=value` + `:'key'`
  quoting handles LLM-supplied strings safely.

If runtime hot-path ever materializes (e.g. auto_rule writers), revisit
with an `emacsql-pg` backend behind the same `satan-memory-store`
interface.

Migration state is tracked in `schema_migrations` (§6.2). The runner
applies a version only when it equals `max(applied) + 1`, records the
file's SHA-256 checksum, and refuses to apply if a previously-applied
version's checksum has changed (post-apply edits are caught early).

### 6.2 Schema (v1)

```sql
-- ============================================================
-- bookkeeping
-- ============================================================

CREATE TABLE schema_migrations (
  version      INTEGER PRIMARY KEY,
  filename     TEXT NOT NULL,
  applied_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  checksum     TEXT NOT NULL
);

CREATE TABLE grammar_versions (
  version          SMALLINT PRIMARY KEY,
  introduced_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  notes            TEXT
);

-- ============================================================
-- traces
-- ============================================================

CREATE TABLE traces (
  id                      TEXT PRIMARY KEY,         -- "YYYYMMDDTHHMMSS-<6char>"
  kind                    TEXT NOT NULL CHECK (kind IN
                            ('observation','intervention','prediction','outcome')),
  trace_origin            TEXT NOT NULL CHECK (trace_origin IN
                            ('llm_mark','auto_rule','external')),
  source                  TEXT NOT NULL,            -- e.g. 'memory_mark@tick-pulse'
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  observed_start_at       TIMESTAMPTZ NOT NULL,
  observed_end_at         TIMESTAMPTZ NOT NULL,

  payload                 TEXT NOT NULL,            -- display only
  valence                 TEXT CHECK (valence IN
                            ('positive','negative','neutral','mixed','unknown')),
  outcome                 TEXT,                     -- closed-world outcome value, or NULL

  strength                DOUBLE PRECISION NOT NULL DEFAULT 1.0
                            CHECK (strength >= 0),
  base_strength           DOUBLE PRECISION NOT NULL DEFAULT 1.0
                            CHECK (base_strength >= 0),
  last_accessed_at        TIMESTAMPTZ,
  last_reinforced_at      TIMESTAMPTZ,
  access_count            INTEGER NOT NULL DEFAULT 0
                            CHECK (access_count >= 0),
  reinforcement_count     INTEGER NOT NULL DEFAULT 0
                            CHECK (reinforcement_count >= 0),

  schema_version          SMALLINT NOT NULL,
  grammar_version         SMALLINT NOT NULL REFERENCES grammar_versions(version),

  metadata_json           JSONB NOT NULL,           -- evidence + hints + ctx + truncation notes
  retention_json          JSONB NOT NULL DEFAULT '{"policy":"normal"}'::jsonb,

  CHECK (observed_start_at <= observed_end_at),
  CHECK (retention_json->>'policy' IN ('normal','ephemeral','pinned','audit'))
);

CREATE INDEX traces_kind_idx           ON traces(kind);
CREATE INDEX traces_origin_idx         ON traces(trace_origin);
CREATE INDEX traces_observed_end_idx   ON traces(observed_end_at DESC);
CREATE INDEX traces_strength_idx       ON traces(strength DESC);

-- ============================================================
-- handles (versioned for re-normalization)
-- ============================================================

CREATE TABLE trace_handles (
  trace_id          TEXT NOT NULL REFERENCES traces(id) ON DELETE CASCADE,
  grammar_version   SMALLINT NOT NULL REFERENCES grammar_versions(version),
  handle            TEXT NOT NULL
                    CHECK (handle ~ '^[a-z][a-z0-9_]*:[A-Za-z0-9][A-Za-z0-9_.+>-]*$'),
  source            JSONB NOT NULL,                 -- per-handle handle_source (§3.2)
  active            BOOLEAN NOT NULL DEFAULT TRUE,
  PRIMARY KEY (trace_id, grammar_version, handle)
);

-- retrieval index: only active rows participate in resonance
CREATE INDEX trace_handles_handle_active_idx
  ON trace_handles(handle)
  WHERE active;

CREATE INDEX trace_handles_trace_active_idx
  ON trace_handles(trace_id, grammar_version)
  WHERE active;

-- ============================================================
-- links
-- ============================================================

CREATE TABLE trace_links (
  trace_id        TEXT NOT NULL REFERENCES traces(id) ON DELETE CASCADE,
  relation        TEXT NOT NULL CHECK (relation IN
                    ('derived_from','supports','contradicts','supersedes')),
  target_trace_id TEXT NOT NULL REFERENCES traces(id) ON DELETE CASCADE,
  PRIMARY KEY (trace_id, relation, target_trace_id)
);

CREATE INDEX trace_links_target_idx    ON trace_links(target_trace_id);

-- ============================================================
-- grammar tables (versioned)
-- ============================================================

CREATE TABLE handle_aliases (
  alias             TEXT NOT NULL,
  canonical_handle  TEXT NOT NULL
                    CHECK (canonical_handle ~ '^[a-z][a-z0-9_]*:[A-Za-z0-9][A-Za-z0-9_.+>-]*$'),
  grammar_version   SMALLINT NOT NULL REFERENCES grammar_versions(version),
  PRIMARY KEY (alias, grammar_version)
);

CREATE TABLE handle_weights (
  namespace         TEXT NOT NULL,
  value             TEXT NOT NULL DEFAULT '__default__',
  weight            DOUBLE PRECISION NOT NULL,
  grammar_version   SMALLINT NOT NULL REFERENCES grammar_versions(version),
  PRIMARY KEY (namespace, value, grammar_version)
);
```

### 6.3 Mutable vs immutable

Immutable after write:

```text
traces:           id, kind, trace_origin, source, created_at,
                  observed_start_at, observed_end_at, payload,
                  metadata_json, schema_version, grammar_version
trace_handles:    (trace_id, grammar_version, handle) identity and
                  the `source` blob attached to each
trace_links:      full row
```

Mutable:

```text
traces:           strength, base_strength, last_accessed_at,
                  last_reinforced_at, access_count, reinforcement_count,
                  valence, outcome, retention_json, updated_at
trace_handles:    active (flipped by re-normalization)
```

Re-normalization after a grammar bump flips old rows to `active = FALSE`
and inserts new rows under the new `grammar_version`. The `traces` row
is not rewritten. Old handle rows remain for audit until an explicit
prune pass.

**Invariant** (enforced app-side, verified by acceptance test §9): if
`traces.outcome IS NOT NULL`, an active `trace_handles` row exists for
the same `trace_id` with `handle = 'outcome:<value>'` under the trace's
`grammar_version`.

### 6.4 Retrieval defaults (no policy lock-in)

Per brief §11:

```text
score(trace) =
    sum( weight(h) for h in active_handles(trace) ∩ cue_handles )
  * trace.strength
  * recency_decay(now - observed_end_at)
```

`active_handles(trace)` selects from `trace_handles` where
`active = TRUE` (current grammar version).

v1 defaults:

- `recency_decay` = identity (no decay).
- New traces have `strength = 1.0`, `base_strength = 1.0`.
- No decay daemon. Schema is decay-ready; *policy* is deferred per
  brief §17 and the addendum's non-bake list.
- **No automatic state mutation on read.** `memory_resonate` and
  `memory_show_trace` do not bump `access_count` or
  `last_accessed_at`; those columns stay at their defaults in v1.
  Explicit touch/reinforce surfaces (`memory_touch_traces`,
  `memory_reinforce`) are a v2 deliverable; the columns are admitted
  now so v2 needs no schema change.

### 6.5 Retention

`retention_json.policy ∈ {normal, ephemeral, pinned, audit}`. Default
`normal`. v1 has no eviction daemon — the schema admits one, the
policy is deferred.

## 7. Grammar versioning

`grammar_version` is a small integer. Every trace stores the version
that was current at write. Aliases and weights are also versioned.

Bumping a version:

1. Insert into `grammar_versions` with notes.
2. Insert/update rows in `handle_aliases` and `handle_weights` under
   the new version. Old rows stay.
3. Update `satan-memory-grammar.el` constants (the elisp-side
   closed-world enums) and the rule registry if rule semantics
   changed.
4. Optionally run `satan-memory-renormalize`: for each affected
   trace, replay `canonicalize(metadata_json.evidence,
   metadata_json.hints, ctx-replay)`, flip old `trace_handles` rows to
   `active = FALSE`, and insert new rows under the new version.

Re-normalization is a maintenance op, not a hot path. v1 ships with
the migration runner; the re-norm CLI command is a deliverable but
runs only on demand. The `handle_sources` JSON shape (§3.2) carries
`grammar_version` per handle, so audit queries can distinguish
"how was this handle assigned under v1?" from "how is it assigned
under v2?".

### 7.1 Alias-bump policy

- During development (pre-v1-ship): an alias addition that does not
  alter canonical handles for in-flight traces may be inserted under
  the current `grammar_version`.
- After v1 ships: **every alias addition or correction bumps
  `grammar_version`.** Cheap, auditable, replayable. Cost is one row
  in `grammar_versions` plus a re-norm pass on affected traces
  (idempotent).
- Removing an alias is always a bump.
- Adding or changing a closed-world value is always a bump.
- Adding a new namespace is always a bump.

## 8. Outcome scoring (light exploration; policy deferred)

This section is exploratory. The substrate must not foreclose this
mapping; the policy of when/how to score is **not** part of v1.

A `prediction` trace is shaped:

```text
kind:      prediction
handles:   ... + phase:* + transition handles + window-derived handles
payload:   "if uninterrupted, no artifact in 10 minutes"
metadata:  { predicted_at, window_for_outcome_min, expected_outcome }
```

When `predicted_at + window_for_outcome_min` elapses, a separate
scorer (cron, tick, or LLM call) compares observed state to expected.
State sources:

| outcome value          | derivation                                                              |
|------------------------|-------------------------------------------------------------------------|
| `produced_artifact`    | git HEAD changed, new file under cwd, or new `bough_event` in window    |
| `bough_progress`       | any `bough_status: todo→active` or `active→done` in window              |
| `returned_to_editing`  | panopticon focus_segment for editor surface after browser drift          |
| `continued_drift`      | panopticon focus stayed on non-editor surface throughout                |
| `abandoned_context`    | panopticon idle > N min, no return                                      |
| `unknown`              | none of the above                                                       |

The scorer writes an `outcome` trace (origin = `auto_rule`) with:

```text
links: [{ relation: 'supports'|'contradicts', target: <prediction_id> }]
```

Bough makes the first two derivations concrete instead of guesses.
This is the structural argument for why the substrate should be
designed with bough in view from day one, even though bough writes
remain out of scope.

Implementation: deferred. The schema admits all of the above with no
change.

### 8.1 v1 canon path: dormant by design

The substrate admits `kind = outcome` end-to-end:

- grammar v1 declares the `outcome` namespace closed-world with five
  values (`unknown`, `returned_to_editing`, `continued_drift`,
  `produced_artifact`, `abandoned_context`, `bough_progress`);
- `traces.kind` accepts `outcome`; `traces.outcome` accepts the same
  closed-world set;
- §9.12 invariant is enforced server-side
  (`memory_mark_trace`, migration `0003`) — any trace with
  `traces.outcome IS NOT NULL` must carry a matching
  `outcome:<value>` row in `trace_handles`.

What v1 deliberately does **not** ship:

- **No canon rule emits an `outcome:<value>` handle.** The
  canonicalizer passes `hints.outcome_for` (a prediction trace_id)
  through to `:normalized`, but there is no `hint.outcome` rule and
  the `memory_mark` tool-schema does not expose an `outcome` hint
  field. An LLM cannot produce an outcome trace via `memory_mark`.
- **The `memory_mark` handler never forwards `:outcome` to
  `satan-memory-store-mark`.** Trace origin is hard-wired to
  `llm_mark`; the store-mark `:outcome` keyword is exercised only
  by direct callers (today: the integration tests for §9.12).

Rationale: outcome traces belong to the **scorer** lane
(`trace_origin = auto_rule`), not the LLM lane. The scorer reads
prior `prediction` traces, observes the window described above
(git HEAD, bough events, panopticon focus), and emits the matched
`outcome` trace. Letting the LLM self-report outcomes would
collapse the prediction/scoring split this section is built around
and create an unverifiable feedback channel.

Waking the canon path is a v2 task and arrives bundled with the
scorer itself: add a `hint.outcome` canon rule, expose `outcome`
on the `memory_mark` hints shape (or a new `outcome_mark` tool),
and plumb `:outcome` through the handler. Until then the
server-side invariant is load-bearing future-proofing, not dead
code.

## 9. Acceptance criteria

A v1 implementation is acceptable when:

1. The canonicalizer converts each fixture `(evidence, hints, ctx)`
   into the expected handles + `handle_sources` (golden tests).
2. Unknown closed-world hint values are rejected with an alias
   suggestion list.
3. `memory_mark` persists `traces`, `trace_handles`, and any
   `trace_links` in one transaction. Typical handle count: 5–12.
4. `memory_resonate` returns matches by inverted-index lookup, scored,
   sorted, with `matched_handles` populated, and a `cue_handles` echo.
   No state mutation occurs.
5. `memory_show_trace` round-trips a trace including provenance.
   No state mutation occurs.
6. `bough_read` returns plausible output for each scope on a populated
   `bough_production`.
7. Re-running `memory_mark` with the same fixture inputs produces the
   same handles.
8. A grammar bump + `satan-memory-renormalize` flips old
   `trace_handles` rows to `active = FALSE` and inserts new rows under
   the new `grammar_version`. The trace row is untouched.
9. The migration runner applies numbered SQL forward-only; refuses to
   skip versions; refuses to apply when a recorded checksum no longer
   matches the file.
10. No code path in `satan-memory-*` reads any bough database
    directly — only via the `bough_read` tool surface (grep lint
    enforced).
11. Two traces matching only on `bough_node:<nanoid>` rank strictly
    below any trace matching on a non-zero-weight handle. (Zero-weight
    handles preserve audit/show value without dominating score.)
12. **Outcome invariant:** for any trace where
    `traces.outcome IS NOT NULL`, an active `trace_handles` row exists
    with `handle = 'outcome:<value>'` under the trace's
    `grammar_version`. Enforced app-side; verified by integration
    test.
13. **Canonicalizer purity:** the canonicalizer module does not
    reference `bough`, `shell-command`, `call-process`,
    `insert-file-contents`, `url-retrieve`, `current-time`, or any IO/
    network primitive. Enforced by grep-lint test (§3.5).
14. **Origin admission:** the `traces.trace_origin` column accepts
    `auto_rule` and `external` without schema change; a test fixture
    inserts one of each and verifies retrieval works.

## 10. Open questions

### 10.1 Hints — `topic` cardinality (LOCKED)
`topic` is an array of slugs. Max 5 per mark. Deduplicated after
normalization. Empty array equivalent to omission. Slug regex
`^[a-z0-9][a-z0-9_-]*$`.

### 10.2 Bough CLI scopes

Discovered against `bough 0.1.0` (binary `/home/david/.cargo/bin/bough`)
on 2026-05-19. Pin this binary path in `satan-tools-bough.el`
defcustom; fail-fast on shape drift (R2). Sample-output integration
fixture goes in `test/bough-fixtures/`.

Status legend: **exists** = single invocation; **composable** = N>1
invocations or in-elisp post-filter; **degraded** = capability missing,
ship loosened semantics in v1 and file a bough issue.

| Design scope (§5.4) | Status | Invocation(s) | Notes |
|---------------------|--------|---------------|-------|
| `node`             | composable | `bough --json node get NANOID` + `bough --json node annotations NANOID` + walk `parent_nanoid` upward via repeated `node get` until `null` | `node get` returns the node with `parent_nanoid` but no chain and no annotations. Compose all three in `satan-tools-bough.el`; cache chain walk per call. |
| `recent_changes`   | composable | `bough --json node status-transitions --since <SINCE>` + `bough --json node created --since <SINCE>` (DR-116) | Peer event feeds: status transitions (`{seq, nanoid, from_status, to_status, at, actor}`) and newly-created nodes. Evidence assembler synthesizes `:event "status_changed"` / `:event "created"` rows for canon. **Bough gap B1 closed 2026-05-21**. |
| `active`           | exists     | `bough --json node tree --kind task --status doing,todo,blocked` | Comma-separated `--status` confirmed. Add `--workspace` passthrough. |
| `day`              | exists     | `bough --json day show -d YYYY-MM-DD` | Returns `error: day not found` when no day entry exists; tool wrapper must translate to `ok { scope:"day", day:null }` rather than error. |
| `week`             | composable | `bough --json day list <MONDAY> <SUNDAY>` followed by per-non-empty-day `bough --json day show -d <D>` | No `bough week` subcommand. `day list` returns the date set; iterate for entries. |
| `project_subtree`  | degraded   | `bough --json node subtree NANOID` + elisp post-filter to `max_depth` | `node subtree` has no `--max-depth N` flag. Fetch full subtree, prune in `satan-tools-bough.el` against design-default depth (e.g. 3). **Bough gap B2**. |

Bough-side issues to file (do not block v1):

- ~~**B1**~~ Closed 2026-05-21 by bough DR-116: `node status-transitions`
  + `node created` shipped. SATAN's `recent_changes` scope consumes
  both peer feeds directly; assembler synthesizes
  `:event "status_changed"` / `:event "created"` rows.
- **B2**. Add `--max-depth N` to `bough node subtree`. v1 prunes in
  elisp.

Decision tree per R1 followed: gap → degrade scope to loosened
semantics in v1 + file bough issue, do **not** write parallel read
logic against the bough DB (B1 of [[satan-governance]] enforced by grep-lint).

This unblocks step 3 (`bough_read` tool wrapper).

### 10.3 Re-normalization cost
For N traces of ~16 KB `metadata_json`, a full re-norm is N canonicalizer
runs + N×|handles| row rewrites. Acceptable up to ~10⁴ traces.
Incremental re-norm (only rules whose semantics changed) is a v2
optimization.

### 10.4 Cross-DB joins
B1 forbids cross-DB joins in v1. If a recurring need to "resonate
where `bough_node` is currently active" appears, the cleanest fix is a
small materialized mirror in `satan_memory.bough_mirror_*` populated
**via `bough_read`** (no parallel read logic; CLI is still the
source). `postgres_fdw` is a possible alternative but couples
lifecycles. Defer until needed.

### 10.5 Touch and reinforcement
v1 has no `memory_touch_traces` or `memory_reinforce`. Open: should
retrieval hits be marked via an explicit touch tool, or only when the
LLM has "actually used" the memory (e.g. cited it in a subsequent
output)? **Lean explicit touch by the LLM** — keeps noise low and
lookups idempotent. Revisit when behavioural data exists.

### 10.6 Payload privacy
`payload` is LLM-authored prose. Should the substrate redact known
sensitive substrings (passwords, tokens) on write? Probably yes,
trivially (regex), with the pattern list living notes-side. Out of
scope for substrate design; raise during implementation.

### 10.7 Hippocampus coexistence
The existing `hippocampus_write` writes prose org files. Open: should
hippocampus writes also emit an `observation` trace pointing at the
hippocampus file (`metadata.hippocampus_path`)? Cheap, valuable
cross-reference. **Lean yes**, as a v1 hook in
`satan-tools-hippocampus.el`.

### 10.8 Source gaps
Some grammar values currently have no emitter:
- `event:command_error`, `event:command_ok`, and the
  `event_transition:command_error->*` family — panopticon does not
  observe terminal exit codes. Requires a new capture source (shell
  hook, ghostty integration, or eat/vterm advice). Future panopticon
  scope.
- `idle_begin` / `idle_end` — panopticon has an `idle` signal in the
  Firefox extension; sway-side idle is TBD.
These values are admitted now to keep the grammar stable.

### 10.9 Auto-marker first targets
With `trace_origin = 'auto_rule'` admitted, the obvious first
deterministic markers are:
- bough status change to `done` → emit observation with
  `bough_event:status_changed`, `artifact:bough_status_change`,
  the affected `bough_node:<nanoid>`.
- explicit user keystroke ("mark this moment") via an Emacs command.
- editor compile/test failure if a clean hook exists.
None are v1 scope; documented so the substrate's first non-LLM
producers are anticipated.

## 11. File layout

```text
~/.emacs.d/satan/
  satan-memory.el                   aggregator + satan-memory-* commands
  satan-memory-grammar.el           closed-world enums; alias seed; weight defaults
  satan-memory-canon.el             canonicalizer; rule registry (PURE)
  satan-memory-evidence.el          evidence-window assembly (panopticon + bough_read + git/fs)
  satan-memory-store.el             DB connection; mark/resonate/show backend
  satan-memory-migrate.el           migration runner; renormalize CLI
  satan-tools-memory.el             tool handlers: memory_mark, memory_resonate, memory_show_trace
  satan-tools-bough.el              bough_read tool (shell-out)
  memory/migrations/0001_init.sql      initial schema (tables in §6.2)
  memory/migrations/0002_grammar_v1.sql initial grammar_versions row + aliases + weights
  test/satan-memory-test.el         unit + canon-fixture golden tests + purity grep-lint
  test/canon-fixtures/                 JSON fixtures
~/notes/satan/tools/
  memory_mark.md
  memory_resonate.md
  memory_show_trace.md
  bough_read.md
```

Naming follows [docs/emacs/naming.md](../../emacs/naming.md): module symbols `satan-memory-*`, public
internals `satan-memory-<name>`, private `satan-memory--<name>`,
user commands `satan-memory-*`.

---

### What's locked

- Decisions (§0), schema (§6.2), tool surface (§5), canonicalizer
  interface (§3) including purity boundary, grammar shape (§2)
  including handle syntax, file layout (§11).

### What's deliberately not locked (policy, deferred)

- Decay formula, scoring weights beyond the listed defaults, demon /
  hypothesis taxonomy, intervention policy, bias-into-prompt
  mechanism, bough write surfaces, automatic outcome scoring, payload
  redaction policy, eviction policy, auto-marker rule set.
