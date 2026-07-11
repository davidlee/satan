---
name: satan-data-collection
description: Complete inventory of SATAN's data-collection and context-influence mechanisms — what feeds into its prompt, what reads environment state, what writes persistent memory, and the influence surfaces that shape future context
metadata:
  type: reference
  topic: satan
  status: living
  updated_at: 2026-05-23
  verified_at: 2026-05-23
---

# SATAN — Data Collection & Context Influence

Every SATAN run begins with an assembled prompt bundle and ends with
persistent effects. This document catalogues both sides: **inputs**
(what data reaches the model) and **influence** (how the model or user
shapes future context). It complements the mode-spec table in
[governance.md](governance.md) and the memory-substrate design in
[memory/design.md](memory/design.md).

---

## 1. Anatomy of one run

A run is a harness-mediated conversation between the broker (Emacs) and
a model, bounded by a mode spec. The model receives:

1. A **system prompt** assembled from:
   - `~/notes/satan/system/scaffold.txt` (shared behavioural framing)
   - `~/notes/satan/prompts/<MODE>.txt` (mode-specific instruction)
   - Section headers from `~/notes/satan/system/framing.txt`
   - Rendered `# Now` block (date/time/tz)
   - For `morning`: `# Today (raw)` block (today's note content)
   - For `tick-*`: `# Recent SATAN runs` block (last N runs)
   - For `self-edit-*`: `# Source files` block (source code + prompts,
     capped at 600K chars)

2. A **tool manifest** with JSON Schema for every allowed tool.
   Each tool's model-facing description is loaded from
   `~/notes/satan/tools/<tool-name>.md` (mind side).

3. **Tool-call results** inserted mid-conversation as the model invokes
   tools. These return live data from the environment — they are the
   primary input channel.

The model's output is either a `satan_final` terminal call (with
`summary` + `actions[]`) or a force-termination (budget/no-tool-calls).
The broker then validates, partitions, and applies actions per the
mode's `auto-apply` policy.

---

## 2. Static context (injected at run start)

These are baked into the prompt bundle before the model takes its first
turn.

### 2.1 System scaffold

**Source:** `~/notes/satan/system/scaffold.txt`
**Injected by:** `satan-context--assemble-prompt`
**Content:** Core behavioural framing — write boundaries, interruption
policy, memory model, tool discipline, protocol rules. Load-bearing
for every mode.
**Control:** User edits the file; self-edit modes can propose changes.

### 2.2 Mode prompt

**Source:** `~/notes/satan/prompts/<mode>.txt`
**Injected by:** `satan-context--assemble-prompt`
**Content:** Mode-specific instruction — what to do, in what order,
with which tools.
**Control:** Per-mode file; self-edit-mind lane can propose changes.

### 2.3 Section headers (framing)

**Source:** `~/notes/satan/system/framing.txt`
**Injected by:** `satan-context--render-prompt`
**Content:** Key=value pairs like `now=# Now`, `today=# Today (raw)`,
`sources=# Source files`. These label the context blocks the broker
appends after the scaffold + prompt.
**Control:** User edits the file.

### 2.4 Now block

**Source:** `satan-context-now` (wall clock)
**Injected by:** `satan-context--render-now`
**Content:** ISO date, weekday, ISO week, time, timezone offset and
name. Every bundle includes this.
**Control:** Clock only; the user cannot influence this directly
(short of changing the system clock or TZ).

### 2.5 Today block (morning mode)

**Source:** Today's journal org file at `~/notes/journal/<date>.org`
**Injected by:** `satan-context-morning`
**Content:** The raw text of today's daily note. This is the user's
own writing from the current day.
**Control:** User writes in their journal file.

### 2.6 Source files block (self-edit modes)

**Source:** All tracked files under `~/.emacs.d/satan/` (mech) or
`~/notes/satan/{prompts,system,tools}/` (mind), capped at 600K chars.
**Injected by:** `satan-context-self-edit`
**Content:** Full file contents packed alphabetically until budget
exhausted. Overflow listed in `:dropped-files`.
**Control:** User edits files; the droppage budget is configurable via
`satan-self-edit-bundle-char-budget`.

