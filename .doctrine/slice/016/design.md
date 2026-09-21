<!-- doctrine:section sec-1 -->
# Intent

SATAN has never been able to ask the keeper anything. Every SATAN-to-human
surface in the tree is fire-and-forget push — `notify_send` with no `:actions`
callback, `inbox_append`, `proposal_stage`, sway borders, the owned org block.
The inverse exists (`@satan` directives) but the human always originates.
Nothing poses a question and receives a structured answer.

goad is a GUI host that renders whatever a user-owned backend tells it to and
carries the answer back. It already runs as a systemd user unit against
`~/satan/goad/backend.py`. SL-016 makes it SATAN's elicitation surface: read the
keeper's answers as perception, pose SATAN's own questions through the existing
backend, and ring the doorbell when the moment matters.

**Elicit only.** goad never gates a SATAN enactment on a human yes. ADR-017 §1
assigns human-approval flows to the Emacs client permanently; this slice holds
no authority item and adds no ledger row — see §8.

## The shape, corrected

The slice scope drew `data/*.toml → percept / sensor`. That route does not
exist: probes emit numeric attribute pressure into Postgres, and nothing they
read becomes model-readable text or a percept handle. The real shape:

```
   ~/satan/goad/  (corpus repo)              ~/dev/satan/  (mechanism repo)
 +------------------------------+
 | data/YYYY-MM-DD.json         |--(1) PERCEIVE--> evidence assembler
 |   answers . deferrals .      |                       |
 |   intervention_id            |                  canon rule --> handles
 +------------------------------+                       |
 | queue.json  (SATAN-authored) |<-(2) PROMPT---- ask tool (consume phase)
 |   a projection, not a record |                  emits kind "ask"
 +------------------------------+
 | backend.py  merges both      |
 +------------------------------+
        ^ evaluate / respond
   +----+-----+
   | goad host|<-(3) DOORBELL------------ goad-emit via satan-trace-call
   +----------+  /run/user/1000/goad.sock   refusal-aware, timeout-bounded
```

Three capabilities in dependency order, each independently useful. **No goad
host change** — keeping the queue backend-side is what preserves that, and it
is goad's own architectural review question #1.

## Why it matters

[[RFC-016]] diagnoses SATAN's dormancy as an attention-economy failure: the
behaviour layer has been dead since 2026-05-31 and the organism has *"no sense
organ for being ignored"*. Its D3 keystone is that disengagement becomes
perceptible and consequential.

goad supplies that organ. `Later`, `Enough` and an unanswered window are refusal
semantics the protocol already carries. The seat is pre-built: `"ask"` is a
**reserved but unemitted** member of the closed intervention-kind set in all
three registries, and is already in `satan-observer-user-facing-kinds`.

A goad answer is also SATAN's **first direct human-sourced outcome signal**. The
observer's three positive predicates today are all ambient telemetry — editor
focus, a git commit, a `recentf` entry. This one asks what the keeper said.

<!-- doctrine:section sec-10 -->
# The correlation gate

**The load-bearing section.** Everything the slice wants to demonstrate sits
behind one condition the scope document did not acknowledge.

`satan-observer-classify-for-motives` (`satan/satan-observer-classify.el:544`)
ranks motives by intersecting each motive's `:cue` against the intervention's
percept handles. When nothing overlaps — *or the motive list is empty* — it
returns `:unknown :reason :no_correlation` and **`satan-observer-classify` is
never called** (`:587-599`).

```
  handles <- satan-observer--intervention-percept-handles   (:500-509)
  ranked  <- rank motives by |cue & handles|
      |
      +-- ranked non-empty --> satan-observer-classify
      |                          |- predicates run FIRST, first-fire-wins
      |                          +- else classify-negative
      |
      +-- ranked EMPTY -------> :unknown :no_correlation
                                no predicate runs
                                classify-negative never runs
```

So an unanswered ask does **not** classify `:ignored` for free. It does so only
when a motive's cues overlap the originating run's percept handles. Both legs of
the verification intent sit behind this.

## What does not work

`satan-intervention-create` accepts `:cue-handles`, persists it to
`cue_handles_json`, and **no production call site passes it**. That looks like
the hook the correlator forgot to use. It is not: the correlator reads
`bundle.json` and never the column. `cue_handles` feeds
`satan-intervention--counter-memory-handles` (`:518-532`) — the resonance path.
Passing it is worth doing for auditability and resonance; it will never make an
ask correlate. See [[DEC-007]].

## The decision: correlate by construction

The emit-time check is **exact, not approximate**, because it reads the identical
input the correlator will read:

