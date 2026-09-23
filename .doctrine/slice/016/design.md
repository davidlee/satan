<!-- doctrine:section sec-1 -->
# Intent

SATAN has never been able to ask the keeper anything. Every SATAN-to-human
surface in the tree is fire-and-forget push — `notify_send` with no `:actions`
callback, `inbox_append`, `proposal_stage`, sway borders, the owned org block.
The inverse exists (`@satan` directives) but the human always originates.
Nothing poses a question and receives a structured answer.

goad is a GUI host that renders whatever a user-owned backend tells it to and
carries the answer back. It already runs as a systemd user unit against
`~/satan/goad/backend.py`. SL-016 makes it SATAN's elicitation surface.

**Elicit only.** goad never gates a SATAN enactment on a human yes. ADR-017 §1
assigns human-approval flows to the Emacs client permanently; this slice holds
no authority item and adds no ledger row — §8.

> **This design was rejected once and rebuilt.** An adversarial pass ([[RV-007]],
> 19 findings, 9 blockers) found that the original routed the keystone through
> panopticon focus telemetry, which cannot carry it. Engagement now comes from
> goad's own record ([[DEC-013]]). Sections marked with the findings they answer.

## The shape

```
   goad's files                              ~/dev/satan/  (mechanism repo)
 +------------------------------+
 | queue.json     (state root)  |<-(2) PROMPT---- ask tool (consume phase)
 |   a projection, not a record |                  records kind "ask"
 |   ALSO: the canon trigger    |--(1) PERCEIVE--> evidence assembler
 +------------------------------+                       |
 | data/YYYY-MM-DD.json (corpus)|--------------->  canon rule --> handles
 |   presented_at . value . at  |                       |
 |   deferral provenance        |                  the answer, and
 |   intervention_id            |                  non-engagement
 +------------------------------+
 | backend.py (corpus)  merges, prioritises, stamps, persists |
 +------------------------------+
        ^ evaluate / respond
   +----+-----+
   | goad host|<-(3) DOORBELL------------ goad-emit via satan-trace-call
   +----------+  primary delivery, lossy     timeout-bounded, refusal-aware
```

Three capabilities. **No goad host change** — the
queue is read backend-side, which is what preserves that, and is goad's own
architectural review question #1. The queue file sits under SATAN's state root
(§4); the day record and `backend.py` are corpus-tracked.

An ask **correlates on what SATAN already perceives**, never on goad's own
handles: the percept is frozen before the question exists, so goad-minted
handles can only describe questions earlier runs queued (§2, [[RV-007]] F-20).
The goad canon rule serves perception — later runs see what is outstanding and
what the keeper did with it — not correlation.

## Why it matters

[[RFC-016]] diagnoses SATAN's dormancy as an attention-economy failure: the
behaviour layer has been dead since 2026-05-31 and the organism has *"no sense
organ for being ignored"*. Its D3 keystone is that disengagement becomes
perceptible and consequential.

goad supplies that organ — and supplies it *directly*, as a fact in a file
written by the thing that asked, rather than as an inference about where the
keeper's attention was. `"ask"` is already a **reserved but unemitted** member of
the closed intervention-kind set in all three registries.

A goad answer is also SATAN's **first direct human-sourced outcome signal**. The
observer's three positive predicates are all ambient telemetry — editor focus, a
git commit, a `recentf` entry. This one asks what the keeper said.

<!-- doctrine:section sec-10 -->
# The correlation gate

**The load-bearing section**, and the one the reframe does *not* rescue. A
goad-derived predicate still runs inside `satan-observer-classify`, which still
sits behind `satan-observer-classify-for-motives`, so motive correlation remains
the outer gate on every classification.

`satan-observer-classify-for-motives` (`satan/satan-observer-classify.el:544`)
ranks motives by intersecting each motive's `:cue` against the intervention's
percept handles. When nothing overlaps — *or the motive list is empty* — it
returns `:unknown :reason :no_correlation` and **`satan-observer-classify` is
never called** (`:587-599`).

```
  handles <- satan-observer--intervention-percept-handles   (:500-509)
  ranked  <- rank motives by |cue & handles|, ties by :order
      |
      +-- ranked non-empty --> satan-observer-classify --> predicates, else negative
      +-- ranked EMPTY -------> :unknown :no_correlation, nothing else runs

  kind "ask":
  motive  <- live motive with id = related_motive_id,
             not dormant, subject (cue_handles) still in its cue
      +-- found -----> satan-observer-classify --> answer predicate, else ask branch
      +-- not found --> :unknown :no_correlation
```

Kind `"ask"` goes through the same gate by a narrower route: it credits the motive
recorded at emit instead of re-ranking (below).

## What does not work

`satan-intervention-record` accepts `:cue-handles`, and its projection persists
it to `cue_handles_json`; **no production call site passes it**. That looks like
the hook the correlator forgot to use. It is not: the correlator reads
`bundle.json` and never the column. `cue_handles` feeds
`satan-intervention--counter-memory-handles` (`satan-intervention.el:597`) — the resonance path.
Passing it does not by itself make an ask correlate. It does carry the ask's
subject, which the ask's route through the gate reads back (below).

## SATAN may only ask about what it already perceives

**[[RV-007]] F-5.** The gate as first designed compared live motive cues against
*ambient* percept handles. Neither the question nor its subject took part — so a
generic `app:goad` cue admitted any question on any subject, and where several
motives carried the handle, file order picked which was credited. The gate proved
*some motive overlaps the ambient percept*, which is not a useful claim.

The machinery forces the fix. The percept is frozen at spawn, **before any
question exists**, and nothing rebuilds it: the tool decides against it at emit,
and the observer reads that decision back at maturity (below). So a
question-specific handle can correlate only if the question is derived from what
is already perceived. Therefore the ask tool requires:

1. the question to name a **subject handle** present in ctx `:percept-handles`;
2. that handle **not** to be goad-minted (`app:goad`, or a `topic:` the goad rule
   emitted); **and**
3. a live, non-dormant motive whose cue holds *that* handle.

