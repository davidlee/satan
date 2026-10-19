# ADR-017 §3 Authority Ledger

Companion to [ADR-017](./adr-017.md) — the single, current record of **who owns
each item of SATAN authority**, one owner at a time, updated as authority
migrates out of the Emacs client. Its mandate is ADR-017 §3 ("Authority
inventory with single ownership"); its invariant contract is SPEC-001
(REQ-001..012). Home and format were decided in DEC-003.

This file is *living current-state*, deliberately kept out of the immutable
ADR-017 decision record (DEC-003). It is greppable by construction: the single
`Owner` column and the append-only transition log below make "exactly one owner"
(REQ-008) and "no dual enforcement" (REQ-009 / NF-001) checkable with `rg`, not
tooling that does not yet exist.

**Day one (2026-07-24): every item was owned by `emacs-client`.** The first
migration was SL-023's (2026-10-19): the patch-job duties moved to
`patch-runner` (rows 4b, 5b, 6b, 8, 9; DEC-062). Every other item is still
`emacs-client`'s. The next planned transition is D4.2 (policy/registry →
`daemon-core`) per RFC-017; the worked example under *Transition log* shows its
shape.

## Owner legend

Fixed vocabulary, keyed to the ADR-017 §1 / ADR-018 D1 topology. A token enters
the legend when its component is first received as an owner; `emacs-client` and
`patch-runner` are in use today.

| Token | Component |
|---|---|
| `emacs-client` | The permanent privileged Emacs client (ADR-017 §1) |
| `daemon-core` | The single daemon repository / core (ADR-018 D1) |
| `patch-runner` | Patch-job runner: the `satan-runner` binary in `~/dev/malebolge` (IMP-006, SL-023; was `satan-patcher`, the retired Go repo) |
| `satan-memoryd` | Memory substrate daemon (IMP-007) |
| `satan-audit` | Audit verifier CLI (IMP-008) |
| `satan-attrd` | Attribute / arrival daemon (ADR-002) |

## Ledger

Grain = one independently-ownable duty (DEC-003 / design §7 D2) — the finest unit
at which ownership *could* diverge, not one row per migration (D4.2 moves rows
1–3 together). `Owner` is exactly one legend token. `Governs` cites the SPEC-001
requirement(s) each row enforces (REQ-012 / NF-004 addressability); where no REQ
covers the duty, a governing ADR stands in (INV-2). `Enforced at` is the current
grep anchor — a stable symbol name is authoritative; any line number is advisory
and rots as code moves. On migration this anchor moves to the new site and the
old site is deleted (the cutover proof, REQ-009 / NF-001).

| # | Authority item | Owner | Governs | Enforced at | Since |
|---|---|---|---|---|---|
| 1 | Action schema validation | `emacs-client` | REQ-001 | `satan-tool-validate-args` (satan-tools.el:132); `patch_job_create`'s `mode` is not schema-validated model input — stamped from the tool ctx `:mode-name` (`satan-tools-patch.el`, DEC-068) | ADR-017 |
| 2 | Mode/tool allowlist | `emacs-client` | REQ-002, REQ-006 | mode-spec `:tools` via `satan-mode-register`; consistency `satan-mode-check-tool-references` (satan-mode.el) | ADR-017 |
| 3 | Capability / jail profiles | `emacs-client` | REQ-002 | `satan-profiles` defcustom / `satan-mode--apply-profile` (satan-mode.el) | ADR-017 |
| 4a | Append-only audit → run actions ⚠ | `emacs-client` | REQ-003 | `satan-audit-record` (satan-audit.el:95) | ADR-017 |
| 4b | Append-only audit → patch-job actions | `patch-runner` | REQ-003 | `JobStore.appendEvent` / transition writes, `job_events` append-only triggers (malebolge `src/runner/store.ts`); the job's pi-durable transcript | SL-023 |
| 5a | Token / budget ceiling → run budget | `emacs-client` | REQ-004 | `satan-budget-exceeded-p` (satan-budget.el:67) | ADR-017 |
| 5b | Token / budget ceiling → per-job ceiling | `patch-runner` | REQ-004 | `createModelGate` / `gatedModels` (`model-gate.ts`), `exhausted` (`ceilings.ts`), `armCeilingTimers` (`deadline.ts`); maxima `checkSubmit` → `ceilingsWithinMaxima` (`protocol.ts`) | SL-023 |
| 6a | Kill / disable switches → broker and client switches | `emacs-client` | REQ-005 | `satan-*-enabled` defcustoms; broker halt | ADR-017 |
| 6b | Kill / disable switches → the runner's `enabled` | `patch-runner` | REQ-005 | runner config `enabled` (`config.ts`); `submit` refused `runner_disabled` (`control.ts`); disabled start parks (`recoverHost`, `recover.ts`) | SL-023 |
| 7 | Arrival policy (gating) † | `emacs-client` | ADR-002 † | `satan-tick-quiet-p` / `satan-tick-pick` (satan-tick.el) | ADR-017 |
| 8 | Patch-job lifecycle / queue consumer | `patch-runner` | REQ-001, ADR-018 D3 ‡ | `parseRequest` / `checkSubmit` (`protocol.ts`), `serveControl` (`control.ts`), `createScheduler` (`scheduler.ts`), `JobStore.transition` (`store.ts`) | SL-023 |
| 9 | Per-job path allowlist | `patch-runner` | REQ-002 | authoritative at collection: `classify` / `disallowedPaths` (`classify.ts`) over every commit; early: `jobGuard` `beforeTool` (`guard.ts`); submit: `normaliseAllowedEntry`, and mode scope `withinModeScope` (`protocol.ts`, DEC-069) | SL-023 |