```
satan-percept-build --> percept :handles
     |-> run ctx :percept-handles        (satan-run.el:250)
     |      |-> the ask tool reads it here, at emit
     |      +-> satan-intervention-create reads it here  (:386)
     +-> bundle.json :percept :handles
            +-> the correlator reads it here, at maturity
```

`|cue & ctx:percept-handles|` at emit and `|cue & bundle-handles|` thirty to
sixty minutes later are the same arithmetic over the same numbers. The only free
variable is the motive file.

So the ask tool:

1. reads live motives and intersects each `:cue` against ctx `:percept-handles`;
2. emits only when a motive wins, passing `:related-motive-id` and
   `:cue-handles` for the winner;
3. **does not emit** when none wins, and records the suppression.

Failing closed follows SPEC-001 REQ-005/010: an ask that cannot be classified is
an ask whose refusal cannot be perceived — precisely the failure RFC-016 names.

## Suppression is an outcome, not an early return

An ask tool that silently declines to ask recreates the blindness RFC-016
diagnoses, one level up: SATAN would be mute and unable to notice its own
muteness, and the symptom — nothing in the goad window — is indistinguishable
from a keeper who answers promptly.

Suppression therefore lands as a **throttled sensor alert**, so SATAN perceives
its own condition on the next tick. The throttle is not optional. The condition
is persistent by nature (no motive names `app:goad` until a human writes one),
`tick-pulse` draws roughly five ticks in eight, and an unthrottled signal that
SATAN cannot ask becomes the noise that teaches the keeper to ignore it — the
exact pathology this slice exists to cure.

## The race this leaves open

`tick-pulse` carries `motive_read`, `motive_replace` and `motive-write`. Between
an ask at T and maturity at T+30..60min, SATAN may rewrite the motive that
justified the ask; the correlator then finds no overlap and the ask is orphaned
by its own author.

Nothing here prevents that without changing the correlator, which is out of
scope. Recording `related_motive_id` and `cue_handles` at emit makes it
**detectable**: they are the before-picture, the verdict's `:motive_id` is the
after, and a verifier comparing them catches every decorrelation. [[IMP-002]]
already scopes that cross-check and should gain this as a case.

<!-- doctrine:section sec-2 -->
# PERCEIVE — evidence, canon rule, handle vocabulary

## Why this route and no other

Research framed PERCEIVE as a three-way cost tradeoff. It is a forced move.
`satan-percept-build` (`satan/satan-percept.el:65-67`) is exactly:

```elisp
(let* ((ctx      (satan-percept--canon-ctx prepare mode))
       (evidence (satan-memory-evidence-assemble ctx opts))
       (canon    (satan-memory-canon-canonicalize evidence nil ctx)))
  (list ... :handles (plist-get canon :handles) ...))
```

and `satan-memory-canon-canonicalize` (`satan-memory-canon.el:523-543`)
dispatches registered rules in `satan-memory-canon--rules` over the evidence
window. **Handles exist only for what reaches the evidence window and has a rule
to name it.**

| route | model-readable? | emits handles? | verdict |
|---|---|---|---|
| probe to attribute pressure | no (numeric) | **no** | cannot correlate |
| on-demand `goad_read` tool | yes | **no** — runs after the percept froze | cannot correlate |
| evidence assembler + canon rule | yes | **yes** | the only viable route |

Under either cheap route no goad-shaped handle ever exists, no motive cue can
overlap one, and every ask classifies `:no_correlation` — making the keystone
undemonstrable by construction. See [[DEC-004]].

An on-demand tool may still supplement for detail, on the `activity_read`
precedent. It carries no weight for the verification intent.

## The handle vocabulary is a public surface

Not an implementation detail: a motive author has to write a `:cue` that matches
it. Two hard constraints.

**Cue tokens are full canon handles, not bare words.** `satan-motive--parse-cue`
splits the `:cue:` footer on whitespace and `--cue-handles-well-formed-p`
requires every token to match the canon handle regex
`[a-z][a-z0-9_]*:[A-Za-z0-9][A-Za-z0-9_.+>-]*`. A motive cues `app:goad`, not
`goad`.

**The namespace is not free.** `satan-motive--admitted-namespaces`
(`satan-motive.el:83-92`) is a **closed allowlist**:

```
app  surface  surface_transition  domain_kind  domain_transition
bough_event  bough_node  bough_project  artifact  topic  phase  focal_app
```

`--cue-admittable-p` requires at least one cue handle whose namespace is in that
set; without one the motive is `:invalid-cue` and parses **dormant**, so it never
reaches the correlator. The docstring gives the reason: *"Without >=1 handle from
this set a motive triggers on every tick — defeats the cooldown floor."*