Only motives whose cue holds the subject compete. Among them the tool ranks by
overlap with the percept, ties by file order (the correlator's own rule), and
records the winner as `related_motive_id`. A motive cued on `app:goad` therefore
cannot outrank or absorb an ask about something else ([[RV-007]] F-28).

**Goad handles cannot be the subject** ([[RV-007]] F-20). The goad canon rule
(§3) emits handles only for questions *already* in the queue, and a question
reaches the queue only by passing this gate. Requiring a goad-minted subject is
circular: no first ask on any subject could ever pass. `topic:` has no other
source today — `satan-percept-build` canonicalizes with hints `nil`
(`satan-percept.el:67`) — so subjects come from the rules that perceive the
keeper's world: `app:`, `surface:`, `domain_kind:`, `artifact:`, `phase:`,
`focal_app:`. (`bough_*` namespaces are admitted but inert: bough is deprecated
and inactive.)

```
 run N:  percept frozen (queue has no question about X)
         motive cue ∩ percept ∋ artifact:X   ──►  ask about X passes
         queue.json gains X
 run N+1: percept now carries app:goad, topic:X  ──►  perceivable, not correlating
```

This is a real constraint on what SATAN may ask, and it is the right one: a
question about something outside SATAN's perceptual field is a question it has no
grounds to ask.

## Emit decides; maturity reads the decision

**[[RV-007]] F-28.** Re-ranking every motive against the whole percept at
maturity, as the correlator does for other kinds, does not survive goad's own
handles. Once a question is outstanding, later percepts carry `app:goad` and
`topic:<Subject>`, and a motive cued on them (§3 invites exactly that) outranks
the subject's motive. At emit that would suppress every ask on another subject.
At maturity it would credit the goad motive with an answer about something else,
which is F-5's misattribution again.

So for kind `"ask"` only one side ranks. The tool decides once, at emit, and the
correlator reads that decision back:

```
emit      motives whose cue holds the subject
            -- rank by |cue ∩ percept|, ties by file order --> winner
          satan-intervention-record :related-motive-id winner
                                    :cue-handles (subject)

maturity  kind "ask":  live motive with id = related_motive_id,
                       not dormant, subject still in its cue?
                         yes --> satan-observer-classify
                         no  --> :unknown :no_correlation
          other kinds: rank by overlap, unchanged
```

`satan-intervention-pending` already returns `related_motive_id` and
`cue_handles`, so the correlator needs no new query. The percept handles the tool
ranks against are ctx `:percept-handles` (`satan-run-tool-ctx`,
`satan-run.el:334`). That is the list `satan-intervention-record` persists
(`satan-intervention.el:396`) and `bundle.json` carries.

With no winner the tool **does not emit** and records the suppression. SPEC-001
REQ-005/010 is the reason: an ask that cannot be classified is an ask whose
refusal cannot be perceived.

**Prohibited in interactive MCP** ([[RV-007]] F-12). Interactive sessions mint a
synthetic bundle with no percept and freeze tool context immediately
(`satan/satan-mcp.el:155-197`), so `:percept-handles` is nil there and the
maturity bundle has no percept either. The tool refuses in that mode. Repairing
MCP run-state coherence is a separate concern and goes to the backlog.

## The loop can still break, and that is now visible

**[[RV-007]] F-4.** The observer rereads **live** motives on every pass
(`satan/satan-observer.el:383`). `tick-pulse` holds `motive_replace`. So an ask
that passed the gate at emit can still mature `:no_correlation` if SATAN
rewrote or removed the motive in between.

For kind `"ask"` the correlator honours the persisted `related_motive_id`
(above). A rewrite that keeps the motive and its subject keeps the credit. One
that drops either yields an explicit `:no_correlation`, never a silent
re-attribution to whichever motive now ranks highest. The original phrasing,
*correlate by construction*, still overclaimed: detecting a broken loop is not
having an unbroken one. So:

- correlation is decided **at emit** and read back at maturity; the design does
  not claim the loop is closed;
- a goad ask that matures `:no_correlation` is **perceptible**, through the same
  attribute channel as suppression (§7) — the slice's thesis applied to itself.

Honouring the persisted motive id for **every** kind changes shared
classification semantics, so that remains backlog work. The ask's route is
kind-scoped, like its predicates (§6).

## Suppression is an outcome, not an early return

An ask tool that silently declines to ask recreates the blindness RFC-016
diagnoses, one level up: SATAN mute and unable to notice its own muteness, with
the symptom indistinguishable from a keeper who answers promptly. Both
suppression and a matured `:no_correlation` therefore land somewhere perceptible
(§7).

<!-- doctrine:section sec-2 -->
# PERCEIVE — evidence, canon rule, handle vocabulary

## Why this route and no other

`satan-percept-build` (`satan/satan-percept.el:65-67`) is exactly:

```elisp
(let* ((ctx      (satan-percept--canon-ctx prepare mode))
       (evidence (satan-memory-evidence-assemble ctx opts))
       (canon    (satan-memory-canon-canonicalize evidence nil ctx)))
  (list ... :handles (plist-get canon :handles) ...))
```

and `satan-memory-canon-canonicalize` (`satan-memory-canon.el:523-543`)
dispatches registered rules over the evidence window.

The evidence assembler is the one source both consumers of goad state read:

- **the percept**, through canon — so a later run perceives outstanding
  questions and their fate as handles a motive can cue on. A probe writes only
  numeric pressure to Postgres, and a tool result arrives after the percept is
  frozen; neither can put a token in `:handles`.
- **the observer's `after` state**, through
  `satan-memory-evidence-assemble-with-bounds` — so the answer predicate and the
  `"ask"` branch (§6) read the goad record with no database query and no side
  channel.

It does **not** make an ask correlate; nothing goad-minted can (§2, [[RV-007]]
F-20). [[DEC-004]] is amended accordingly.

**The goad source ignores the assembler's time bounds** ([[RV-007]] F-23).
`after` is assembled for emit to emit + 30 minutes (`satan-observer--after-state`,
`satan-observer-classify.el:102`) whatever the intervention's own window. The
source reads each ask's record, keyed by `intervention_id`, from the day file of
**that ask's emit date**, and the consumers apply the ask's window themselves
(§6). The percept takes each outstanding ask's emit date from its queue entry;
the observer takes it from the intervention. Neither ever reads by its own
window's date or by the classification date ([[RV-007]] F-34).

One file per ask is enough because `backend.py` files every event of a SATAN ask
(presentation, deferral, answer) in the day file of the ask's **emit date**,
which the ask's queue entry carries. The date the event happens does not matter
(§4, [[RV-007]] F-29). An answer at 00:05 to an ask emitted at 23:15 is filed
beside its presentation.

**The emit date is the keeper's local calendar date**, the one `backend.py`'s
`record_path` uses, and it is always derived from a parsed instant: the local
date of the time, never a substring of a timestamp string ([[RV-007]] F-33). The
distinction is real. `satan-intervention-pending` returns `ts` as psql renders it
in the `satan_memory` session zone, which is `GMT`, so under AEST an ask emitted
at 09:30 local carries the previous day's date in its first ten characters.
The queue entry's `emitted_at` and `expires_at` are written with the local
offset, and `backend.py` compares them as instants, as `is_deferred` already does.
(The existing `crosses_midnight` guard has exactly this defect for every kind:
[[ISS-021]].)

*(The stronger phrasing "handles exist only for what reaches the evidence window"
is false and was corrected — canon also emits context- and hint-derived handles,
`satan-memory-canon.el:429`. It does not create a missed route. [[RV-007]] F-16.)*

An on-demand `goad_read` tool may supplement for detail, on the `activity_read`
precedent. It carries no weight for the verification intent.

## What the rule is for: perception, not correlation

**[[RV-007]] F-6, F-20.** Two earlier versions made goad's handles carry
correlation, and both deadlocked. Keyed on the day record, no handle existed
until the keeper answered something — `load()` returns `{}` for an absent file
(`:69-74`) and `save()` runs only on a `respond` (`:153`). Keyed on the queue
file, a handle existed only for a question already queued, and a question is
queued only by passing the correlation gate. Either way the first ask could
never correlate.

So the ask correlates on handles the existing rules already emit (§2), and this
rule does a different job: it lets **later** runs perceive SATAN's outstanding
questions and what the keeper did with them. It reads the queue file and the
day record, and emits `app:goad` plus `topic:<Subject>` per outstanding
question. A motive may cue on those to act on the goad state — to follow up, or
to back off. No ask may use them as its subject, and they never change which
motive an ask credits (§2, [[RV-007]] F-28).

## The handle vocabulary is a public surface

A motive author has to write a `:cue` that matches it. Two hard constraints.

**Cue tokens are full canon handles, not bare words.** `satan-motive--parse-cue`
splits the `:cue:` footer on whitespace and `--cue-handles-well-formed-p`
requires every token to match `[a-z][a-z0-9_]*:[A-Za-z0-9][A-Za-z0-9_.+>-]*`. A
motive cues `app:goad`, not `goad`.

**The namespace is not free.** `satan-motive--admitted-namespaces`
(`satan-motive.el:83-92`) is a **closed allowlist**:

```
app  surface  surface_transition  domain_kind  domain_transition
bough_event  bough_node  bough_project  artifact  topic  phase  focal_app
```

`--cue-admittable-p` requires at least one cue handle from that set; without one
the motive is `:invalid-cue` and parses **dormant**, never reaching the
correlator. The docstring gives the reason: *"Without >=1 handle from this set a
motive triggers on every tick — defeats the cooldown floor."*

So minting a `goad:` namespace does not work. The rule emits `app:goad` as the
anchor and `topic:<Subject>` per outstanding question, inside the admitted set.

## Purity, and the watermark that is not there

ADR-001 requires perceive to be pure — its only write is `percept.json` — and
fixes the integration point: one percept builder, which the goad reader plugs
into rather than replacing.

Because this is evidence-window inclusion rather than a probe, **there is no
watermark**. R1's timestamp trap — comparing goad's local-offset microsecond ISO
against a formatted `...Z` under `string<` — is avoided by construction, and the
slice's original verification item 5 is moot. It returns the moment a probe leg
is added.

The contribution must be **compact by construction**: it costs tokens on every
run and the truncation cap is unenforced ([[ISS-001]]).

<!-- doctrine:section sec-3 -->
# PROMPT — the ask, the queue, and what the backend must become

## The tool

One `satan-tool-register` spec: `:name`, `:risk`, `:capability`, `:args-schema`,
`:handler` (SPEC-001 REQ-001/002). The handler:

1. refuses outright in interactive MCP mode ([[RV-007]] F-12) — before anything
   else, so a refusal there never records a false suppression (F-26);
2. refuses inside the goad quiet window (§8) — a refusal, not a suppression:
   nothing was decided about the question;
3. resolves the correlating motive among those whose cue holds the **question's
   subject handle** (§2), and **fails closed** if there is none, recording the
   suppression;
4. **records** the intervention of the reserved kind `"ask"` —
   `satan-intervention-record`, passing `:related-motive-id` (the winner),
   `:cue-handles` (the subject) and `:outcome-window-minutes 60`;
5. **projects** it — `satan-intervention-project`;
6. rewrites the queue projection whole, from the open rows;
7. rings the doorbell (§5) — the primary delivery path, not an optimisation.

**The window is 60 minutes** ([[RV-007]] F-10), the value
`docs/attributes/outcome-semantics.md:103` recommends for kind `"ask"`. With the
doorbell ringing at emit, presentation is near-immediate; the observer's own
30-minute evidence horizon does not bound it, because the goad source ignores
those bounds (§3).

`"ask"` is already in the closed intervention-kind set in all three registries
(`satan-memory-grammar.el:72`, `satan-audit.el:233`,
`satan-observer-classify.el:258`) and in `satan-observer-user-facing-kinds`. No
closed set is touched. Emission is an enactment and must appear in the transcript
(SPEC-001 REQ-003).

## Record, project, then ask

SL-017 split the intervention write in two (`DEC-018`, `satan-intervention.el`
header): a **record** half that appends to the run's transcript — the canonical
record, no database — and a **project** half that writes the Postgres row.
`notify_send` established the discipline for an emitter whose side effect must
be recorded first: record, act, project (`satan-tool/notify-send`).

The ask follows the record-first rule but projects **before** it acts, and the
difference is deliberate. `satan-intervention-pending` — the observer's only
source of work — reads Postgres. An ask with no row is never classified, so
showing it spends the keeper's attention and learns nothing. Notify's invariant
is *a Postgres outage never suppresses the act*; the ask's is **the queue holds
exactly the asks the observer will score**.

```
record (transcript) ──► project (row) ──► rewrite queue.json from open rows
      │                      │ fails                  │ fails
      ▼ fails                ▼                        ▼
  nothing asked      undelivered verdict,     undelivered verdict,
  (error)            recorded only            recorded and projected
```

Both failure arms reuse notify's existing verdict for *recorded but never seen*:
`unknown` / `high` / `mature` / `auto`, noted `undelivered: ERR`. Today that
lives as `satan-tools-notify--mark-undelivered`; it moves to
`satan-intervention.el` as a shared writer rather than being cloned. On the
project-failed arm the verdict is recorded only — the database is down — and
`satan-rebuild-interventions` later replays record and verdict together, so the
rebuilt row is never mistaken for pending. A verdict row also removes the
intervention from `satan-intervention-pending` at once, so an undelivered ask
never matures into a false `:ignored`.

## The queue is a projection

A question's durable identity is its intervention record ([[DEC-005]]) — the
transcript line, with the Postgres row as its projection. The queue file is a
**disposable projection** of the open rows — kind `"ask"`, no outcome row, and
`created_at + outcome_window_minutes` not yet passed — so it belongs under
`satan-state-path`, whose *"discardable"* contract is then exactly right.
Regenerating it from rows rather than transcripts is correct, not a shortcut: a
row-less ask is one the observer cannot score, and by the invariant above it
should not be asked.

One file, rewritten whole and atomically ([[DEC-010]]) — and rewritten at **two**
triggers, not one. The first design specified only the ask handler, but the
observer retires rows independently at classification
(`satan-observer-persist-verdict`, `satan/satan-observer.el:413`), so a matured
ask kept its queue entry until some later ask happened to rewrite the file, and
the backend kept re-presenting it ([[RV-007]] F-11). The rewrite therefore also
fires at classification. That is what makes the regenerability property
[[DEC-005]] leans on actually hold.

**Each entry carries `emitted_at` and `expires_at`** (emit plus window).
`backend.py` never renders an expired entry ([[RV-007]] F-24), and it files the
ask's events under `emitted_at`'s date (F-29). Both rewrite triggers run inside
SATAN runs, and runs can stop: under SL-018's `defer` policy no child spawns and
the observer (inside `satan-broker--spawn`) never runs. Without expiry the queue
would keep presenting questions whose window closed hours ago. With it the queue
is self-limiting even when SATAN is not running; a stale row that never gets a
verdict (`satan-intervention-pending` drops rows past window + 24h) is already
invisible to the backend.

## What `backend.py` must become

**This is the load-bearing part of the slice**, and the first design badly
understated it. "Merge the queue into `pending()`" is six changes, none
optional, to a file with no tests, no fixtures and no check recipe (slice R2):

| # | change | why | finding |
|---|---|---|---|
| 1 | **priority** for SATAN asks in `pending()` | `main()` renders only `waiting[0]`, and `pending()` returns `ITEMS` order — the comment at `:22` says *"Order is ask order."* Behind fourteen checklist entries, an appended question is effectively never shown | F-18 |
| 2 | **`presented_at`** written on an item's **first** render, never overwritten | the only real delivery proof (§5). `main()` re-renders `waiting[0]` on every evaluation (`:158-160`), so a later render must not move the stamp into the window's last minutes | F-1, F-30 |
| 3 | **deferral provenance** | `answer()` writes the same `deferred_at` for `later:` and `enough:` (`:132-146`). Here those are opposite signals, and `enough:` bulk-defers questions the keeper never saw | F-19 |
| 4 | **serialize queued items** | `save()` iterates `ITEMS` alone (`:77-90`), so a SATAN answer would render, mutate the in-memory map, and vanish on write | F-7 |
| 5 | **skip expired entries** | an entry past `expires_at` is not rendered, so the queue is self-limiting when SATAN is not running | F-24 |
| 6 | **file a SATAN ask under its emit date** — its events go to the day file of its `emitted_at` date, and `pending()` reads its state from there | `record_path(now)` keys every write by the date of the event (`:65-66`, `:151`). An ask answered at 23:40 would be pending again at 00:10 and asked twice, and its record would be split across two files | F-29 |

Fixtures come first. goad degrades safely on a backend fault — the host does not
crash — but prompts stop, and goad's own field notes record that *"waiting and
dead look the same"*.

## Identity rides the option id

**[[RV-007]] F-13 — not `event.data`.** Ingress `data` does not survive into a
`respond` request. goad echoes backend-owned **option and field ids**
(`docs/specs/001-host-backend-protocol.md:87`); only `view_id` is host-minted
(`:139`). `backend.py`'s docstring already describes the pattern as deliberate:

> *"which item a button belongs to is carried in the option id (`yes:meds`),
> because the host mints view ids and will not carry ours."*

Constraint: option ids must remain parseable back to an `intervention_id`, and
`answer()` currently parses with `verb, _, item_id = option.partition(":")` — a
single split. An encoding must survive that, or `answer()` changes with it.

## Two repos, one landing

`satan-tool--description` reads the model-facing description from the **corpus**
repo and **signals when it is missing** (`satan/satan-tools.el:208-209`), with
the manifest built per-spawn. Landing `goad_ask` without
`~/satan/tools/goad_ask.md` **breaks every run of every mode that allowlists it**.

Corpus-side change set: `goad/backend.py` (the six above), `goad/README.md:16`
(the record format), `tools/goad_ask.md`, and the one-off day-file conversion.
The corpus repo is ungoverned by this doctrine corpus, which makes the coupling a
sequencing hazard rather than a governance one — and is why they land together.

<!-- doctrine:section sec-4 -->
# DOORBELL — the delivery path, never the delivery proof

The ask tool rings goad at emit via `goad-emit --source satan --kind K --data
JSON`. `source: "host"` is reserved (goad SPEC-003/R-13). The doorbell is how an
ask reaches the keeper inside its window; `presented_at` is how SATAN knows it
did.

## The contract is three exit codes

From `~/dev/goad/crates/goad-emit/src/main.rs`:

| exit | meaning | output |
|---|---|---|
| 0 | the host **took the envelope** | silent (goad 005/D-7) |
| 1 | the host refused it and said why | one stderr line: `goad-emit: refused: <reason>[ retry_after_ms=N][ (detail)]` |
| 2 | emit got no usable answer — usage, configuration, nothing listening, inadmissible reply | one stderr line |

The reason **token is first, deliberately** (`render.rs:59`: *"so a wrapper can
branch on it"*).

## The ledgered tier carries it

[[EVD-002]]. `satan-trace-call` (`satan/satan-trace.el:227-266`) calls
`call-process` with DESTINATION `t`, which **mixes stderr into the same buffer**:

```
$ emacs --batch --eval '(with-temp-buffer (let ((exit (call-process "sh" nil t nil "-c" "echo OUT; echo ERR 1>&2; exit 1"))) (princ (format "exit=%s buffer=%S\n" exit (buffer-string)))))'
exit=1 buffer="OUT\nERR\n"
```

It returns `(:exit N :stdout STR :timed-out BOOL)`. Unambiguous because success
is silent and a refusal writes exactly one line and nothing to stdout. **No raw
two-buffer fallback, no structured-refusal parser, no new mechanism.**

## Exit 0 does not mean delivered

**[[RV-007]] F-1 — the first design got this wrong, and the correction is why
the doorbell proves nothing about delivery.** goad replies `accepted` **before** calling the
backend. `crates/goad/src/controller.rs:735`, verbatim:

> *"accepted. The reply leaves **before** the backend is called: the listener
> awaits it before accepting the next connection, so a reply that waited for the
> exchange would put `engaged` out of reach (I-2)."*

`host.evaluate()` runs later, at `:998`. So a dead or crashing `backend.py`
yields **exit 0**. The first design read exit 2 as the fail-closed case and
claimed a dead backend would suppress asking; it does not.

The consequence was worse than a wrong sentence: SATAN would persist an
intervention and start an outcome window for a question that was never rendered,
which then matures as non-engagement. **Delivery failure would have been recorded
as the keeper ignoring SATAN** — the exact signal the slice exists to produce,
manufactured out of a crash.

So **no inference is attached to the exit code beyond the doorbell itself**:

| exit | what SATAN concludes |
|---|---|
| 0 | the envelope was accepted. Nothing about the backend, nothing about rendering |
| 1 | the host refused it — the question waits for goad's next evaluation |
| 2 | the doorbell could not be rung — likewise |

**Delivery is proven by `presented_at`** in the day record (§4, §7) — a stamp only
something that actually ran can write.

## The timeout is mandatory

`goad-emit`'s usage text: *"The host answers when it has judged the event, and
takes as long as that takes; emit sets no deadline of its own. Wrap it if you
need one."* ADR-018's cited failure mode — handlers run synchronously in the
broker's host process — therefore binds. `satan-trace-call`'s `timeout -k 2`
(exit 124 mapped to `:timed-out`, the wrapper's own 125/126/127 never conflated)
is the correct tier, not a nicety.

## Why the doorbell is not optional

**[[RV-007]] F-22.** goad's `default_poll` (30m) never governs a live backend:
`backend.py` answers every evaluation with `next_check = next_slot(now)`
(`:160`), and slots are two-hourly from 09:00 to 23:00 (`SLOT_HOURS`, `:40`).
An ask queued at 09:05 waits for 11:00 unless something rings; one queued at
23:05 waits for 09:00. Against a 60-minute window, the slot poll alone would
mature most asks `undelivered`. The first design's *"ship last, or not at all"*
rested on the 30-minute poll and was wrong.

## A refused doorbell loses nothing, and hides nothing

The queue file is the durable carrier, so a refused or failed ring loses the
question to nobody: goad's next evaluation — the next slot, or the end of the
exchange that made it `engaged` — still finds it. goad's spacing is a fixed
three seconds, so `too_soon` is an edge case. **No retry machinery**:
`retry_after_ms` is advice goad itself reports and never obeys.

What a refusal costs is latency, and latency is visible: an ask that is not
presented within its window matures `:unknown` `undelivered` (§6), never
`:ignored`. Whether goad re-evaluates at the end of an `engaged` exchange is
unverified; the plan verifies it before relying on it.

A failed ring is recorded in the transcript by `satan-trace-call` already. If it
is ever also journalled, that goes through `satan-announce :journal` — the one
seam for SATAN's journal lines and pops since SL-017 (`satan/satan-announce.el`)
— never a fresh `logger` call.

<!-- doctrine:section sec-5 -->
# The loop — the answer, and the silence

The positive leg is an observer predicate. The negative leg is a kind-specific
branch of the observer's negative path that reads the same record — **not** the
ack-event path over focus telemetry, and getting that wrong is what a 19-finding
review cost.

```
  ask recorded --> queue.json --> backend prioritises --> goad renders?
                                                              |
                          +------------- no ------------------+-- yes: presented_at
                          |                                   |
                  never presented          +------------------+------------------+
                          |            answered         Later (explicit)    Enough, or nothing
                          |         value + at + iv_id   deferred_at +      by maturity
                          |                |             provenance              |
                          v                v                  v                  v
                  :unknown :high    predicate fires    :unknown :low      :ignored :medium
                   "undelivered"       :worked        engaged, postponed  <-- THE KEYSTONE
```

Every branch is a fact in one file, written by the process that asked the
question. Nothing is inferred from where the keeper's eyes were.

## The positive leg

One entry in `satan-observer--predicates`, an ordered alist of keyword to
function with the uniform signature `(baseline after motive intervention)`. Every
predicate runs and every one that fires is collected; two or more raise the
confidence to `:high` (`satan-observer-classify.el:476-485`). It reads the goad day record out of `after`, the assembled
evidence window that §3 already populates, so it needs no database query and no
side channel.

It fires when the record holds an entry carrying this intervention's
`intervention_id` with a `value` present and an `at` **within the declared
outcome window** — emit plus 60 minutes (§4, §9). The goad source is not cut to
`after`'s 30-minute horizon (§3), so the predicate applies the ask's own window.

This is the first predicate that is **direct evidence** rather than ambient
inference. The other three ask whether the editor focused, whether a commit
landed, whether a file was visited.

**Predicates are scoped by kind** ([[RV-007]] F-21). The ambient three ignore
the intervention's kind and run first (`satan-observer-classify.el:470-485`),
so a commit in the motive's project would mark a never-presented ask `:worked`.
For kind `"ask"` the answer predicate is the **only** positive predicate: an
ask's expected outcome is an answer, and nothing ambient is evidence of one.
Every other kind keeps the ambient three; the answer predicate is inert for
them, since it keys on an `intervention_id` only an ask writes.

**The answer is traced by the observer** ([[RV-007]] F-9, [[DEC-011]]). An
answered ask classifies `:worked`, so it already passes through
`satan-observer--persist-positive` (`satan/satan-observer.el:110`), which writes
the `observation` trace via `satan-memory-store-mark`. For kind `"ask"` that
trace's metadata gains the question (the intervention's `message`) and the
submitted value, read from the same record. One writer, one trigger, an existing
module — no new path.

**Not the manual writer.** `satan-intervention-write-manual-outcome` enforces
`--manual-classifications` = `("harmful" "contradicted")`, and its docstring is
the rule: *"Auto kinds (worked/neutral/ignored/unknown) belong to the auto
classifier and must not reach here."* Using it for success would amend an
invariant that exists to keep the two apart and touch authority-ledger row 4.

## Why the negative leg is not focus telemetry

**[[RV-007]] F-2, F-3, F-17.** The original narrowed `--count-ack-events` by
target surface so `:ignored` would mean *ignoring* rather than *absent*. Four
things were wrong underneath it:

1. **The gate never opened.** `satan-observer--ack-checked-p` compared the
   string `"ok"` to the symbol `'ok` with `eq`, so every user-facing
   intervention firing no predicate classified `:ignored :low` unconditionally
   ([[ISS-014]], since fixed at `6ff52f7`). Fixed, the gate puts the verdict
   back on focus telemetry — which items 2–4 say cannot carry it.
2. **The boundary excludes presence.** Ack-events count only segments whose
   `start_ts` is strictly after the emit (`:279`), so a keeper continuously
   focused from before it counts as absent.
3. **The data is evicted and mislabelled.** Only the newest ten segments survive
   assembly (`satan-memory-evidence.el:63,185`), and real telemetry carries
   `app_id:"goad"` against Emacs and Claude window titles.
4. **Presentation may fake acknowledgement.** Rendering calls `window.show()`
   (`goad/src/glass.rs:328`); if the compositor focuses new windows, an untouched
   prompt looks acknowledged.

Narrowing a count that is never taken, on evicted data, with mislabelled
surfaces, against a possible self-focus artefact, is not a design.

## The negative leg, as it now stands

Non-engagement is **presented, not answered, not explicitly deferred, window
elapsed** — facts in the day record, read at maturity (the observer runs only
once the outcome window has passed, so *elapsed* is given).

The mechanism is one branch in `satan-observer-classify-negative`
(`satan/satan-observer-classify.el:292`), dispatched on kind `"ask"` **before**
the user-facing focus path, reading the goad record out of `after` exactly as
the positive predicate does.

**The record is judged as it stood at window end** ([[RV-007]] F-35). Both legs
treat any stamp after emit + 60 minutes (`presented_at`, `deferred_at`, or an
answer's `at`) as absent. The verdict therefore does not depend on when the
observer happens to run within its 24-hour band. Precedence, first match wins:

| the record, for this `intervention_id` | verdict | evidence |
|---|---|---|
| no `presented_at` | `:unknown :high` | `undelivered` — delivery unproven, never the keeper's silence |
| `presented_at` in the last 10 minutes of the window | `:unknown :low` | `short_exposure` — too little time to call it ignored |
| `deferred_at` with `later` provenance | `:unknown :low` | `deferred` — engaged, postponed |
| presented, then bulk `enough` | `:ignored :medium` | `dismissed` — saw it and refused the slot |
| presented, nothing else | `:ignored :medium` | `untouched` — **the keystone** |

The `undelivered` row uses the verdict `notify_send` already writes for a
recorded-but-unseen intervention (§4) — `unknown`, `high` — so the two tools
agree on what *never delivered* means. The evidence labels in the right-hand
column reach the persisted outcome through the observer's verdict mapping
(`satan-observer--verdict-classify-args`, `satan/satan-observer.el:180`), which
today carries no such labels and gains them ([[RV-007]] F-25). A `dismissed` ask is a refusal the keeper made with the
question in front of them, which RFC-016 counts as disengagement; `enough`
reaches only questions *not* presented through the first row.

**A late answer counts as no answer** ([[RV-007]] F-31, F-35). goad keeps a
view already on screen answerable after `backend.py` stops rendering the entry:
`respond` still reaches `answer()` (`backend.py:141-142`). `backend.py` stores
the answer, and later percepts see it, but the ask's verdict is what the record
held at window end: presented and unanswered, so `:ignored` `untouched`, with no
`:worked` and no answer trace. That holds whether the observer ran before the
answer or after it.

**Midnight does not bound an ask** ([[RV-007]] F-29). `satan-observer-classify`
returns `:unknown :crosses_midnight` before any predicate runs when the 30-minute
window spans two dates (`satan-observer-classify.el:87-96`, `:472`). That guard
protects the panopticon segment file, which the assembler keys by the window's
end date. Kind `"ask"` reads no segments (its only positive predicate is the
answer), and its record is one file keyed by the emit date (§3). So the guard
does not apply to it. Without that exemption every ask emitted after 23:30 would
mature `:unknown`, whatever the keeper did.

The branch keeps `satan-observer--assert-auto-classification` satisfied — every
verdict it returns is an auto kind. It needs no panopticon, no compositor
behaviour and no retention policy, and it dispatches before the ack gate, so
the gate's state never reaches an ask. Every other kind keeps the focus path
unchanged.

It is also a *truer* claim. Absence of a focus segment was only ever a proxy for
disengagement; a presented question left untouched past its slot **is**
disengagement with that question.

## Deferral is engagement, and must be distinguishable

`Later` means the keeper saw this and postponed it. `Enough` defers **every**
pending item for the slot — and since only the first pending item is rendered,
it routinely dismisses questions nobody saw.

`answer()` writes the same `deferred_at` for both (`backend.py:132-146`), so the
record cannot currently tell them apart ([[RV-007]] F-19). For this slice they are
opposite signals, so §4's change set gives them distinct provenance. Without it
the negative leg cannot read engagement out of the record at all.

Per goad SPEC-001/R-58, to distinguish *unanswered* from *false* the field is
**omitted rather than defaulted**.

<!-- doctrine:section sec-6 -->
# State, data, and where things land

## No new stateful layer

ADR-018 D5 (*"no new stateful layer lands in elisp"*) and POL-001's
anti-candidate clause (*tiny single-file state stays*) appear to conflict here,
and ADR-018 VA-4 is checked at design review. [[DEC-005]] dissolves it rather
than adjudicating: the state SL-016 appeared to need already exists.

An ask **is** an intervention. `satan-intervention-record` already records
`intervention_id`, `run_id`, `ts`, `mode`, `kind`, `message`,
`related_motive_id`, `cue_handles`, `percept_handles`, `expected_outcome`,
`outcome_window_minutes`, `severity`. So D5 is **satisfied, not waived**, and
POL-001's clause is never engaged — the two authorities do not meet.

| tier | holds | where | on loss |
|---|---|---|---|
| record | the ask, as `intervention.created` | the run's `transcript.jsonl` | the question is gone |
| row | its projection, what the observer scores | `satan_memory` (Postgres) | `satan-rebuild-interventions` |
| queue | the open rows, for `backend.py` | `satan-state-path` | regenerate from the rows |
| answer | what happened to each question | goad's `data/*.json` | goad's concern, corpus-tracked |

What the reframe changes is not this split but **how much the third tier has to
carry** — see below.

## The record format

JSON, not TOML. The day file is **not** a goad contract: goad's invariant is that
the host understands interaction and the backend owns all domain meaning and
persistence, and `backend.py`'s docstring says *"items, sections, slots and the
record format are all this file's business"*. The host never reads it; the only
other mention is `README.md:16`.

So rather than hand-roll an elisp TOML reader against a grammar SATAN does not
own — no parser in the tree, none on the load path, and adding one would be the
first elisp package dependency, contradicting `satan.el:5` — `backend.py` emits
JSON and SATAN reads it with the built-in `json-parse-buffer` ([[DEC-009]]).

`save()` today is a hand-written TOML serializer including a three-branch value
renderer, ending in a non-atomic `Path.write_text`. It becomes a `json.dump`
through tmp+rename. **Atomicity is not incidental**: SATAN reads this file from
the broker at percept-build time, on a ~30 minute tick, while the keeper may be
answering.

Two fields the first design did not see:

- **`presented_at`** — written on an item's first render and never moved. The
  only proof of delivery, because `goad-emit` exit 0 does not carry one (§5).
- **deferral provenance** — so an explicit `Later` is distinguishable from a bulk
  `Enough` (§6).

A SATAN ask's entry, with these fields and its answer, lives in the day file of
the ask's emit date, not of the event (§4).

Plus the one-off conversion of the five existing day files, a reviewable commit
since they are corpus-tracked.

## Where the answer lands

Three places, each doing one job ([[DEC-011]]):

1. **the day record** — arrival, keyed by `intervention_id` via the option id
   ([[ASM-001]]);
2. **the percept** — visibility for later runs, via §3; never correlation (§2);
3. **a memory trace** — durable human-sourced evidence.

**Not the inbox.** The slice names `satan-tools-inbox.el` under deliberate
non-duplication as the incumbent SATAN-to-human surface. The same logic runs the
other way: an answer is human-to-SATAN, which is perception, and perception has a
substrate already.

**The trace is an explicit write by this slice** ([[RV-007]] F-9). The first
design said the answer *"becomes a memory trace ... written under tick-pulse's
existing `memory-write` capability"*. Both halves were wrong: the observer's
trace records intervention id, motive id, predicates, classification and
confidence (`satan-observer--persist-positive`, `satan/satan-observer.el:110`) —
**not** the question or the submitted value — and it writes via
`satan-memory-store-mark` directly,
not through a capability-gated tool. So the answer trace is written by the observer when it classifies an answered
ask `:worked`, extending the trace `satan-observer--persist-positive` already
writes with the question and the submitted value (§6). No new writer.

## Where suppression lands

Suppression and a matured `:no_correlation` need a channel of their own: nothing
was asked, so the day record cannot hold it, and an unasked question is not an
enactment so SPEC-001 REQ-003 does not reach it.

**Not a sensor alert** ([[RV-007]] F-8). Alerts are derived **pre-spawn** from a
closed sensor-status table covering only current-window, focus and browser faults
(`satan/satan-sensor-alerts.el:102,311`). Suppression happens later, inside a
tool handler. There is no enqueue API and no status source; the first design
asserted a mechanism that does not exist.

**Verified replacement:** enqueue an **attribute** from the tool handler via
`satan-attribute-enqueue`, following `satan/satan-tools-hippocampus.el:109` —
a tool handler doing exactly that. Checked by read rather than assumed.

It is also the right shape: suppression is a persistent *condition of the
organism*, not an event in the world, which is what the attribute layer is for,
and the throttling the first design demanded becomes a property of attribute
semantics rather than bespoke cooldown code.

Two constraints for the plan: attributes reach the capsule as **pressure**, not
readable text, so detail needs a second sink; and [[ISS-011]] records that
`satan-attrd` **rejects** unknown sensor outcome reasons, so a new reason value
needs attrd support — a cross-repo dependency.

<!-- doctrine:section sec-7 -->
# Governance posture

## No authority item, no ledger row

ADR-017 §1 assigns human-approval flows to the Emacs client **permanently**, and
the authority ledger has all seven rows at `emacs-client` with nothing migrated.
goad is a **data-plane** surface: it elicits, never gating a SATAN enactment on a
human yes. This slice holds no authority item and adds no row.

Two triggers would flip that, and the design avoids both by construction:

1. **goad gating an enactment** — §1 assigns that to Emacs permanently; an ADR
   amendment, not a slice decision.
2. **goad answers writing outcomes by a new path** — that touches ledger row 4
   (append-only audit), already flagged as a latent dual-write hazard. Both
   legs are observer verdicts (§6). The only other outcome this slice writes —
   `undelivered`, at emit (§4) — goes through the auto-verdict writer
   `notify_send` already uses (`satan-intervention-classify-record` then
   `satan-intervention-project-with-verdict`). The slice moves that writer to a
   shared home and calls it from a second tool; it adds no path. *(No REV
   accepted that writer as such: SL-017's REV-002 covers operational alarms.
   Whether a second caller of an existing auto-verdict writer wants a ledger note
   is a question for `/reconcile` at close.)*

**Elicit-only exempts the new tools from the *authority* question, not the
*protocol* one** (ADR-017 §2). The ask and the doorbell are enactments and
inherit the full invariant set. SPEC-001 REQ-011 is most on point because goad is
a new surface: invariants hold regardless of initiating surface, which forbids a
"goad shortcut". That is what makes elicit-only load-bearing rather than
stylistic.

*(SPEC-001 is `draft` with `pending` requirements. Its authority is derivative —
the REQ ids are addressable names for constraints ADR-017 §2 already imposes.)*

## POL-001: the No branch, explicitly

A1 assumed the SATAN-side code earns its seat as a thin shell on the
`satan-tools-{notify,sway,activity,agenda}.el` precedent. **A1 is falsified.**
The 2026-07-22 amendment says why those keep their seats:

> They earn the seat because **the human's editing surface is where their output
> lands and where the keeper approves it**, not because they need an Emacs image
> to compute.

The rationale is the destination of the output, not the thinness of the shell.
goad renders in its own window. Applying the test — *does it use the editor as an
editor?* — the goad reader, the ask tool and the doorbell use no org parsing or
writing, no denote naming, no buffer manipulation, no dired/`find-file`/`recentf`,
no interactive `satan-*` command, and take no approval at the keeper's editor.
**The answer is No.**

No is not the same as now. POL-001's No branch makes a module *eligible* for
extraction when carving becomes cheaper than hosting it, gated on four triggers —
imminent surface growth, a recurring language/runtime-fit bug, a reviewer reading
elisp to evaluate non-elisp work, tests dominating `emacs --batch` CI cost —
closing with *"Absent any trigger, leave it."*

**None fires.** So the modules stay in elisp as **recorded tenants, not
residents** ([[DEC-008]]), travelling with the observer/memory extraction
([[IMP-009]], [[IMP-007]]) rather than anchoring to Emacs.

The seat clause genuinely does not contemplate a second human surface that is not
the editor. That gap predates this slice; widening it here would be governance by
implementation. It is a revision candidate for `/reconcile` at close, with two
others: `.doctrine/state/boot.md` still saying the protocol tech spec and
authority ledger are "not written yet" when both exist, and RFC-017 D1 rows G1/G2
reading "not written" when both landed.

## ADR-018

- The doorbell runs synchronously in the broker's host process and is
  `timeout(1)`-bounded (§5).
- D5 on state is satisfied, not waived (§7).
- Adding a capability and tools **enlarges the `satan-mode.el` mode/tool/
  capability table that D4.2 names as the first authority item to migrate**.
  Saying so here is cheaper than discovering it at migration.

## Autonomy, and the window it needs

The autonomous producer ships in v1 ([[DEC-006]]), with a precondition it
does not own: an unattended run that can authenticate. SL-018's broker
credential gate is in the tree (`723c205`; `satan/satan-broker.el:754`), though
the slice is still open. An unattended run of any mode without
`:credential-policy prompt` defers when no credential session is live. That
covers every `tick-*` mode, since `satan-tick-register` sets no policy. A
deferring run records `credential_deferred` and spawns nothing. Once the
deferral streak reaches `satan-credential-escalate-after` (default 4h,
`satan-broker.el:380`), the next run prompts instead. So SATAN asks unprompted
**only when an unattended run can authenticate**, which loosely tracks the
keeper having unlocked the vault. A deferred run also runs no observer, which
lives in `satan-broker--spawn`. Asks that mature meanwhile wait for the next
spawned run, and `expires_at` stops the queue presenting them (§4). The slice
builds and verifies without any of this, because every verification item
drives the tool directly. Research delta 9 reported
`tick-pulse` holds neither `notify` nor `inbox-write`, citing
`satan-mode.el:146-154` — which is `self-edit-mech`'s spec. `tick-pulse` is
registered at `satan/satan-tick.el:95` from the `satan-tick-register` defaults
(`:60-88`), whose capabilities are `(notify inbox-write memory-write
motive-write)`. It already holds both, and carries `motive_read`/`motive_replace`
— which is what makes §2's correlation check performable in the mode that emits,
and also what creates §2's mutation race.

A **distinct** `goad-ask` capability, not a reuse of `notify`: reusing it would
give one switch for two behaviours, so disabling goad would silence all
notification and re-enabling notification would silently re-arm goad. Plus a
`satan-goad-enabled` defcustom (the governed idiom, ledger row 6).

**A goad-specific emission window, not global quiet hours** ([[RV-007]] F-15).
The hazard is real: `satan-tick-quiet-hours` is `nil` — *"was '(22 . 7); disabled
while iterating"* (`satan-tick.el:24`) — and the tick fires every ~30 minutes
around the clock. Today that is harmless because every tick surface is ambient: a
sway border, an inbox line, an org block. A doorbell is not ambient; it draws a
window, and a slice that answers RFC-016 by earning the right to interrupt and
then interrupts at 3am spends the attention it was built to conserve.

But restoring the **global** switch was the wrong remedy. `satan-tick-quiet-p` is
consulted by `satan-tick` **before any mode is selected** (`satan-tick.el:129`),
so it would suppress overnight observer processing, memory work and inbox work —
none of which this slice has any business changing. The window belongs to the ask
path.

It does not get a predicate of its own. `satan-tick-quiet-p` now has three
consumers — the tick, sensor alerts (`satan-sensor-alerts.el:331`) and failure
announcements (`satan-broker--quiet-p`) — each reading the one global
defcustom. The ask path calls the same predicate with **its own window**:
`satan-tick-quiet-p` gains an optional window argument defaulting to
`satan-tick-quiet-hours`, and the ask passes `satan-goad-quiet-hours`. One
predicate, two windows, no parallel implementation.

`satan-goad-quiet-hours` defaults to **`(22 . 9)`**: no ask from 22:00 through
08:59 ([[RV-007]] F-29). Asks resume at goad's first slot (09:00). Under the
default, every 60-minute window closes before the 23:00 slot and before
midnight, so no ask's record straddles two dates at all. What keeps a narrower
setting correct is the emit-date filing (§4), not the default.

<!-- doctrine:section sec-8 -->
# Verification

## Done is a closed loop, observed end to end

| # | claim | how |
|---|---|---|
| 1 | SATAN emits an `"ask"`, it takes priority in `pending()`, and goad renders it without a host change | VT |
| 2 | the keeper answers; the answer is readable and **attributable to the originating intervention** via the option id, and **survives `save()`** | VT — [[ASM-001]]'s round trip |
| 3 | a presented ask left untouched, or dismissed by a bulk `Enough`, classifies `:ignored :medium` at maturity through the `"ask"` branch, whichever way the ack gate reads | VT — the keystone |
| 4 | an explicit `Later` is distinguishable in the record from a bulk `Enough`, and classifies `:unknown :low` | VT — without it, item 3 cannot be read |
| 5 | a refused or failed `goad-emit` loses nothing: the question is still in the queue at goad's next evaluation, and if that falls outside the window the ask matures `undelivered`, not `:ignored` | VT |
| 6 | an ask with no correlating motive is suppressed, and the suppression is perceptible as an attribute | VT |
| 7 | a matured `:no_correlation` is likewise perceptible | VT |
| 8 | the queue projection regenerates totally from the open intervention rows, and retires an entry at classification | VT |
| 9 | `goad_ask` refuses in interactive MCP mode | VT |
| ~~10~~ | ~~sensor watermark advance, seeded with a source-format watermark~~ | **moot** — no probe, no watermark |
| 11 | an ask whose projection or queue rewrite fails carries the `undelivered` verdict, never enters `satan-intervention-pending`, and survives `satan-rebuild-interventions` with its verdict | VT |
| 12 | an ask never presented matures `:unknown :high` `undelivered`, not `:ignored` | VT |
| 13 | an ask correlates on a perceived non-goad subject handle on its **first** emission; a goad-minted subject is refused | VT — [[RV-007]] F-20 |
| 14 | a never-presented ask does not classify `:worked` when an ambient predicate would fire (e.g. a commit in the motive's project) | VT — F-21 |
| 15 | an answer after emit + 60 minutes does not fire the predicate; an ask presented in the window's last 10 minutes matures `short_exposure` | VT — F-10, F-23 |
| 16 | `backend.py` never renders an entry past `expires_at` | VT — F-24 |
| 17 | an answered ask's trace carries the question and the value | VT — F-9 |
| 18 | the ask's evidence labels reach the persisted outcome row | VT — F-25 |
| 19 | with a question outstanding and a motive cued on `app:goad`, an ask on another perceived subject emits and credits the subject's motive, at emit and at maturity | VT — F-28 |
| 20 | an ask whose recorded motive has been removed, made dormant, or no longer cues the subject matures `:no_correlation` | VT — F-28, F-4 |
| 21 | with quiet hours off, an ask emitted at 23:15 and answered at 00:05 classifies `:worked` from the emit date's file, and is not presented again after midnight | VT — F-29 |
| 22 | `presented_at` keeps its first render's stamp across later evaluations | VT — F-30 (a `backend.py` fixture) |
| 23 | an answer after the window classifies `:ignored` `untouched` with no answer trace, the same whether the observer runs before or after the answer arrives | VT — F-31, F-35 |
| 24 | under a UTC database session and a +10:00 local zone, an ask emitted at 09:30 local is filed and read under its local date | VT — F-33 |
| 25 | a run after midnight perceives an ask answered before midnight as answered, not outstanding | VT — F-34 |

## What the reframe bought, tested

Item 3 is the RFC-016 D3 keystone and it is now testable **without a compositor
fixture, without panopticon, and independently of [[ISS-014]]** — the test runs
it with the ack gate reading both checked and unchecked, proving the branch
dispatches first. Present an ask,
touch nothing, let the slot pass, read the record. Under the original design it
required a keeper physically absent from the machine, which is not disengagement,
and rested on an ack gate that never opens.

Items 4, 6, 7 and 9 are new, each the consequence of a finding: the record could
not express deferral provenance (F-19), suppression had no mechanism (F-8),
the correlation loop can break after emit (F-4), and interactive mode has no
percept (F-12). Items 11 and 12 hold the rule that a delivery failure is never
recorded as the keeper's silence — the F-1 lesson, applied to emit and to
maturity.

## The outcome window, stated

`outcome-semantics.md:103` recommends 60 minutes for kind `"ask"`; the observer's
evidence window is a fixed 30 (`satan-observer-classify.el:28,80`). The first
design left those to disagree silently and gave the predicate no upper bound
([[RV-007]] F-10).

The ask handler passes `outcome-window-minutes` **60** (§4). The predicate
requires the answer's `at` to fall within emit + 60, so a late answer cannot
register as `:worked`. The observer's 30-minute evidence horizon does not cut
the goad record, which is contributed whole and windowed by its consumers (§3);
the `short_exposure` row (§6) keeps a late presentation from reading as
ignored.

## Test conventions

`satan/test/<module>-test.el` — **not** a top-level `test/`, which the slice's
original selectors named and which does not exist. Tests are
`<prefix>/<behaviour-slug>`. Three fixture idioms exist and all three are wanted:
temp dir plus defcustom rebinding (record and queue paths), `cl-letf` subprocess
stubbing (`goad-emit` without a live host), and `ert-fail` spies on mutating
functions to prove purity (ADR-001 on the perceive leg).

`backend.py` needs fixtures of its own — it has none, and six of the slice's
changes live there.

**A fixture must not build the value under test.** [[ISS-014]] survived because
`satan/test/satan-observer-test.el` constructed `sensor_status` as the symbol
`'ok` by hand while the assembler emits the string `"ok"`. The test passed;
production never behaved as tested. Fixtures here pin to the producer's own
output.

## Two traps that make green not green

- The suite **refuses to run** without `SATAN_DB_HOST` or
  `SATAN_FAILOVER_TO_SYSTEM_DB` (`dev/satan-test.el:73-77`), and DB tests
  `skip-unless` reachable — a fresh checkout silently skips ~130 tests and
  reports green ([[mem.fact.satan.green-is-not-green]]).
- `just check` exits 0 even with unexpected test failures ([[ISS-008]]), and
  concurrent runs clobber the shared test databases ([[ISS-013]]).

Neither is this slice's to fix; both are this slice's to not be fooled by.

<!-- doctrine:section sec-9 -->
# Surface, sequencing, and risks carried

## Affected surface

**Mechanism repo** (`~/dev/satan`) — design targets:

| file | why |
|---|---|
| `satan-memory-evidence.el` | goad record + queue join the evidence window (§3) |
| `satan-memory-canon.el` | the canon rule, triggered by the queue file (§3) |
| `satan-observer.el` | queue rewrite at classification; the answer trace in `--persist-positive`; the ask's evidence labels in `--verdict-classify-args` (§4, §6) |
| `satan-observer-classify.el` | the answer predicate; kind-scoped predicate selection; the `"ask"` branch of `classify-negative`; kind `"ask"` credits its emit-time motive in `classify-for-motives` and is exempt from the `crosses_midnight` guard — no other kind's verdicts change (§2, §6) |
| `satan-tick.el` | the `goad-ask` capability; `satan-tick-quiet-p` gains a window argument (§8) |
| `satan-intervention.el` | the `undelivered` auto-verdict writer, moved from `satan-tools-notify.el` (§4) |
| `satan-attribute.el` | suppression and `:no_correlation` as attributes (§7) |

Scope-relevant: `satan-tools.el` (registration and the capability token — note
`satan/satan-tools-*.el` does **not** match it, the hyphen is required),
`satan-tools-*.el` (the new tool module), `satan-tools-notify.el` (calls the
moved writer), `satan-custom.el` (`satan-goad-enabled`,
`satan-goad-quiet-hours`), `satan-mode.el`, `satan-percept.el`,
`satan-context.el`, `satan/test/**`.

**Left the surface** since the first design: `satan-sensor-*.el` (no probe leg),
and `satan-sensor-alerts.el` (suppression is an attribute, not an alert).

**Corpus repo** (`~/satan`) — lands together with the above (§4):
`goad/backend.py` (six changes), `goad/README.md`, `tools/goad_ask.md`, and the
one-off day-file conversion.

## Sequencing

PERCEIVE puts the goad record into the evidence window both the percept and
the observer read (§3); PROMPT and the observer legs depend on it. **The
doorbell ships with PROMPT**, not after it: without it `backend.py`'s two-hour
slot poll matures most asks `undelivered` (§5, [[RV-007]] F-22). Its exit code
still carries no meaning.

`backend.py` fixtures come before any of its six changes. It carries the slice
and has no tests.

**SL-018 gates enablement, not construction** (§8). Nothing in this slice
needs an unattended run to be built or verified. SL-018's broker gate has
landed, so unattended asks come only from `tick-pulse` runs that find a live
credential session. Interactive MCP refuses the tool (§2).

## Risks carried, not resolved

| risk | why it is not closed here | where it goes |
|---|---|---|
| **[[ASM-001]] is inference, not evidence** — the option-id round trip is unproven, and `save()` would drop the answer until F-7 lands | proving it requires implementing it | verification item 2 |
| **The correlation loop can break after emit** — SATAN can rewrite or remove the credited motive before maturity ([[RV-007]] F-4) | for kind `"ask"` the correlator reads the emit-time motive, so a break is an explicit `:no_correlation`; honouring the persisted id for every kind changes shared semantics | made perceptible (§2, §7); the all-kinds correlator fix to backlog |
| **The gate constrains what SATAN may ask** — only about what it already perceives (§2) | it is the fix, and it is a real limitation | documented as the operating contract |
| **Whether goad re-evaluates when an `engaged` exchange ends** — a refused ring's question otherwise waits for the next slot | unverified | plan verifies before relying on it (§5) |
| **The autonomous producer needs an authenticating unattended run** — SL-018's `defer` policy (broker gate landed at `723c205`) | SL-018 owns credentials | asks flow only while a credential session is live (§8) |
| **Interactive MCP has no percept** ([[RV-007]] F-12) | repairing run-state coherence is separate | tool refuses there; MCP fix to backlog |
| **`satan-attrd` rejects unknown outcome reasons** ([[ISS-011]]) | cross-repo dependency for the suppression attribute | name it at plan time |
| **`backend.py` has no tests** (R2) | fixtures are phase-one work | §4 |
| **Evidence truncation cap unenforced** ([[ISS-001]]) | pre-existing | keep the contribution compact |

## Out of scope, deliberately

- **Approval gating.** ADR-017 §1 assigns it to Emacs permanently (§8).
- **Any change to the goad host.** If the design finds one unavoidable, that is a
  signal to re-examine the design, not to widen scope.
- **The correlator's motive handling for kinds other than `"ask"`, or MCP
  run-state coherence** — both
  real, both separately owned. ([[ISS-014]] is fixed at `6ff52f7`; the `"ask"`
  branch does not depend on it either way.)
- **Global quiet hours** ([[RV-007]] F-15) — the emission window is goad's own.
- **Reviving the `:staged` action path** (`satan-broker.el:263`) — the approval
  story, not the elicitation one.
- **SATAN rewriting `backend.py` via satan-patcher** — [[IMP-020]]. Note its
  prerequisites move with this slice: `backend.py` gains the fixtures IMP-020
  needed for non-empty `checks`.
- **Widening POL-001's seat clause** — a REV at close (§8).