### 2.7 Recent SATAN runs block (tick modes)

**Source:** `~/notes/satan/runs/<YYYY-MM-DD>/<run-id>/final.json` +
`transcript.jsonl`
**Injected by:** `satan-context--recent-runs`
**Content:** The N most recent runs (default 5), newest-first. Each:
timestamp, mode, status, summary clipped to 280 chars, tool-call tally.
Includes failed runs. Cross-mode visibility — a `morning` run appears
in a `tick-pulse` context and vice versa.
**Control:** Runs are append-only artifacts; the mode-spec `:recent-runs
N` key controls presence (tick modes default to 5; other modes omit).
No user-facing kill switch beyond setting the key nil.

---

## 3. Dynamic context (tool-call-time reads)

These are retrieved live when the model invokes a read-only tool. Each
is described by handler and by model-facing description
(`~/notes/satan/tools/<tool>.md`).

### 3.1 `org_read_context`

| Scope | Source | What comes through |
|-------|--------|--------------------|
| `today` | `~/notes/journal/<date>.org` | Today's full note body |
| `week` | `~/notes/weekly/<week-file>.org` | Current week's file |
| `inbox` | `~/notes/inbox.org` | User's global inbox |

**Risk:** read. Available to: morning, motd, tick-*, self-edit-*.
**Control:** User writes in those files.

### 3.2 `activity_read`

| Scope | Source | What comes through |
|-------|--------|--------------------|
| `today` | `~/.local/state/behaviour/histograms/daily-<date>.json` | Per-app/second/workspace/hour aggregates |
| `recent_focus` | `~/.local/state/behaviour/segments/focus-<date>.jsonl` | Last N focus segments (app, workspace, start/end, duration) |
| `recent_browser` | `~/.local/state/behaviour/segments/browser-<date>.jsonl` | Last N browser segments (origin stripped to host, start/end, duration) |
| `current` | `~/.local/state/behaviour/current/sway.json` | Live snapshot: app_id, workspace, output, title, pid |

**Risk:** read. Available to: morning, motd, tick-pulse.
**Producer:** panopticon (`~/dev/panopticon`) — sway watcher + Firefox
extension + segmentizer. PII redacted at source (URLs → origin,
incognito dropped).
**Control:** The user influences this by changing focus and opening
tabs. No direct kill switch; stopping panopticon's systemd units
halts data production.

### 3.3 `agenda_read`

**Source:** gcalcli (network), calendar id from `$WORK_EMAIL` env var.
**What comes through:** Plain-text agenda listing, default 5-day window.
**Risk:** read. Available to: morning, motd.
**Control:** User edits the calendar and manages gcalcli OAuth.

### 3.4 `bough_read`

| Scope | Source | What comes through |
|-------|--------|--------------------|
| `node` | `bough --json node get <nanoid>` + `annotations` + `parent` walk | Full node + annotations + parent chain |
| `recent_changes` | `bough --json node status-transitions --since` + `node created --since` | Status transitions + newly-created nodes (DR-116) |
| `active` | `bough --json node tree --kind task --status doing,todo,blocked` | Active task tree (elisp-flattened) |
| `day` | `bough --json day show -d <date>` | Day entry + linked items |
| `week` | `bough --json day list Mon Sun` → per-day `day show` | Week data (composed) |
| `project_subtree` | `bough --json node subtree <nanoid>` (elisp-pruned to depth 3) | Project tree, truncated |

**Risk:** read. Available to: all modes.
**Producer:** bough (Rust CLI at `~/.cargo/bin/bough`).
**Control:** User manages tasks in bough. This is SATAN's **only** path
into bough data — no direct PG access.

### 3.5 `notes_recent`

**Source:** `fd --changed-after N hours` over `~/notes/`, excludes `satan/`.
**What comes through:** Recently-modified files under the notes corpus,
with denote-style title/tag parsing. Newest-first, capped at 200.
**Risk:** read. Available to: morning, motd, tick-pulse.
**Control:** User edits files.