**So minting a `goad:` namespace does not work.** The canon rule emits into
admitted namespaces: `app:goad` as the anchor, `topic:<Subject>` for per-item
subject matter so a motive about a specific concern correlates. Widening the
allowlist edits a closed set that exists to protect the cooldown floor, and this
slice does not need it.

## The timing trap

Canon already emits `app:<id>` and `surface:<...>` from `current_window.app_id`
(`satan-memory-canon.el:256-271`). So `app:goad` arrives free — **when goad has
focus**. SATAN asks precisely when it does not, so the free handle is absent at
the moment correlation is evaluated for a new ask.

The new canon rule must therefore emit a goad handle from **the presence of the
day record**, independently of window focus. The free one is a bonus at answer
time, not the mechanism.

## Purity, placement, and the watermark that is not there

ADR-001 requires perceive to be pure — its only write is `percept.json` — and
fixes the integration point: there is exactly one percept builder, and the goad
reader plugs into it rather than becoming a second constructor.

Because this is evidence-window inclusion rather than a probe, **there is no
watermark**. R1's timestamp-format trap — comparing goad's local-offset
microsecond ISO against a formatted `...Z` under `string<` — is avoided by
construction, and the slice's verification-intent item 5 is moot as written. It
returns the moment a probe leg is added.

The contribution must be **compact by construction**: it costs tokens on every
run, and the evidence truncation cap is unenforced ([[ISS-001]]).

<!-- doctrine:section sec-3 -->
# PROMPT — the ask, the queue projection, the landing

## The tool

One `satan-tool-register` spec: `:name`, `:risk`, `:capability`, `:args-schema`,
`:handler` (SPEC-001 REQ-001/002 want the schema and the capability, not just a
handler). The handler:

1. resolves the correlating motive (§2) and **fails closed** if none;
2. emits an intervention of the reserved kind `"ask"` via
   `satan-intervention-create`, passing `:related-motive-id` and `:cue-handles`;
3. rewrites the queue projection whole.

`"ask"` is already a member of the closed intervention-kind set in all three
registries — `satan-memory-grammar.el:72`, `satan-audit.el:233`,
`satan-observer-classify.el:258` — and already in
`satan-observer-user-facing-kinds`. No closed set is touched.

Emission is an enactment and must appear in the transcript (SPEC-001 REQ-003 —
the `notify_send` precedent audits even at risk `low`). The keeper's *answer* is
percept data and is audited only where it writes an outcome.

## The queue is a projection, not a record

Under [[DEC-005]] a question's durable identity is its existing intervention row.
The queue file is a **disposable projection** of the open-ask rows, so it belongs
under `satan-state-path`, whose documented contract — *"discardable: nothing
below it is authored or versioned"* — is then exactly right rather than an
uncomfortable fit.

One file, rewritten whole and atomically ([[DEC-010]]):

| | |
|---|---|
| **total by construction** | every rewrite produces the complete open set; no stale entry survives |
| **no reaping** | a directory of per-question files needs deletion on answer, expiry and withdrawal, from two processes — every missed case is a question re-asked after it was answered |
| **no new idiom** | `backend.py` already rewrites the day record whole on every answer |
| **recovery is regeneration** | rewrite from the open rows and the file is correct; this is the property [[DEC-005]] rests on, so it is a test, not a sentence |

## Two repos, one landing

`satan-tool--description` reads the model-facing description from a file in the
**corpus** repo and **signals when it is missing** (`satan/satan-tools.el:208-209`),
and the manifest is built per-spawn. Landing `goad_ask` in the mechanism repo
without simultaneously landing `~/satan/tools/goad_ask.md` in the corpus repo
**breaks every run of every mode that allowlists it**.

The corpus-side change set is therefore part of the same landing, not a
follow-up:

- `goad/backend.py` — merge the queue into `pending()`; echo `intervention_id`
  into the day record ([[ASM-001]]); JSON serialization with an atomic write
  ([[DEC-009]]);
- `goad/README.md:16` — the record format;
- `tools/goad_ask.md` — the tool description.

The corpus repo is ungoverned by this doctrine corpus: nothing in ADR-001/017/018,
POL-001 or SPEC-001 reaches `backend.py`. That makes the coupling a sequencing
hazard rather than a governance one, and it is why the two land together.

`backend.py` has no tests, no fixtures and no check recipe (slice R2). goad
degrades safely on a backend fault — the host does not crash — but prompts stop,
and goad's own field notes record that *"waiting and dead look the same"*.
Fixtures come before the merge.

<!-- doctrine:section sec-4 -->
# DOORBELL — the shell-out and its failure posture

SATAN chooses the moment via `goad-emit --source satan --kind K --data JSON`.
`source: "host"` is reserved to the host (goad SPEC-003/R-13); `data` is opaque
and reaches the backend whole (R-11), so it can carry `intervention_id`.

