# Notes SL-037: signal loss (F1) — hold unsupported outcomes, then add the reason

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## Design triage (2026-11-06, exploring)

Evidence: `research/research.md` (T1 = governance thread, T2 = code map, X =
cross-thread). All claims below cite this artefact's rows.

**Constraining governance (T1).** design-contract §6S/§9/§16/§17 is the binding
wire contract and the slice is its amend. ADR-017 §3 keeps exactly one owner per
authority item: `satan-attrd` remains the authority on what it accepts, so the
broker's list can only ever be a *claim* — the design must not present it as
daemon truth. ADR-018 D5 forbids a new stateful elisp layer, so the hold record
must be argued as a disposable projection (the DEC-005 precedent). POL-001 puts
the gate in the broker and finds no extraction candidate. SPEC-001/SPEC-002 give
no vocabulary requirement; SPEC-002 needs no amend. Checked and ruled out:
ADR-001, RFC-016/017/021, SL-019 (infrastructure), SL-036 (a convention this
slice chooses to adopt, not a rule).

**Shaping facts carried from research:**
- No daemon→broker refusal channel exists; `satan_audit_replies` runs the other
  way (T2, X3). "Discovered vocabulary" therefore *is* O1's handshake.
- `satan-attribute-enqueue` cannot report the daemon's verdict (T2, X4): the gate
  must be predictive, before the enqueue.
- The vocabulary has five sites, not two: broker probe literal, broker audit
  validator (`satan-audit.el:448`), contract §6S.1, contract §6S.5 evidence
  enumerations, daemon enum (X1, X2). `wiring-status.md` is a sixth, non-
  normative.
- No migration: `reason` is `TEXT NOT NULL` with no CHECK (T2) — the slice's
  guess is confirmed.
- Scope to add: `satan/satan-audit.el` and contract §6S.5, which the authored
  scope does not name. Additive; no new authority.
- `DR-005` (the watermark rule) is not resolvable from this checkout: it is a
  frozen-corpus design id. Do not build design prose on it; restate the rule.
  Also: the slice's bare `DEC-5` is *not* `DEC-005`.

**Risks and assumptions still live.**
- Deployment ordering is a release constraint, not a code property: a broker
  constant that gains the reason before the daemon deploys re-opens the loss and
  looks fixed (X6).
- Delta magnitude can re-create the 2026-05-29 curiosity cancellation against
  `segment_backlog` (X7, contract §16).
- "Schema-major refusal vs vocabulary refusal" needs an explicit disposition —
  the gate can only cover vocabulary (X4, inq-8).
- Unverified: the live value of `satan-sensor-content-enabled` on the host
  (no Emacs, no state root in this session) — the slice's own `[verify]`.

**Open questions:** inq-1 … inq-8 in the design run (`doctrine design tree SL-037`),
of which inq-8 is non-blocking. inq-4/inq-5 wait on inq-3; inq-6/inq-7 on inq-2.

## Review and re-scope (2026-11-07)

The user accepted a critical review of the inquiry map: the hold is dropped (`DEC-148`,
superseding `DEC-141`…`DEC-146`; inq-2…inq-7 pruned). `inq-10` reopened the delta row and
settled it: `DEC-149` supersedes `DEC-140`.

Evidence, measured 2026-11-07 on the host:
- `satan_attribute_events`, last 15 days: `segment_backlog` ~23/day, `trace_marked` ~18/day;
  Curiosity reached 1.000 each day, now 0.975; caps on 309 of 690 Curiosity events in 30 days.
- Journal: 66 `content_backlog` rejections in 7 days.
- `sensor-content.json` watermark equals the newest capture, so the probe is enabled.
- `articles.jsonl` has 3,145 rows. 36 end in `Z` (all 2026-05-31…06-01); the rest carry an
  offset, despite the probe's "UTC-millis-Z" comment. Harmless today; lexical order can slip
  in the hour after a DST fall-back.

The triage section above predates this and describes the dropped design.

## Design review (RV-064, 2026-11-07)

Two pi passes (`review` profile) over the broker side. The first raised seven points, the second six on the revised passages. The daemon pass was refused (`form-unapproved`: the approved quotient form for `~/dev/satan-attrd` no longer matches), so the orchestrator read the daemon code itself. That side has had no independent review.

Corrections worth keeping, all from reading the code:
- The live flag does not survive a restart; the interim setting lives under `:custom` in `apps/dl-satan.el`.
- The event row proves only the daemon half. A broker rejection is silent in the broker, and `satan_audit_replies` rows are deleted after logging. The broker half is a transcript line matched on the reason, plus the `satan-attrd` journal.

**A further pass:** none is needed before planning. The last edits were wording, and pi's remaining disputes were resolved. The two checks a further pass would probe are F-3 (control: a broker without the list entry must fail the host check) and F-4 (probe: the flag across a restart). Both are settled by phase criteria, so `/plan` must carry them from the RV ledger. If the quotient form is re-approved, a pi pass over `satan-attrd` would probe sec-4's claims independently; it can run alongside the daemon phase.

## Verification notes

- Zero-hit greps as verification ("the parse-failure line for this reason
  disappears") need a live positive control and `rg`, not ugrep —
  `mem.pattern.satan.rg-not-ugrep-for-rename-verification`.
- `just check` reaches a throwaway Postgres on a socket and refuses if it is
  absent; `SATAN_TEST_ALLOW_NO_DB=1` skips ~142 DB tests (never use it to claim
  green) — `mem.fact.satan.green-is-not-green`.
- Daemon cargo tooling needs the flake devshell (`direnv exec`); the system cargo
  has no rustfmt/clippy — `mem.pattern.satan-attrd.devshell-toolchain`.

## Plan (2026-11-07)

`plan.toml` has four phases; PHASE-01 and PHASE-04 are operator acts that need the user's approval. `RV-064` F-3 and F-4 are transcribed onto criteria. The research advisory reports drift only in the slice and design files, not in code, so `research.md` was not refreshed or restamped. Nothing from this design or plan round is committed.