Rows track *duties*, not *delivery mechanisms*: REQ-006 (policy as a read-only
artifact) and REQ-007 (control-plane RPC) are not rows — they surface inside a
row's `Enforced at` as it migrates. REQ-008 (single ownership on transition) is
the ledger itself, not a row.

`patch-runner` anchors are symbols in `~/dev/malebolge/src/runner/` (verified at
malebolge `8c93902`, SL-023 audit RV-029). The Emacs tool's argument schema
for `patch_job_*` stays under row 1 (model-facing); row 8's REQ-001 is the
runner's own full-schema parse of every control-socket operation. Promotion is
an approval surface owned by Emacs (ADR-017 §1), not a row; provider
credentials stay out (DEC-049).

**‡ Row 8 — no REQ covers lifecycle.** ADR-018 D3 stands in for who runs and
moves a job (INV-2); the gap is QUE-001's, as for row 7.

### Standing notes

**⚠ Row 4 — audit is a latent dual-write (a REQ-009 / NF-001 hazard).**
`satan-audit-record` (the Emacs client) *and* the attribute bridge
(`satan-attribute-listener.el` → `transcript.jsonl`) both append audit — ADR-018's
"split authority already realised." This is a no-dual-enforcement
violation-in-waiting: today it is tolerated because both paths run inside the one
`emacs-client` owner, but the migration that gives audit a daemon owner **must**
make exactly one side the sole writer and delete the other, or the row is
malformed.

**Row 4 — operational alarms are not audit writers (SL-017).** Two emits
report SATAN's own state rather than act on the keeper's world, and neither
appends audit. **Failure announcements** (`satan-broker--announce-failure`)
fire after `satan-audit-close` and the `.FAILED` rename; the run bundle
(`status`, `final.json`, transcript, `crash-context`) is their record, and the
pop decision is derived from it. **Listener death reports**
(`satan-attribute-listener--report-death`; the patch listener's
was deleted with the elisp runner in SL-023) happen outside any run, with no audit
handle; their `:journal` line is the only durable trace. Recording them would
need a third audit writer, which this row forbids. Both emit only through
`satan-announce`.