## The contract is three exit codes

From `~/dev/goad/crates/goad-emit/src/main.rs`, the doc comment on `exchange`
and its three arms:

| exit | meaning | output |
|---|---|---|
| 0 | the host took it | **silent** — success prints nothing (goad 005/D-7) |
| 1 | the host refused it and said why | one stderr line: `goad-emit: refused: <reason>[ retry_after_ms=N][ (detail)]` |
| 2 | emit got no usable answer — usage, configuration, nothing listening, an inadmissible reply | one stderr line |

The reason **token is first, deliberately** (`render.rs:59`: *"so a wrapper can
branch on it"*).

## The ledgered tier is sufficient

Research concluded the doorbell would need the raw two-buffer `call-process`
pattern plus new refusal-parsing mechanism with no template in the tree, because
`satan-trace-call` "returns stdout only and discards stderr".

That is false, and [[EVD-002]] records the correction. `satan-trace-call`
(`satan/satan-trace.el:227-266`) calls `call-process` with DESTINATION `t`, which
**mixes stderr into the same buffer**:

```
$ emacs --batch --eval '(with-temp-buffer (let ((exit (call-process "sh" nil t nil "-c" "echo OUT; echo ERR 1>&2; exit 1"))) (princ (format "exit=%s buffer=%S\n" exit (buffer-string)))))'
exit=1 buffer="OUT\nERR\n"
```

It returns `(:exit N :stdout STR :timed-out BOOL)`, so `:exit` alone carries the
accepted/refused/faulted tri-state, and the refusal line rides along in
`:stdout`. Unambiguous because success is silent and a refusal writes exactly one
line and nothing to stdout — the buffer holds at most one line, ever.

**So: no raw two-buffer fallback, no structured-refusal parser, no new
mechanism.** Branch on the exit code; the reason token is available for the
ledger.

## The timeout is mandatory

`goad-emit`'s own usage text: *"The host answers when it has judged the event,
and takes as long as that takes; emit sets no deadline of its own. Wrap it if you
need one."* It will block while the host deliberates.

ADR-018's cited failure mode — handlers run synchronously in the broker's host
process — therefore binds for real. `satan-trace-call`'s `timeout -k 2` wrapper
(SIGKILL two seconds after SIGTERM, exit 124 mapped to `:timed-out`, the
wrapper's own 125/126/127 never conflated with a timeout) is the correct tier
rather than a nicety.

## A refused doorbell loses nothing

The doorbell is a **hint**; the queue file is the durable carrier. goad's spacing
is a fixed three seconds with two independent anchors, so a refusal
(`too_soon`, `engaged`) is an edge case rather than a routine loss — milder than
the slice scoped in R3. There is **no retry machinery**: `retry_after_ms` is
advice goad itself reports and never obeys, and the question is still asked at
the next slot because it is still in the queue.

## Fail closed

SPEC-001 REQ-005/010: a dead `backend.py` or an unreachable socket must suppress
asking, never bypass. Exit 2 is that case and it is distinguishable from a
refusal, which is why the tri-state matters. The governed idiom is a
`satan-goad-enabled` defcustom (authority-ledger row 6), independent of the
`goad-ask` capability so the two switches do not collapse into one.

<!-- doctrine:section sec-5 -->
# The observer loop — both legs

OQ-4's resolution settled the positive leg and was assumed to be the whole
observer change. It is not. [[DEC-012]] does both.

```
                    satan-observer-classify
                             |
             predicates run FIRST, first-fire-wins
                             |
  +--------------------------+---------------------------+
  | :goad_answer_observed fires                          | none fire
  |   the keeper answered this ask                       |
  v                                                      v
:worked                                    satan-observer-classify-negative
(:high if it co-fires                                    |
 with a git commit)                   ack-events, NARROWED to target surface
                                                         |
                       +-----------------+---------------+------------+
                goad focus, no answer   no focus anywhere      focus elsewhere,
                 (Later / Enough)        (keeper away)          none on goad
                       v                     v                       v
                :unknown :low           not :ignored         :ignored :medium
                engaged, unanswered      -- absent            <-- THE KEYSTONE
```

## The positive leg

One entry in `satan-observer--predicates` — an ordered alist of keyword to
function with the uniform `(baseline after motive intervention)` signature,
first-fire-wins for the recorded `:predicate` slot. Adding a positive signal is
one entry plus one function; confidence rises to `:high` automatically when two
or more fire.

It reads the goad day record out of `after` — the assembled evidence window,
which §3 already puts there — so it needs no database query and no side channel.
It fires when the record holds an entry carrying this intervention's
`intervention_id` with a `value` present and an `at` strictly after
`intervention_emitted_at`.

This is the first predicate that is **direct evidence** rather than ambient
inference. The other three ask whether the editor focused, whether a commit
landed, whether a file was visited.

**Not** the manual writer. `satan-intervention-write-manual-outcome` enforces
`--manual-classifications` = `("harmful" "contradicted")` and its docstring is
the rule: *"Auto kinds (worked/neutral/ignored/unknown) belong to the auto
classifier and must not reach here."* Reaching for it to record success would
amend an invariant that exists to keep the two apart, and would touch
authority-ledger row 4 — already flagged as a latent dual-write hazard. The
disjointness is guarded on both sides.

## The negative leg was inverted

`satan-observer--count-ack-events` (`:278-290`) counts **any** focus segment
after the emit — its own comment: *"v1 does not narrow by surface ... A stricter
surface mapping is a follow-up."* And `classify-negative` (`:300-345`) awards
`:ignored` only on `ack-events-found = 0`. Composed, during any working day:

| keeper | focus segments | verdict today | should be |
|---|---|---|---|
| answered | yes | (predicate fires) | `:worked` |
| pressed Later | yes | `:unknown :low` | `:unknown :low` — correct |
| present, never looked | yes, elsewhere | `:unknown :low` | **`:ignored`** |
| away from the machine | none | `:ignored :medium` | not `:ignored` — absent |

`:ignored` today means **the keeper was absent**, not that they ignored
anything. Verification-intent item 3 would have passed only by testing the
keeper being away, which is not disengagement.

## The fix, and why it stays contained

Narrow ack-event counting by target surface: for an ask on the goad surface,
only a goad focus segment counts as acknowledgement. Focus segments carry
`app_id`, and canon already derives `app:` and `surface:` handles from
`current_window.app_id`, so the mapping has a real key to match on.

The mapping starts **empty for every existing kind**, and a kind with no mapping
counts any segment exactly as today. No currently-emitted intervention
reclassifies. That is what makes this a slice-sized change to a shared classifier
rather than a recalibration of the whole observer.

Additionally: split **absent** from **ignoring**. Both counts are already in hand
at the branch, and away-at-lunch versus saw-it-and-did-nothing are different
facts about the keeper that this slice's entire thesis depends on telling apart.

`satan-observer--ack-checked-p` still gates everything: when the focus probe is
not `ok`, presence and absence are both unassertable and the verdict stays
`:low`. The negative leg degrades fail-soft if panopticon is unreachable.

## Deferral needs no new code

`Later` and `Enough` write `deferred_at` without `value`, so the predicate does
not fire; pressing the button produces a goad focus segment, so the ask lands
`:unknown :low` — the correct verdict for engaged-but-not-answered. Per goad
SPEC-001/R-58, to distinguish *unanswered* from *false* the field is **omitted
rather than defaulted**.

<!-- doctrine:section sec-6 -->
# State, data, and where the answer lands

## No new stateful layer

ADR-018 D5 (*"no new stateful layer lands in elisp"*) and POL-001's
anti-candidate clause (*tiny single-file state stays*) appear to conflict for
this slice, and ADR-018 VA-4 is checked at design review. [[DEC-005]] dissolves
the conflict rather than adjudicating it: the state SL-016 appeared to need
already exists.

An ask **is** an intervention. `satan-intervention-create` already persists
`intervention_id`, `run_id`, `ts`, `mode`, `kind`, `message`,
`related_motive_id`, `cue_handles`, `percept_handles`, `expected_outcome`,
`outcome_window_minutes`, `severity`. No field of a goad question is
unrepresented. So D5 is **satisfied, not waived**, and POL-001's anti-candidate
clause is never engaged — the two authorities do not actually meet.

## Three tiers

| tier | holds | where | on loss |
|---|---|---|---|
| record | the ask, as an intervention row | `satan_memory` (Postgres) | the question is gone — the durable tier |
| projection | the open asks, as `backend.py` input | `satan-state-path` | regenerate from the rows |
| answer | the keeper's reply, per item | goad's `data/*.json` | goad's concern, corpus-tracked already |

No tier holds what another is responsible for, so none can disagree in a way
that matters — SPEC-001 REQ-009's no-dual-enforcement shape applied to data
rather than authority.

## The record format becomes JSON

The day file is **not** a goad contract. goad's invariant is that the host
understands interaction and the backend owns all domain meaning and persistence,
and `backend.py`'s own docstring says *"items, sections, slots and the record
format are all this file's business"*. The goad host never reads it; the only
other mention anywhere is `README.md:16`.

So rather than hand-roll an elisp TOML reader against a grammar SATAN does not
own — there is no TOML parser in the tree, none on the load path, and adding one
would be the first elisp package dependency, contradicting `satan.el:5` —
`backend.py` emits JSON and SATAN reads it with the built-in
`json-parse-buffer` ([[DEC-009]]).

`save()` today (`:77-90`) is a hand-written TOML serializer including a
three-branch value renderer, ending in a non-atomic `Path.write_text`. It becomes
a `json.dump` through tmp+rename; `load()` drops `tomllib`. **The file gets
shorter.**

The atomicity is not incidental: SATAN reads this file from the broker process
at percept-build time, on a ~30 minute tick, while the keeper may be answering.
A torn read is a malformed record reaching the canon rule. Research assumed
tmp+rename was already in place; it is not.

Cost: a one-off conversion of the five existing day files (2026-09-14 through
2026-09-21). They are corpus-tracked, so it is a reviewable commit.

The sidecar alternative was rejected: two files holding one state is a
divergence class that must then be detected and reconciled, bought for the
benefit of a human-readable artifact whose actual human-facing surface is the
goad window.

## Where the answer lands

Three places, each doing one job ([[DEC-011]]):

1. **the day record** — arrival, keyed by `intervention_id` ([[ASM-001]]);
2. **the percept** — visibility and correlation for the run, via §3;
3. **a memory trace** — durable, resonatable human-sourced evidence.

**Not the inbox.** The slice already names `satan-tools-inbox.el` under
deliberate non-duplication as the incumbent SATAN-to-human surface. The same
logic runs the other way: an answer is human-to-SATAN, which is perception, and
perception has a substrate already. Routing an answer to the inbox would mean
SATAN writing to itself through a surface built for writing to the keeper.

**Not a manual outcome write.** See §6.

The trace is written under `tick-pulse`'s existing `memory-write` capability, so
the answer path needs no new capability. It earns a trace because the observer's
other positive signals are all ambient inference; this is the first time the
keeper tells SATAN something deliberately, in a system whose whole premise is
that it is starved of exactly this.

**Suppression** — wanting to ask with no correlating motive — cannot land in the
day record, because nothing was asked. It lands as a throttled sensor alert
(§2). It is not audited: an unasked question is not an enactment, so SPEC-001
REQ-003 does not reach it.

<!-- doctrine:section sec-7 -->
# Governance posture

## No authority item, no ledger row

ADR-017 §1 assigns human-approval flows to the Emacs client **permanently**, and
the authority ledger has all seven rows at `emacs-client` with nothing migrated.
goad is a **data-plane** surface: it elicits, it never blocks a SATAN enactment
on a human yes. This slice therefore holds no authority item and adds no row.

Two named triggers would flip that, and the design avoids both by construction:

1. **goad gating an enactment** — §1 assigns that to Emacs permanently; it would
   need an ADR amendment, not a slice decision.
2. **goad answers writing outcomes by any path other than the existing writer** —
   that touches ledger row 4 (append-only audit), already flagged as a latent
   dual-write hazard. §6 routes the positive leg through a predicate and writes
   no outcome directly, so the hazard never arises.

**Elicit-only exempts the new tools from the *authority* question, not the
*protocol* one** (ADR-017 §2). The ask and the doorbell are enactments and
inherit the full invariant set: schema-validated actions, allowlists,
append-only audit, ceilings, kill switches.

SPEC-001 REQ-011 is the clause most on point, because goad is a new surface:
invariants hold regardless of initiating surface. That forbids a "goad
shortcut" — an answer must not cause enactment outside the
validated/allowlisted/audited path. It is what makes elicit-only load-bearing
rather than stylistic.

(SPEC-001 is `draft` with `pending` requirements. Its authority is derivative:
the REQ ids are addressable names for constraints ADR-017 §2 already imposes,
not independently accepted law.)

## POL-001: the No branch, explicitly

A1 assumed the SATAN-side code earns its seat as a thin shell, on the
`satan-tools-{notify,sway,activity,agenda}.el` precedent. **A1 is falsified.**
The 2026-07-22 amendment says why those keep their seats:

> They earn the seat because **the human's editing surface is where their output
> lands and where the keeper approves it**, not because they need an Emacs image
> to compute.

The rationale is the destination of the output, not the thinness of the shell.
goad renders in its own window, under its own host. The precedent's load-bearing
clause does not extend there.

Applying the test — *does it use the editor as an editor?* — the goad reader, the
ask tool and the doorbell use no org parsing or writing, no denote naming, no
buffer manipulation, no dired/`find-file`/`recentf`, no interactive `satan-*`
command, no compile-angel hook, and take no approval at the keeper's editor.
**The answer is No.**

No is not the same as now. POL-001's No branch makes a module *eligible* for
extraction when carving becomes cheaper than hosting it, and Verification gates
it on four triggers — imminent surface growth, a recurring language/runtime-fit
bug, a reviewer reading elisp to evaluate non-elisp work, tests dominating
`emacs --batch` CI cost — closing with *"Absent any trigger, leave it."*

**None fires.** The surface is being created small and bounded; there is no
recurring bug in code that does not exist; no reviewer is blocked; the tests are
a handful. So the modules stay in elisp as **recorded tenants, not residents**
([[DEC-008]]).

Consequences: they travel with the observer/memory extraction ([[IMP-009]],
[[IMP-007]]) rather than anchoring to Emacs, and ADR-018 D4's ordering should
know the goad reader rides along.

The seat clause genuinely does not contemplate a second human surface that is
not the editor. That gap is real and **predates this slice**; widening it here
would be governance by implementation. It is logged as a revision candidate for
`/reconcile` at close, with two others research found: `.doctrine/state/boot.md`
still saying the protocol tech spec and authority ledger are "not written yet"
when both exist, and RFC-017 D1 rows G1/G2 reading "not written" when both
landed.

## ADR-018

- The doorbell runs synchronously in the broker's host process and is
  `timeout(1)`-bounded (§5).
- D5 on state is satisfied, not waived (§7).
- Adding a capability and tools **enlarges the `satan-mode.el` mode/tool/
  capability table that D4.2 names as the first authority item to migrate**. The
  slice makes that table slightly bigger; saying so here is cheaper than
  discovering it at migration.

## Autonomy and its cost

The autonomous producer ships in v1 ([[DEC-006]]). Research delta 9 reported
`tick-pulse` holds neither `notify` nor `inbox-write`, citing
`satan-mode.el:146-154` — which is `self-edit-mech`'s spec. `tick-pulse` is
registered at `satan/satan-tick.el:95` from the `satan-tick-register` defaults
(`:60-88`), whose capabilities are `(notify inbox-write memory-write
motive-write)`. It already holds both, and carries `motive_read`/`motive_replace`
— which is what makes §2's correlation check performable in the mode that emits.

A **distinct** `goad-ask` capability, not a reuse of `notify`: reusing it gives
one switch for two behaviours, so disabling goad would silence all notification
and re-enabling notification would silently re-arm goad.

And the hazard this exposes:

```elisp
(defcustom satan-tick-quiet-hours nil ; was '(22 . 7); disabled while iterating
```

Quiet hours are **off**, and a systemd timer fires the broker every ~30 minutes.
Today that is harmless because every tick surface is ambient — a sway border, an
inbox line, an org block. A doorbell is not ambient: it draws a window. A slice
that answers RFC-016 by earning the right to interrupt, and then interrupts at
3am, spends the attention it was built to conserve. **Restoring the window is in
scope, not a follow-up.**

<!-- doctrine:section sec-8 -->
# Verification, and what the scope got wrong

## Done is a closed loop, observed end to end

| # | claim | how |
|---|---|---|
| 1 | SATAN emits an `"ask"` and the question reaches the goad window without a goad host change | VT — queue projection merged by `pending()`, rendered |
| 2 | the keeper answers; the answer is readable by SATAN and **attributable to the originating intervention** | VT — [[ASM-001]]'s round trip; the test that assumption reduces to |
| 3 | an unanswered prompt matures and classifies `:ignored` — **with the keeper present** | VT — the keystone; see below |
| 4 | a refused `goad-emit` loses nothing: the queued question is still asked at the next slot | VT — exit 1 is not a failure path |
| 5 | ~~sensor watermark advance, seeded with a source-format watermark~~ | **moot** |
| 6 | an ask with no correlating motive is suppressed, and the suppression is perceptible | VT — new, from §2 |
| 7 | the queue projection regenerates totally from the open intervention rows | VT — new; the property [[DEC-005]] rests on |

## Three corrections to the scope's verification intent

**Item 3 needed restating.** As scoped it reads *"an unanswered prompt matures
and classifies `:ignored` through the existing observer path"*. Through the
existing path, `:ignored` requires zero focus segments anywhere — so the test
would have passed by parking the keeper away from the machine, which is absence,
not disengagement. §6 narrows ack-events by surface so the claim becomes what it
was always meant to be: **present, saw it, did nothing**. That is the RFC-016 D3
keystone and it is now testable as itself.

**Item 5 is moot as written.** It presupposes a watermarked sensor. §3 takes the
evidence-window route, which has no watermark, so R1's timestamp trap is avoided
by construction rather than tested. It returns the moment a probe leg is added —
and [[mem.pattern.satan.sensor-watermark-format]] is the standing guard if one
ever is.

**Two claims are new**, both consequences of decisions taken here: the
suppression signal (6) and projection regenerability (7). Neither was visible at
scoping time.

## Test conventions

`satan/test/<module>-test.el` — **not** a top-level `test/`, which the slice's
selectors named and which does not exist; corrected at §10. Tests are
`<prefix>/<behaviour-slug>`. Three fixture idioms are already built and all
three are wanted here: temp dir plus defcustom rebinding (the day record and
queue paths), `cl-letf` subprocess stubbing (`goad-emit` without a live host),
and `ert-fail` spies on mutating functions to prove purity (ADR-001 on the
perceive leg).

The three-way observer outcome is **three fixtures, not one**: answered fires
the predicate; deferred produces a goad focus segment and no fire; present-but-
untouched produces focus elsewhere and none on goad.

## Two traps that make green not green

- The suite **refuses to run** without `SATAN_DB_HOST` or
  `SATAN_FAILOVER_TO_SYSTEM_DB` (`dev/satan-test.el:73-77`), and DB tests
  `skip-unless` reachable — so a fresh checkout silently skips ~130 tests and
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
| `satan-memory-evidence.el` | goad day record joins the evidence window (§3) |
| `satan-memory-canon.el` | the canon rule emitting `app:goad` + `topic:` handles (§3) |
| `satan-observer-classify.el` | the fourth predicate **and** ack-event surface narrowing (§6) |
| `satan-tick.el` | the `goad-ask` capability; quiet-hours restoration (§8) |

Scope-relevant: `satan-tools.el` (registration and the capability token — note
`satan/satan-tools-*.el` does **not** match it, the hyphen is required),
`satan-tools-*.el` (the new tool module), `satan-custom.el`
(`satan-goad-enabled`), `satan-mode.el` (capability vocabulary),
`satan-intervention.el` (ask emission), `satan-percept.el`, `satan-context.el`,
`satan/test/**`.

The scope's selectors named `test/**`, which does not exist, and
`satan-sensor-*.el`, which targets the probe route §3 does not take. Both
removed; `selector doctor` reports healthy.

**Corpus repo** (`~/satan`) — lands together with the above (§4):
`goad/backend.py`, `goad/README.md`, `tools/goad_ask.md`, and the one-off day
file conversion.

## Sequencing

The three capabilities are independently useful and strictly ordered:
**PERCEIVE** creates the correlation substrate that **PROMPT** depends on;
**DOORBELL** is an optimisation over a queue that already works by polling
(goad's `default_poll` is 30m). Nothing forces the doorbell into the first
phase.

`backend.py` fixtures come before the `pending()` merge — it has none today, and
a backend fault stops prompts silently.

## Risks carried, not resolved

| risk | why it is not closed here | where it goes |
|---|---|---|
| **[[ASM-001]] is inference, not evidence** — the `intervention_id` round trip is unproven, and `backend.py` has no tests to catch it failing. [[DEC-005]]'s whole no-new-layer argument rests on it. | proving it requires implementing it | verification item 2 promotes it to evidence |
| **The decorrelation race** — `motive_replace` between emit and maturity orphans an ask. | unfixable without changing the correlator, which is out of scope | detectable via `related_motive_id`; [[IMP-002]] is the home for the cross-check |
| **Suppression alert flooding** | needs a cooldown policy, not just a switch | §2; specify the floor at plan time |
| **Quiet hours are off** | a doorbell at 3am inverts the slice's thesis | §8 — in scope for this slice |
| **Two repos, one landing** | a tool without its corpus description breaks every run of every allowlisting mode | §4 — one landing, not a follow-up |
| **Evidence truncation cap unenforced** ([[ISS-001]]) | pre-existing | keep the goad contribution compact by construction |

## Out of scope, deliberately

- **Approval gating.** ADR-017 §1 assigns it to Emacs permanently (§8).
- **Any change to the goad host.** If the design finds a host change
  unavoidable, that is a signal to re-examine the design, not to widen scope —
  goad is separately governed with its own ADRs and specs.
- **Reviving the `:staged` action path** (`satan-broker.el:239` logs
  `action-staged` and discards the plist). A real dead hole, but it is the
  approval story, not the elicitation one.
- **SATAN rewriting `backend.py` via satan-patcher** — [[IMP-020]]. Its hard
  blocker is cleared, but `backend.py` still needs fixtures so a patch job's
  `checks` are non-empty, and the job must target the **corpus** repo with
  repo-relative `allowed_paths`.
- **Retiring the four-button shape** or the `ITEMS`-as-code list; reporting over
  `data/`.
- **Widening POL-001's seat clause** — a REV at close, not a slice edit (§8).

