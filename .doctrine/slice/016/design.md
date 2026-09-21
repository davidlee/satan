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
   ~/satan/goad/  (corpus repo)              ~/dev/satan/  (mechanism repo)
 +------------------------------+
 | queue.json  (SATAN-authored) |<-(2) PROMPT---- ask tool (consume phase)
 |   a projection, not a record |                  emits kind "ask"
 |   ALSO: the canon trigger    |--(1) PERCEIVE--> evidence assembler
 +------------------------------+                       |
 | data/YYYY-MM-DD.json         |--------------->  canon rule --> handles
 |   presented_at . value . at  |                       |
 |   deferral provenance        |                  the answer, and
 |   intervention_id            |                  non-engagement
 +------------------------------+
 | backend.py  merges, prioritises, stamps, persists  |
 +------------------------------+
        ^ evaluate / respond
   +----+-----+
   | goad host|<-(3) DOORBELL------------ goad-emit via satan-trace-call
   +----------+  a HINT ONLY — see sec-5     timeout-bounded, refusal-aware
```

Three capabilities, each independently useful. **No goad host change** — the
queue lives backend-side, which is what preserves that, and is goad's own
architectural review question #1.

The **queue file is the perceptual trigger** as well as the delivery channel: it
exists exactly when SATAN has something outstanding. Keying the canon rule on the
day record instead deadlocked, because no day record exists until the keeper
answers something ([[RV-007]] F-6).

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
```

## What does not work

`satan-intervention-create` accepts `:cue-handles`, persists it to
`cue_handles_json`, and **no production call site passes it**. That looks like
the hook the correlator forgot to use. It is not: the correlator reads
`bundle.json` and never the column. `cue_handles` feeds
`satan-intervention--counter-memory-handles` (`:518-532`) — the resonance path.
Worth passing for auditability; it will never make an ask correlate.

## SATAN may only ask about what it already perceives

**[[RV-007]] F-5.** The gate as first designed compared live motive cues against
*ambient* percept handles. Neither the question nor its subject took part — so a
generic `app:goad` cue admitted any question on any subject, and where several
motives carried the handle, file order picked which was credited. The gate proved
*some motive overlaps the ambient percept*, which is not a useful claim.

The machinery forces the fix. The percept is frozen at spawn, **before any
question exists**, so a question-specific handle can correlate only if the
question is derived from what is already perceived. Therefore the ask tool
requires:

1. the question to name a handle present in ctx `:percept-handles`; **and**
2. *that* handle — not merely `app:goad` — to appear in the winning motive's cue.

This is a real constraint on what SATAN may ask, and it is the right one: a
question about something outside SATAN's perceptual field is a question it has no
grounds to ask.

## The check is exact at emit

```
satan-percept-build --> percept :handles
     |-> run ctx :percept-handles        (satan-run.el:250)
     |      |-> the ask tool reads it here, at emit
     |      +-> satan-intervention-create reads it here  (:386)
     +-> bundle.json :percept :handles
            +-> the correlator reads it here, at maturity
```

Same list, same arithmetic. With no winner the tool **does not emit** and records
the suppression — SPEC-001 REQ-005/010: an ask that cannot be classified is an
ask whose refusal cannot be perceived.

**Prohibited in interactive MCP** ([[RV-007]] F-12). Interactive sessions mint a
synthetic bundle with no percept and freeze tool context immediately
(`satan/satan-mcp.el:154,177,197`), so `:percept-handles` is nil there and the
maturity bundle has no percept either. The tool refuses in that mode. Repairing
MCP run-state coherence is a separate concern and goes to the backlog.

## The loop can still break, and that is now visible

**[[RV-007]] F-4.** The observer rereads **live** motives on every pass
(`satan/satan-observer.el:383`) and never consults the persisted
`related_motive_id`. `tick-pulse` holds `motive_replace`. So an ask that passed
the gate at emit can still mature `:no_correlation` if SATAN rewrote the motive
in between.

The original phrasing — *correlate by construction* — overclaimed, and detecting
a broken loop is not having an unbroken one. So:

- correlation is asserted **at emit and nowhere else**; the design does not claim
  the loop is closed;
- a goad ask that matures `:no_correlation` is **perceptible**, through the same
  attribute channel as suppression (§7) — the slice's thesis applied to itself.

Making the correlator honour the persisted motive id is the real fix. It changes
shared classification semantics for every kind, so it is backlog work, not this
slice's.

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