### 3.6 `notes_at_satan_scan`

**Source:** `rg --json --fixed-strings @satan` over `~/notes/`,
excludes `satan/**`.
**What comes through:** Every `@satan` directive not yet claimed, with
surrounding context lines, headline, and stable session id.
**Risk:** read. Available to: morning, tick-agent.
**Control:** User writes `@satan` directives in their notes. Claimed
directives (bearing `@satan-was-here`) are excluded from results.
This is the **only** way SATAN reads user-authored directives.

### 3.7 `docs_list` / `docs_search` / `docs_read`

**Source:** Frontmatter-stamped `.md` files under
`~/.emacs.d/docs/satan/` and `~/.emacs.d/docs/emacs/`.
**What comes through:** Doc chunk metadata and bodies.
**Risk:** read. Available to: all modes.
**Control:** SATAN documentation is maintained by commit.

### 3.8 `memory_resonate` / `memory_show_trace`

**Source:** PostgreSQL `satan_memory` database, via `psql` subprocess.
**What comes through:** Inverted-index lookup over prior trace handles.
Returns scored matches with matched handles.
**Risk:** read. Available to: all modes.
**Control:** Prior `memory_mark` calls populated the substrate. The
model cannot directly influence the canonicalizer (it is deterministic,
broker-side).

### 3.9 `motive_read`

**Source:** `~/notes/satan/motives.org` parsed via `satan-motive-parse`.
**What comes through:** Whole motive file — active motives with prose,
`:cue:` handles, `:cooldown_s:`, `:worked_count:`, `:last_intervention_at:`,
optional `:project_cwd:`, plus background ruminations (≤10 lines).
**Risk:** read. Available to: tick-* (motives also auto-render into
the tick capsule via broker §S3, so the model rarely needs to ask).
**Control:** User edits motives.org directly; SATAN edits it via
`motive_replace` (model) or the observer footer rewriter (broker, §4.12).
Cooling-down motives render in the capsule with a
`[cooling-down (Nm remaining)]` header annotation per
[[satan-perceptual-design]] §S4 + Phase 6.

---

## 4. Write surfaces (environment influence)

These are how the model changes durable state — both its own future
context and the user's environment.

### 4.1 `hippocampus_write` (memory via org files)

| Property | Value |
|----------|-------|
| **Risk** | low |
| **Capability** | `hippocampus-write` |
| **Auto-apply** | yes (SATAN-owned dir) |
| **Target** | `~/notes/satan/hippocampus/<id>--<slug>__satan_hippocampus.org` |
| **Effect** | Curated prose org file, denote-named |
| **Side effect** | When the mode also holds `memory-write`, emits an `auto_rule` observation trace cross-referencing the file path. |

These are re-read in future runs only if a tool inspects the directory
(no current tool does — the cross-ref trace is the retrieval path).

### 4.2 `memory_mark` (structured trace substrate)

| Property | Value |
|----------|-------|
| **Risk** | low |
| **Capability** | `memory-write` |
| **Auto-apply** | yes |
| **Target** | PostgreSQL `satan_memory.traces` + `trace_handles` |
| **Effect** | Persists an `observation` (or other kind) trace with canonical handles, evidence window, LLM hints, metadata |
| **Side effect** | Future `memory_resonate` calls will match against these handles |

This is SATAN's primary mechanism for **influencing its own future
context**. The model writes a trace; future runs reply on handle
collision. The canonicalizer is deterministic (broker-side), so the
model can only influence *what* to mark via typed hints (phase, topic,
valence, focal_app, focal_bough_nanoid, outcome_for, kind) — not the
actual handles or evidence.

### 4.3 `inbox_append` (local inbox)

| Property | Value |
|----------|-------|
| **Risk** | low |
| **Capability** | `inbox-write` |
| **Auto-apply** | yes |
| **Target** | `~/notes/satan/inbox.org` |
| **Effect** | Appends an org headline tagged `:unread:satan:` |