**† Row 7 — trigger vs policy; ADR-002 pending.** The *trigger* is a dumb
external systemd timer (satan-tick.el:4 — "systemd timer fires the broker every
~30 min"); it holds no authority. The *policy* — quiet-hours gating, weighted
mode pick, per-tick budget ceiling — is `emacs-client` in `satan-tick.el`. No
SPEC-001 requirement covers *who may start or gate a run* (lifecycle/arrival
authority), so this row cites ADR-002 in place of a REQ (INV-2 permits it); the
gap is tracked as QUE-001 for the SPEC-001 owner. ADR-002 (still `proposed`)
would move the *policy* to `satan-attrd` as "the only periodic clock" — the
pending transition this row will record if ADR-002 is accepted.

**Provider-credential custody is not a SATAN authority item (SL-022,
DEC-049).** RFC-018 D3 proposed a row 8 (provider credential custody,
`emacs-client` → `auth-gateway`). It is not added. Since SL-022 no SATAN
surface holds or resolves a provider key: the harness and jailed pi reach
models only through the host LLM gateway, and each jail launcher passes its
gateway client key to the child over a file descriptor. The keys and the
gateway are host deployment (`~/flakes/SATAN.md`), so custody left SATAN's
inventory rather than migrating to a new owner, and the legend gains no
`auth-gateway` token. The enforcement sites RFC-018 cited
(`satan-broker-provider-key-vars`, `satan-patch-adapter-pi-api-key-vars`)
are deleted; `rg '_API_KEY|op://|op run|satan-credential' satan/ dev/ flake.nix`
hits only the flake check's probe strings. Gateway key budgets are
deployment insurance caps outside this ledger (DEC-043).

## Transition log

Append-only; one line per owner change, newest last, grouped by row. The
first lines are SL-023's (below the worked example). A migration edits the row's `Owner`
and `Enforced at` *and* appends its transition line in the **same change**
(INV-3); a row whose owner moved without a line is malformed by construction. An
item co-owned across a transition window is *not representable and must not be* —
that is exactly the REQ-009 / NF-001 hazard the single `Owner` column forbids.

**Line format:**

```
↳ YYYY-MM-DD  <from> → <to>  (SL-NNN audit; <old enforcement> deleted; <verification> green)
```

**Worked example — D4.2 (illustrative; not yet transitioned).** RFC-017's first
migration moves schema validation, the mode/tool allowlist, and capability
profiles (rows 1–3) into `daemon-core`. When SL-NNN lands it, each row's `Owner`
becomes `daemon-core`, its `Enforced at` moves to the daemon symbol, and these
lines are appended:

```
row 1  ↳ 2026-MM-DD  emacs-client → daemon-core  (SL-NNN audit; satan-tool-validate-args deleted; `rg satan-tool-validate-args satan/` → 0 hits, daemon-core validate_action green)
row 2  ↳ 2026-MM-DD  emacs-client → daemon-core  (SL-NNN audit; satan-mode-register :tools allowlist deleted; daemon-core policy artifact green)
row 3  ↳ 2026-MM-DD  emacs-client → daemon-core  (SL-NNN audit; satan-profiles / satan-mode--apply-profile deleted; daemon-core profile gate green)
```

The `<from> → <to>` shape is what the audit greps: `rg 'emacs-client → daemon-core'
authority-ledger.md` enumerates every moved item, and the paired "deleted" clause
plus a zero-hit grep at the old site is the REQ-009 / NF-001 "no dual enforcement"
proof.

**SL-023 (2026-10-19).** Rows 4, 5 and 6 split by duty (4a/5a/6a stay
`emacs-client`); rows 8 and 9 are new. Before SL-023 these duties sat with the
elisp patch runner inside `emacs-client`, while the unlisted Go `satan-patcher`
consumed the same queue (ISS-039) — the dual enforcement this ledger forbids.

```
row 4b ↳ 2026-10-19  emacs-client → patch-runner  (SL-023 audit; satan-patch-store event writes and patch_job_events deleted — 0009 applied, `rg -l satan-patch-store satan/` → 0; job_events append-only triggers + store.test green)
row 5b ↳ 2026-10-19  emacs-client → patch-runner  (SL-023 audit; elisp runner timeout deleted with satan-patch-runner.el — `rg -l satan-patch-runner satan/` → 0; model-gate / ceilings-harness tests green)
row 6b ↳ 2026-10-19  emacs-client → patch-runner  (SL-023 audit; satan-patch-runner-enabled deleted — `rg -l satan-patch-runner-enabled satan/ ~/.config/emacs` → 0; runner-main disabled-start tests green)
row 8  ↳ 2026-10-19  emacs-client → patch-runner  (SL-023 audit; elisp runner/store/listener deleted, satan-patcher unit removed and repo archived, patch_jobs dropped — one consumer verified deployed; control/scheduler/store tests green)
row 9  ↳ 2026-10-19  emacs-client → patch-runner  (SL-023 audit; satan-patch-worktree-path-allowed-p deleted — `rg -l` → 0; classify / guard / run tests green)
legend ↳ 2026-10-19  satan-patcher → patch-runner  (SL-023 audit; token renamed, never an owner; DEC-062)
```

## Maintaining this ledger

- **Read** — open this file (linked from ADR-017 §3) or grep it
  (`rg 'emacs-client|daemon-core' authority-ledger.md`).
- **Migrate** — the migrating slice's **audit** phase edits the moved row(s)'
  `Owner` + `Enforced at` and appends the transition line(s); its checklist gains
  "ledger row moved; old-enforcement grep returns zero" (ADR-018 VT-3, generalised
  to every item). Built by the downstream slice, not here.
- **Review** — ADR-017's per-extraction audit reads this ledger as the "authority
  ledger exists and is current" check.

### Invariants (checked by review — this artifact is not machine-gated; design §8 R2)

- **INV-1** — every row has exactly one `Owner` token drawn from the legend.
- **INV-2** — every row cites ≥1 SPEC-001 REQ, or a governing ADR where no REQ
  applies (row 7 → ADR-002).
- **INV-3** — a migration edits `Owner` + `Enforced at` *and* appends a transition
  line in the same change; an owner moved without a line is malformed.

<!-- Ledger stood up by SL-014 (RFC-017 gate G2). Anchors verified present in the
     tree at authoring: satan-tools.el:132, satan-audit.el:95, satan-budget.el:67,
     satan-tick.el:33/43. Line numbers advisory; symbol names authoritative. -->