The claim that carries the decision is narrow and precise: **no probe and no
post-percept tool can contribute a handle for that run.** A probe writes numeric
pressure to Postgres; a tool result is produced after the percept is frozen.
Neither can put a token in `:handles`, so under either cheap route no
goad-shaped handle exists, no motive cue can overlap one, and every ask
classifies `:no_correlation`.

*(The stronger phrasing "handles exist only for what reaches the evidence window"
is false and was corrected — canon also emits context- and hint-derived handles,
`satan-memory-canon.el:429`. It does not create a missed route. [[RV-007]] F-16.)*

An on-demand `goad_read` tool may supplement for detail, on the `activity_read`
precedent. It carries no weight for the verification intent.

## The trigger is the queue file, not the day record

**[[RV-007]] F-6 — this was a daily deadlock.** The first design keyed the goad
handle on the presence of today's day record, specifically so it would not depend
on window focus. But `backend.py` `load()` returns `{}` when the file is absent
(`:69-74`) and `save()` runs **only on a `respond` request** (`:153`). No day
record exists until the keeper answers something. So before the first answer of
any day there is no handle, no correlation, and every ask suppresses itself —
SATAN could never be the first goad interaction of the day, which is most of what
an autonomous producer is for.

The rule keys on **SATAN's own queue file**, which exists exactly when there is
something outstanding. The handle then means *"SATAN has a question waiting"*
rather than *"goad has state today"* — the more useful thing for a motive to cue
on in any case.

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
anchor and `topic:<Subject>` per outstanding question — and §2 requires the ask
to correlate on the **subject** handle, not the anchor, so the `topic:` emissions
are load-bearing rather than decorative.

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

1. resolves the correlating motive on the **question's subject handle** (§2) and
   **fails closed** if none, recording the suppression;
2. refuses outright in interactive MCP mode ([[RV-007]] F-12);
3. emits an intervention of the reserved kind `"ask"`, passing
   `:related-motive-id` and `:cue-handles`;
4. rewrites the queue projection whole.

`"ask"` is already in the closed intervention-kind set in all three registries
(`satan-memory-grammar.el:72`, `satan-audit.el:233`,
`satan-observer-classify.el:258`) and in `satan-observer-user-facing-kinds`. No
closed set is touched. Emission is an enactment and must appear in the transcript
(SPEC-001 REQ-003).

## The queue is a projection

A question's durable identity is its intervention row ([[DEC-005]]). The queue
file is a **disposable projection** of the open asks, so it belongs under
`satan-state-path`, whose *"discardable"* contract is then exactly right.

One file, rewritten whole and atomically ([[DEC-010]]) — and rewritten at **two**
triggers, not one. The first design specified only the ask handler, but the
observer retires rows independently at classification
(`satan/satan-observer.el:424`), so a matured ask kept its queue entry until some
later ask happened to rewrite the file, and the backend kept re-presenting it
([[RV-007]] F-11). The rewrite therefore also fires at classification. That is
what makes the regenerability property [[DEC-005]] leans on actually hold.

## What `backend.py` must become

**This is the load-bearing part of the slice**, and the first design badly
understated it. "Merge the queue into `pending()`" is four changes, none
optional, to a file with no tests, no fixtures and no check recipe (slice R2):

| # | change | why | finding |
|---|---|---|---|
| 1 | **priority** for SATAN asks in `pending()` | `main()` renders only `waiting[0]`, and `pending()` returns `ITEMS` order — the comment at `:22` says *"Order is ask order."* Behind fourteen checklist entries, an appended question is effectively never shown | F-18 |
| 2 | **`presented_at`** written when an item is actually rendered | the only real delivery proof — see §5 | F-1 |
| 3 | **deferral provenance** | `answer()` writes the same `deferred_at` for `later:` and `enough:` (`:132-146`). Here those are opposite signals, and `enough:` bulk-defers questions the keeper never saw | F-19 |
| 4 | **serialize queued items** | `save()` iterates `ITEMS` alone (`:77-90`), so a SATAN answer would render, mutate the in-memory map, and vanish on write | F-7 |

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

Corpus-side change set: `goad/backend.py` (the four above), `goad/README.md:16`
(the record format), `tools/goad_ask.md`, and the one-off day-file conversion.
The corpus repo is ungoverned by this doctrine corpus, which makes the coupling a
sequencing hazard rather than a governance one — and is why they land together.

<!-- doctrine:section sec-4 -->
# DOORBELL — a hint, and nothing more

SATAN chooses the moment via `goad-emit --source satan --kind K --data JSON`.
`source: "host"` is reserved (goad SPEC-003/R-13).

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