Data written here is re-read by `org_read_context` (inbox scope) and
`notes_recent` (fd picks up the mtime change). This is the model's
main communication channel to the user — preferred over `notify_send`.

### 4.4 `notify_send` (desktop notification)

| Property | Value |
|----------|-------|
| **Risk** | low |
| **Capability** | `notify` |
| **Auto-apply** | yes |
| **Target** | D-Bus notification daemon |
| **Effect** | Popup notification visible to the user immediately |

Ephemeral — no durable state, but directly interrupts the user.
Policy prefers `inbox_append` over `notify_send`.

### 4.5 `org_update_owned_block` (daily note)

| Property | Value |
|----------|-------|
| **Risk** | low |
| **Capability** | `write-daily` |
| **Auto-apply** | morning mode only |
| **Target** | Today's journal file's `#+begin_satan` block |
| **Effect** | Replaces the SATAN-owned block with new content |

This is the daily-plan surface. Re-read by the next run's `today`
context.

### 4.6 `proposal_stage`

| Property | Value |
|----------|-------|
| **Risk** | low |
| **Capability** | `stage-proposal` |
| **Auto-apply** | no (stages for review) |
| **Target** | `~/notes/satan/proposals/<id>--<slug>__satan_proposal.org` |
| **Effect** | Writes a denote-named proposal file |

These never feed into the model's context automatically. The user must
explicitly act on them. No tool re-reads the proposals dir.

### 4.7 `satan_final` (terminal output)

| Property | Value |
|----------|-------|
| **Risk** | internal |
| **Auto-apply** | by output handler per mode |
| **Effect** | `summary` → written to `final.json` (audit) + dispatches output handler |

The output handler may write the summary to `motd.txt` (motd mode),
insert it into the daily block (morning mode), or just archive it
(tick modes). The `final.json` summary populates the `# Recent SATAN
runs` block for future tick runs, which means **the model's own
summary influences its future context** indirectly through the
recent-runs block.

### 4.8 `sway_border_set` / `sway_border_reset`

| Property | Value |
|----------|-------|
| **Risk** | medium |
| **Capability** | none (mode-gated) |
| **Effect** | Changes sway window-border colours; reset does `swaymsg reload` |

Ephemeral visual effect. No durable state. Not a feed-forward mechanism
for future context.

### 4.9 `notes_at_satan_done`

| Property | Value |
|----------|-------|
| **Risk** | low |
| **Capability** | `write-notes` |
| **Auto-apply** | yes |
| **Target** | User's note file containing `@satan` |
| **Effect** | Replaces `@satan` with `@satan-was-here` + quoted run-id/comment block |

Claims a directive so it won't appear in future `notes_at_satan_scan`
results. This is SATAN's way of preventing re-processing. The
`@satan-was-here` marker is persistent and grep-able.

### 4.10 `patch_job_create` / `patch_job_cancel` / `patch_job_cleanup`

| Property | Value |
|----------|-------|
| **Risk** | low/medium |
| **Capability** | `patch-job-create`, `patch-job-cancel`, `patch-job-cleanup` |
| **Target** | PostgreSQL `satan_patch.patch_jobs` table + git worktree on disk |
| **Effect** | Create/cancel/cleanup a patch job: a git worktree + branch for isolated edits |

Jobs produce branches the user can cherry-pick or merge. The model
cannot auto-apply patch results — only the user can accept them via
git. This is SATAN's escape valve for multi-file edits it should not
perform inline.

### 4.11 `motive_replace` (motive file rewrite, model-driven)

| Property | Value |
|----------|-------|
| **Risk** | low |
| **Capability** | `motive-write` |
| **Auto-apply** | yes |
| **Target** | `~/notes/satan/motives.org` (+ `motives.archive.org` on demote) |
| **Effect** | Atomic full-file replace; broker validates ≤3 active motives, ≤10 ruminations, `:cue:` syntax + sensor-observed-handle requirement, rejects `:ceiling:` |
| **Side effect** | Next tick's motive block in the capsule reflects the new state |

The model authors prose and `:cue:` lines. The broker is the only
writer of `:worked_count:` and `:last_intervention_at:` (see §4.12).
The broker's `motive_replace` handler preserves footer fields it owns
when the model omits them, refuses to accept model-supplied values for
those fields when they differ from the canonical state, and rejects
the call entirely on bound breach.

### 4.12 Observer verdict (broker-side, post-window-mature)

Not a model tool. Broker module `satan-observer.el` (Phase 5) runs
in `satan-broker--spawn` before percept-build, scans the prior 24h
of `transcript.jsonl` files for interventions whose 30-min attribution
window has matured (`satan-observer-window-mature-seconds`,
default 1800), classifies each per [[satan-perceptual-design]] §S5
predicate, and on a positive verdict triggers three writes via
`satan-observer-persist-verdict`:

| Write | Surface | Effect |
|---|---|---|
| Motive footer touch | `~/notes/satan/motives.org` via `satan-motive-touch-footer` | `:worked_count:` increment + `:last_intervention_at:` ISO bump; prose, ruminations, other footer fields preserved verbatim; atomic tmp + rename |
| Memory trace | `satan_memory.traces` (kind `observation`, origin `auto_rule`) via `satan-memory-store-mark` | Records run_id, applied_index, motive_id, predicate metadata; future `memory_resonate` calls can surface it |
| Dedup mark | observer state file (`~/.local/state/satan/observer.json`) | Per-intervention-id mark prevents double-count across ticks; written last so partial failures retry |

Negative verdicts write only the dedup mark — absence of a positive
trace is the only negative signal v0 records. The model cannot author
these writes directly; only the deterministic broker-side classifier
fires them.

### 4.13 Sensor alerts (broker-side, pre-model-turn)

Not a model tool. Broker module `satan-sensor-alerts.el` (Phase 4)
runs in `satan-broker--prepare` after evidence assembly, evaluates
the freshness thresholds in [[satan-perceptual-design]] §S6, and on a
fire dispatches through the **same `notify_send` tool handler** the
model uses (so capability checks + audit apply). Every fire AND every
suppression is recorded in `actions.json.pre_spawn` as a `sensor_alert`
entry (`{kind, cause, severity, message, remediation, suppressed?,
dispatched_at?}`). Per-cause cooldown (default 24h) and quiet-hours
suppression live in `~/.local/state/satan/notified.json`. Audit
verifier requires a one-to-one correspondence between `notified.json`
entries this run and `actions.json.pre_spawn` entries (acceptance A16).

---

## 5. Memory substrate (future-context engine)

The memory substrate at `satan_memory` (PostgreSQL) is the primary
cross-run persistence layer. Here is how data flows in and out:

### 5.1 Write path (→ substrate)

| Source | Handler | `trace_origin` | Frequency |
|--------|---------|----------------|-----------|
| `memory_mark` tool call | `satan-tool/memory-mark` | `llm_mark` | Per-run, on demand |
| `hippocampus_write` cross-ref hook | `satan-tools-hippocampus--cross-ref` | `auto_rule` | Per hippocampus write |
| Auto-rule writers (future) | TBD | `auto_rule` | TBD |

The canonicalizer (§3 of memory/design.md) is a pure function running
in the broker. The model supplies typed hints; the broker turns those
+ the evidence window into canonical handles. The model **cannot**
directly author handles.

### 5.2 Read path (← substrate)

| Tool | Mechanism | Used in |
|------|-----------|---------|
| `memory_resonate` | Inverted-index: weight × strength × recency | All modes |
| `memory_show_trace` | Round-trip by trace id | All modes |

Resonance results are injected mid-conversation as tool-call results,
not into the system prompt. The model decides whether to query memory;
it is not forced into every turn.

### 5.3 Grammar versioning

When handles, aliases, or weights change (grammar bump), existing
traces are re-normalizable from stored metadata. The `grammar_version`
column on every trace + handle row makes this possible without data
loss.

### 5.4 Evidence window