**[[RV-007]] F-1 — the first design got this wrong and the correction is the
reason the doorbell is demoted.** goad replies `accepted` **before** calling the
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
| 1 | the host refused the hint — harmless, the queue still carries the question |
| 2 | the doorbell could not be rung — also harmless, goad polls anyway |

**Delivery is proven by `presented_at`** in the day record (§4, §7) — a stamp only
something that actually ran can write.

## The timeout is mandatory

`goad-emit`'s usage text: *"The host answers when it has judged the event, and
takes as long as that takes; emit sets no deadline of its own. Wrap it if you
need one."* ADR-018's cited failure mode — handlers run synchronously in the
broker's host process — therefore binds. `satan-trace-call`'s `timeout -k 2`
(exit 124 mapped to `:timed-out`, the wrapper's own 125/126/127 never conflated)
is the correct tier, not a nicety.

## A refused doorbell loses nothing

The queue file is the durable carrier and goad polls on its own schedule
(`default_poll` 30m). goad's spacing is a fixed three seconds with two
independent anchors, so a refusal is an edge case. **No retry machinery**:
`retry_after_ms` is advice goad itself reports and never obeys.

This is also why the doorbell can ship last, or not at all in v1 — it optimises
latency over a queue that already works.

<!-- doctrine:section sec-5 -->
# The loop — the answer, and the silence

The positive leg is an observer predicate. The negative leg is **not** the
observer's ack-event path, and getting that wrong is what a 19-finding review
cost.

```
  ask emitted --> queue.json --> backend prioritises --> goad renders
                                                            |
                                            backend writes presented_at
                                                            |
              +---------------------------+----------------+-----------------+
          answered                   Later (explicit)                  nothing,
       value + at + iv_id        deferred_at + provenance            slot elapsed
              |                            |                              |
              v                            v                              v
      predicate fires                 engaged, unanswered          NON-ENGAGEMENT
         :worked                          :unknown                 <-- THE KEYSTONE
```

Every branch is a fact in one file, written by the process that asked the
question. Nothing is inferred from where the keeper's eyes were.

## The positive leg

One entry in `satan-observer--predicates` — an ordered alist of keyword to
function, uniform `(baseline after motive intervention)` signature,
first-fire-wins. It reads the goad day record out of `after`, the assembled
evidence window that §3 already populates, so it needs no database query and no
side channel.

It fires when the record holds an entry carrying this intervention's
`intervention_id` with a `value` present and an `at` **within the declared
outcome window** (§9). Confidence rises to `:high` automatically when it co-fires.

This is the first predicate that is **direct evidence** rather than ambient
inference. The other three ask whether the editor focused, whether a commit
landed, whether a file was visited.

**Not the manual writer.** `satan-intervention-write-manual-outcome` enforces
`--manual-classifications` = `("harmful" "contradicted")`, and its docstring is
the rule: *"Auto kinds (worked/neutral/ignored/unknown) belong to the auto
classifier and must not reach here."* Using it for success would amend an
invariant that exists to keep the two apart and touch authority-ledger row 4.

## Why the negative leg is not the observer's

**[[RV-007]] F-2, F-3, F-17.** The original narrowed `--count-ack-events` by
target surface so `:ignored` would mean *ignoring* rather than *absent*. Four
things were wrong underneath it:

1. **The gate never opens.** `satan-memory-evidence--segments-status` returns the
   **string** `"ok"` (`satan-memory-evidence.el:163-190`, docstring says so) and
   `satan-observer--ack-checked-p` compares it to the **symbol** `'ok` with `eq`
   (`satan-observer-classify.el:271-277`). `(eq 'ok "ok")` is nil. So
   `--count-ack-events` **never runs**, the `:unknown` branch is unreachable, and
   every user-facing intervention firing no predicate classifies `:ignored :low`
   unconditionally. Raised as [[ISS-014]] — a live bug, no longer this slice's
   prerequisite.
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

Non-engagement is **presented, not answered, not deferred, slot elapsed** — all
four facts in the day record and the queue. It needs no panopticon, no compositor
behaviour, no retention policy, and no fix to [[ISS-014]].

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

An ask **is** an intervention. `satan-intervention-create` already persists
`intervention_id`, `run_id`, `ts`, `mode`, `kind`, `message`,
`related_motive_id`, `cue_handles`, `percept_handles`, `expected_outcome`,
`outcome_window_minutes`, `severity`. So D5 is **satisfied, not waived**, and
POL-001's clause is never engaged — the two authorities do not meet.

| tier | holds | where | on loss |
|---|---|---|---|
| record | the ask, as an intervention row | `satan_memory` (Postgres) | the question is gone |
| projection | the open asks, for `backend.py` | `satan-state-path` | regenerate from the rows |
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

- **`presented_at`** — written when an item is actually rendered. The only proof
  of delivery, because `goad-emit` exit 0 does not carry one (§5).
- **deferral provenance** — so an explicit `Later` is distinguishable from a bulk
  `Enough` (§6).

Plus the one-off conversion of the five existing day files, a reviewable commit
since they are corpus-tracked.

## Where the answer lands

Three places, each doing one job ([[DEC-011]]):

1. **the day record** — arrival, keyed by `intervention_id` via the option id
   ([[ASM-001]]);
2. **the percept** — visibility and correlation, via §3;
3. **a memory trace** — durable human-sourced evidence.

**Not the inbox.** The slice names `satan-tools-inbox.el` under deliberate
non-duplication as the incumbent SATAN-to-human surface. The same logic runs the
other way: an answer is human-to-SATAN, which is perception, and perception has a
substrate already.

**The trace is an explicit write by this slice** ([[RV-007]] F-9). The first
design said the answer *"becomes a memory trace ... written under tick-pulse's
existing `memory-write` capability"*. Both halves were wrong: the observer's
trace records intervention id, motive id, predicates, classification and
confidence (`satan/satan-observer.el:131,141`) — **not** the question or the
submitted value — and it writes via `satan-memory-store-mark` directly (`:149`),
not through a capability-gated tool. So the answer trace is designed, with the
question and value in it, on a stated path. If it is not worth its cost, dropping
the third landing place is the honest alternative — a decision, not an omission.

## Where suppression lands

Suppression and a matured `:no_correlation` need a channel of their own: nothing
was asked, so the day record cannot hold it, and an unasked question is not an
enactment so SPEC-001 REQ-003 does not reach it.

**Not a sensor alert** ([[RV-007]] F-8). Alerts are derived **pre-spawn** from a
closed sensor-status table covering only current-window, focus and browser faults
(`satan/satan-sensor-alerts.el:102,322`). Suppression happens later, inside a
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
2. **goad answers writing outcomes by any path other than the existing writer** —
   that touches ledger row 4 (append-only audit), already flagged as a latent
   dual-write hazard. §6 routes the positive leg through a predicate and writes
   no outcome directly.

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

The autonomous producer ships in v1 ([[DEC-006]]). Research delta 9 reported
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
consulted by `satan-tick` **before any mode is selected** (`satan-tick.el:124`),
so it would suppress overnight observer processing, memory work and inbox work —
none of which this slice has any business changing. The window belongs to the ask
path.

<!-- doctrine:section sec-8 -->
# Verification

## Done is a closed loop, observed end to end

| # | claim | how |
|---|---|---|
| 1 | SATAN emits an `"ask"`, it takes priority in `pending()`, and goad renders it without a host change | VT |
| 2 | the keeper answers; the answer is readable and **attributable to the originating intervention** via the option id, and **survives `save()`** | VT — [[ASM-001]]'s round trip |
| 3 | a presented, unanswered, undeferred ask **with the keeper present** is recorded as non-engagement once its slot elapses | VT — the keystone |
| 4 | an explicit `Later` is distinguishable in the record from a bulk `Enough` | VT — without it, item 3 cannot be read |
| 5 | a refused or failed `goad-emit` loses nothing: the question is still asked at the next poll | VT |
| 6 | an ask with no correlating motive is suppressed, and the suppression is perceptible as an attribute | VT |
| 7 | a matured `:no_correlation` is likewise perceptible | VT |
| 8 | the queue projection regenerates totally from the open intervention rows, and retires an entry at classification | VT |
| 9 | `goad_ask` refuses in interactive MCP mode | VT |
| ~~10~~ | ~~sensor watermark advance, seeded with a source-format watermark~~ | **moot** — no probe, no watermark |

## What the reframe bought, tested

Item 3 is the RFC-016 D3 keystone and it is now testable **without a compositor
fixture, without panopticon, and without fixing [[ISS-014]]**. Present an ask,
touch nothing, let the slot pass, read the record. Under the original design it
required a keeper physically absent from the machine, which is not disengagement,
and rested on an ack gate that never opens.

Items 4, 6, 7 and 9 are new, each the consequence of a finding: the record could
not express deferral provenance (F-19), suppression had no mechanism (F-8),
the correlation loop can break after emit (F-4), and interactive mode has no
percept (F-12).

## The outcome window, stated

`outcome-semantics.md:103` recommends 60 minutes for kind `"ask"`; the observer's
evidence window is a fixed 30 (`satan-observer-classify.el:28,80`). The first
design left those to disagree silently and gave the predicate no upper bound
([[RV-007]] F-10).

The design states the `outcome-window-minutes` the ask handler passes, and the
predicate requires the answer's `at` to fall **within** it — so a late answer
cannot register as `:worked` outside the declared window. The reframe reduces the
tension, since the answer comes from the day record rather than from focus
evidence with a 30-minute horizon, but the bound still has to be explicit.

## Test conventions

`satan/test/<module>-test.el` — **not** a top-level `test/`, which the slice's
original selectors named and which does not exist. Tests are
`<prefix>/<behaviour-slug>`. Three fixture idioms exist and all three are wanted:
temp dir plus defcustom rebinding (record and queue paths), `cl-letf` subprocess
stubbing (`goad-emit` without a live host), and `ert-fail` spies on mutating
functions to prove purity (ADR-001 on the perceive leg).

`backend.py` needs fixtures of its own — it has none, and four of the slice's
changes live there.

**A fixture must not build the value under test.** [[ISS-014]] survived because
`satan/test/satan-observer-test.el:682` constructs `sensor_status` as the symbol
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
| `satan-observer-classify.el` | the fourth predicate **only** — the negative path is no longer touched (§6) |
| `satan-tick.el` | the `goad-ask` capability (§8) |
| `satan-attribute.el` | suppression and `:no_correlation` as attributes (§7) |

Scope-relevant: `satan-tools.el` (registration and the capability token — note
`satan/satan-tools-*.el` does **not** match it, the hyphen is required),
`satan-tools-*.el` (the new tool module), `satan-custom.el`
(`satan-goad-enabled`, the emission window), `satan-mode.el`,
`satan-intervention.el`, `satan-percept.el`, `satan-context.el`,
`satan/test/**`.

**Left the surface** since the first design: `satan-sensor-*.el` (no probe leg),
and `satan-sensor-alerts.el` (suppression is an attribute, not an alert).

**Corpus repo** (`~/satan`) — lands together with the above (§4):
`goad/backend.py` (four changes), `goad/README.md`, `tools/goad_ask.md`, and the
one-off day-file conversion.

## Sequencing

PERCEIVE creates the correlation substrate PROMPT depends on. **The doorbell is
genuinely last and genuinely optional** (§5) — it optimises latency over a queue
goad already polls, and it is the only leg whose exit code carries no meaning.

`backend.py` fixtures come before any of its four changes. It carries the slice
and has no tests.

## Risks carried, not resolved

| risk | why it is not closed here | where it goes |
|---|---|---|
| **[[ASM-001]] is inference, not evidence** — the option-id round trip is unproven, and `save()` would drop the answer until F-7 lands | proving it requires implementing it | verification item 2 |
| **The correlation loop can break after emit** — the observer rereads live motives and ignores the persisted id ([[RV-007]] F-4) | fixing it changes classification semantics for every kind | made perceptible (§2, §7); correlator fix to backlog |
| **The gate constrains what SATAN may ask** — only about what it already perceives (§2) | it is the fix, and it is a real limitation | documented as the operating contract |
| **[[ISS-014]]** — every user-facing intervention currently classifies `:ignored :low` unconditionally | a live bug this slice no longer depends on | its own backlog life |
| **Interactive MCP has no percept** ([[RV-007]] F-12) | repairing run-state coherence is separate | tool refuses there; MCP fix to backlog |
| **`satan-attrd` rejects unknown outcome reasons** ([[ISS-011]]) | cross-repo dependency for the suppression attribute | name it at plan time |
| **`backend.py` has no tests** (R2) | fixtures are phase-one work | §4 |
| **Evidence truncation cap unenforced** ([[ISS-001]]) | pre-existing | keep the contribution compact |

## Out of scope, deliberately

- **Approval gating.** ADR-017 §1 assigns it to Emacs permanently (§8).
- **Any change to the goad host.** If the design finds one unavoidable, that is a
  signal to re-examine the design, not to widen scope.
- **Fixing [[ISS-014]]**, the correlator's motive handling, or MCP run-state
  coherence — all real, all separately owned.
- **Global quiet hours** ([[RV-007]] F-15) — the emission window is goad's own.
- **Reviving the `:staged` action path** (`satan-broker.el:239`) — the approval
  story, not the elicitation one.
- **SATAN rewriting `backend.py` via satan-patcher** — [[IMP-020]]. Note its
  prerequisites move with this slice: `backend.py` gains the fixtures IMP-020
  needed for non-empty `checks`.
- **Widening POL-001's seat clause** — a REV at close (§8).