Every `memory_mark` captures an evidence snapshot:
- Current window (sway focus)
- Focus segments (last 10, window-bounded)
- Browser segments (last 10, window-bounded)
- Bough recent changes (last 50)
- Bough active tasks
- Bough day entry
- Git state (HEAD short, remote, dirty flag, last 5 commits)
- FS state (cwd, recently-edited files via `recentf`)

Truncated deterministically from ~16 KB target to 64 KB hard cap. The
evidence is stored in `metadata_json` so future grammar bumps can
replay the canonicalizer.

---

## 6. Typing speed analytics (unconsumed)

Added 2026-05-21. Not yet consumed by any SATAN mode, tool, or prompt.
Discovered in the notes tree at:

```
~/notes/satan/log/wpm/
  2026-05-21.tsv
  2026-05-22.tsv
```

### 6.1 Data format

**Pre-2026-05-22 (5 columns, tab-separated):**
```
tsv columns:  timestamp  total_chars  total_keystrokes  total_seconds  peak_wpm
```

**2026-05-22 onward (4 columns, tab-separated):**
```
tsv columns:  timestamp  raw_wpm  net_wpm  accuracy_pct
```

Minute-granularity timestamps (~100 rows/day for active periods).
Today's file is 2026-05-22 at ~3 KB, growing.

### 6.2 Producer

Unknown (not under this workspace). Presumably an Emacs hook, a systemd
timer, or a standalone binary that reads keystroke events. The data is
emitted to this path at regular intervals.

### 6.3 Consumption status

**Not consumed.** No SATAN mode prompt references it, no tool reads it,
no memory rule canonicalizer rules handle it. It sits in the notes tree
alongside other data (like the activity histogram) that SATAN could
read if a tool and a prompt directive were added.

### 6.4 Integration surface

To consume it, a simple tool (e.g. `activity_read_typing`) would read
the TSV aggressively into a histogram or summary shape. The existing
`activity_read` pattern (scope-enum, file-backed, read-only, risk read)
is the natural model.

---

## 7. Passive data feed (environmental sensors not tool-mediated)

These are written by external processes and could be consumed by SATAN
tools but currently sit as raw files:

| Source | Path | Producer | Current SATAN consumption |
|--------|------|----------|---------------------------|
| Behaviour focus segments | `~/.local/state/behaviour/segments/focus-<date>.jsonl` | panopticon | Via `activity_read` |
| Behaviour browser segments | `~/.local/state/behaviour/segments/browser-<date>.jsonl` | panopticon | Via `activity_read` |
| Behaviour histograms | `~/.local/state/behaviour/histograms/daily-<date>.json` | panopticon | Via `activity_read` |
| Current sway window | `~/.local/state/behaviour/current/sway.json` | panopticon | Via `activity_read` |
| **Typing speed** | `~/notes/satan/log/wpm/<date>.tsv` | Unknown | **None** |
| Bough DB | PostgreSQL `bough_production` | bough daemon | Via `bough --json` CLI (no direct PG access) |
| Memory substrate | PostgreSQL `satan_memory` | SATAN itself | Via `psql` subprocess |

---

## 8. Influence chains (how context feeds back)

### 8.1 Immediate feed-forward — recent runs

```
run N (morning) writes summary → final.json → 
  run N+1 (tick-pulse) reads recent-runs block → 
    model sees its own prior summary
```

This is the tightest feedback loop: a model's summary from one run
appears as context to the next. Clipped to 280 chars. The mode-spec
`:recent-runs N` key controls which modes see this.

### 8.2 Memory resonance

```
run N calls memory_mark → trace in satan_memory →
  run N+1 calls memory_resonate → returns match →
    model sees the prior trace's handles + payload
```

The model must explicitly call `memory_resonate` — there is no
automatic injection of top-k matches into system prompts (v1
policy). The cue can be automatic (derived from the current evidence
window) or explicit (model-provided handles/hints).

### 8.3 Hippocampus cross-ref

```
hippocampus_write(title, body) → org file + auto_rule trace →
  memory_resonate may surface that trace →
    model sees "hippocampus entry: <title>" in recall
```

The cross-ref trace carries the hippocampus file path in metadata,
but no tool currently follows that link to re-read the org file.

### 8.4 Inbox re-read

```
inbox_append → ~/notes/satan/inbox.org grows →
  next run's org_read_context(scope=inbox) includes it →
    or notes_recent surfaces it by mtime
```

### 8.5 Owned block re-read

```
org_update_owned_block → today's journal file changes →
  next run's org_read_context(scope=today) includes it →
    or the # Today (raw) block (morning) includes it
```

### 8.6 `@satan` directive cycle

```
user writes @satan in note →
  notes_at_satan_scan surfaces it →
    model acts + calls notes_at_satan_done →
      file now bears @satan-was-here →
        next scan excludes it
```

### 8.7 Observer → motive → capsule loop (Phase 5 + 6)

The newest feedback chain. Entirely broker-side; the model never
authors it.

```
run N: model emits intervention (notify_send / inbox_append / …) →
  transcript.jsonl persists intervention_emitted_at + cue handles →
run N+k: observer at start of next spawn scans prior 24h →
  intervention's 30-min window has matured →
    observer.classify-for-motives intersects intervention's percept
    handles ∩ each active motive's :cue: handles →
      positive predicate fires (file edit under :project_cwd:, git
      HEAD delta, mtime delta, or bough_event) →
        observer.persist-verdict:
          1. motive footer :worked_count: increment + :last_intervention_at: ISO
          2. observation/auto_rule trace into satan_memory
          3. dedup mark into observer.json
→ same spawn's percept-build / motive-read reads the just-updated
  footer →
    broker pre-capsule cooldown check (Phase 6) flips motives in
    cooldown to read-only [cooling-down (Nm remaining)] in the
    capsule →
      model sees updated worked_count + cooling-down state
```

Net effect: a successful intervention this run dampens the same
motive's pressure on the next tick (cooldown floor) AND surfaces as a
prior trace for future `memory_resonate` calls. No live loop, no
callbacks, no LLM in the path — the same frozen `time_now` carried in
`run_ctx` gates window-mature and cooldown-remaining symmetrically.

---

## 9. Collectors that do NOT feed future context

These write to durable state that is never re-read by any tool:

| Surface | Written by | Re-read by |
|---------|-----------|------------|
| `~/notes/satan/proposals/` | `proposal_stage` | Nothing (user reads manually) |
| `motd.txt` | `satan_final` summary in motd mode | Nothing (intended for user display) |
| D-Bus notifications | `notify_send` | Nothing (ephemeral) |

---

## 10. Summary: input categories by origin

| Category | Static / probe | What it samples | Can model influence future reads? |
|----------|----------------|-----------------|-----------------------------------|
| **System prompt** | Static | Behavioural framing | Only via self-edit proposals |
| **Mode prompt** | Static | Per-mode instruction | Only via self-edit proposals |
| **Tool descriptions** | Static | Per-tool model-facing text | Only via self-edit proposals |
| **Wall clock** | Static | Date/time/tz | No |
| **Today's note** | Probe | Current journal file | Yes — update_owned_block |
| **Source files** | Probe (self-edit) | Code + prompt sources | Yes — model proposes edits |
| **Recent runs** | Probe | Last N summaries | Yes — model writes its own summary |
| **Agenda** | Probe | Calendar events | Indirect (user manages calendar) |
| **Activity focus** | Probe | Panopticon focus segments | No (sensor; user's behaviour) |
| **Activity browser** | Probe | Panopticon browser segments | No (sensor; user's behaviour) |
| **Current window** | Probe | sway focus snapshot | No (sensor; user's behaviour) |
| **Bough state** | Probe | Task tree, events, day entry | Indirect (user manages tasks) |
| **Notes files** | Probe | Recently-edited files | Yes — notes_at_satan_done |
| **@satan directives** | Probe | User-authored triggers | Yes — notes_at_satan_done |
| **SATAN docs** | Probe | Doc chunks | Only via self-edit proposals |
| **Memory substrate** | Probe | Prior marked traces | Yes — memory_mark |
| **Typing speed** | **Unconsumed** | Keystroke analytics | Not yet |
