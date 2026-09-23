<!-- doctrine:section sec-1 -->
## 1. Problem and shape

Scheduled runs resolve their provider key late, inside `satan-broker--spawn`,
through `my/op-read-env` wrapped in `(condition-case _ … (error nil))`. With no
1Password session, the read either raises an unattended dialog or fails silently
into `KEY not set` (ISS-012). A rotated key is replayed from `my/op--cache`
forever. The patch adapter repeats the same path under `ignore-errors`.

This design makes "can this unattended run get a key?" an explicit, recorded,
per-mode decision taken **before the run is allocated**, through a seam SATAN
owns (DEC-020, DEC-021, DEC-022).

```
satan-broker-run MODE
  │
  ├─ busy? (a child is live) ── yes → skip acquisition (verdict nil)
  ├─ acquire (sec-3)            satan-credential-acquire VARS POLICY CONTEXT
  │     literal / cached ─────────────────────────────┐
  │     session-p (op whoami)? ── yes → read (silent) ┤
  │     policy (sec-4):                               │
  │        prompt → read (dialog, may block) ─────────┤→ (:env …)
  │     any backend error / failed read ─────────────→ (:unavailable ERR)
  │        defer  ───────────────────────────────────→ (:deferred)
  │
  ├─ satan-run-new-ctx          run_id / time_now allocated AFTER acquisition
  ├─ perceive                   unconditional (ISSUE-001)
  └─ cond: perceive_failed │ session_blocked │ run_busy │ budget_denied
           │ credential_deferred   (no rename, no pop; journal line)
           │ credential_unavailable (.FAILED, DEC-015 back-off)
           │ spawn with (:env …)
```

Two repos change: `~/dev/satan` (policy, gate, seam) and
`~/.emacs.d/lisp/dl-secret.el` (the 1Password backend).

<!-- doctrine:section sec-2 -->
## 2. Credential seam (DEC-021)

New module `satan/satan-credential.el` owns the seam, reference recognition,
scrubbing and the acquisition algorithm. It knows nothing about 1Password
beyond a reference syntax it owns as a setting.

**Reference recognition is SATAN's** (RV-013 F-1):

```elisp
(defcustom satan-credential-ref-regexp "\\`op://"
  "A value matching this is a credential reference, never a literal key.")
```

**Backend protocol.** One function variable, four operations (DEC-021):

```elisp
(defcustom satan-credential-function nil
  "Backend called as (OP &rest ARGS); nil means no backend.")
```

| OP | args | returns | may prompt? |
|---|---|---|---|
| `lookup` | REF | cached plaintext or nil; no subprocess | no |
| `session-p` | — | non-nil when a session is live | no |
| `read` | REF CONTEXT | plaintext; signals on failure | **yes** |
| `forget` | REF | — (evicts REF from the cache) | no |

CONTEXT is the label the backend shows in its announce (IMP-021), e.g.
`"satan broker/tick-pulse"` or `"satan broker/tick-pulse (escalated: deferred 4h)"`.

**SATAN side (public API).** Every function takes ENV, the environment list the
child will actually receive (RV-013 N5), and never calls `getenv`. For each VAR,
its value in ENV is looked up. An unset VAR is skipped, as it is today. A value not matching the regexp is a literal. A ref is looked up;
refs still missing are *pending*.

- `(satan-credential-ready-p env vars)`: non-nil when nothing is pending, or when
  `session-p` holds. It never reads, so it never prompts.
- `(satan-credential-acquire env vars policy context)` →
  `(:env ("K=v" …) :refs ((VAR . REF) …))`, `(:deferred)`, or `(:unavailable ERR)`, where ERR is a
  condition object (RV-013 F-4). Nothing pending → `:env`. Pending and
  `session-p` → `read` each. Pending with no session: POLICY `prompt` → `read`
  each; POLICY `defer` → `:deferred`. **Strict**: every pending ref must resolve.
- `(satan-credential-resolve env vars context)` → `(:env … :failed ((VAR . ERR) …))`.
  **Lenient**: reads each pending ref and collects failures per var instead of
  failing the whole call. Used only after `ready-p` (sec-7).
- `(satan-credential-scrub env)`: ENV without `K=ref` entries. Replaces
  `my/scrub-op-refs-env`.
- `(satan-credential-forget ref)`: `forget` on REF. Returns nil on success, or
  the condition object on failure. Like every function here, it never signals.

**Error boundary** (RV-013 F-2). Every backend call goes through one internal
wrapper. In `acquire`, any signal from any operation becomes `(:unavailable ERR)`.
In `ready-p`, a signal reads as not ready. In `resolve`, a signal becomes a
per-var failure. No backend signal escapes the module.

**No backend** (`satan-credential-function` nil). `lookup` and `session-p`
read as nil, and `read` signals `satan-credential-no-backend`. A ref therefore
takes the no-session path: a defer mode defers, and a prompt mode records
`:unavailable`. Literal values still pass. The ref never reaches a child,
because every spawn goes through `scrub` (fail closed, REQ-010).

**dl-secret adapter** (outside this repo): `my/satan-credential (op &rest args)`,
a `pcase` over the four operations. `lookup` is `gethash … my/op--cache`.
`session-p` is a new `my/op-session-p` (`op whoami`, exit 0). `read` is `my/op-read`
with `my/op-read-context` bound to CONTEXT. `forget` is `remhash`. The keeper's
config sets `satan-credential-function` to it. `my/op-read` itself is unchanged.

After this slice no `my/*` symbol remains in `satan-broker.el` or
`satan-patch-adapter-pi.el`.

<!-- doctrine:section sec-3 -->
## 3. Acquisition and ordering in `satan-broker-run` (DEC-020, DEC-023)

Today `satan-broker-run` allocates (`satan-run-new-ctx`), perceives, runs the gate
`cond`, and only then, inside `--spawn`, reads the key. New order:

1. `mode` ← `satan-mode-resolve`.
2. `cred` ← `(satan-broker--acquire mode)`, **skipped (nil) while
   `satan-run--spawn-running`**, so a run that will be refused as busy never
   prompts. Otherwise it builds the **effective base env**,
   `(satan-broker--direnv-env process-environment)`, which is the same env
   `--spawn` uses, now computed once and passed down (RV-013 N5). It collects the
   mode's key var (`satan-broker-provider-key-vars` over `:provider`; none →
   `(:env nil)`), the effective policy (sec-4) and the context label, and calls
   `satan-credential-acquire`. A prompting read blocks here, before any run
   exists. **The whole step is one error boundary**: policy evaluation
   (streak walk, duration check) and direnv sit inside a `condition-case`, and
   any signal becomes `(:unavailable ERR)`. The run is then allocated and
   recorded as `credential_unavailable`, never lost (RV-013 N6).
3. `prepare` ← `satan-run-new-ctx`; perceive, unchanged.
4. `cond` branches, **in this precedence** (RV-013 N7): real failures announce
   first; the silent deferrals follow.
   - `perceive_failed`, `session_blocked`: unchanged.
   - **`run_busy`** (DEC-023, RV-013 F-3): `(or (null cred)
     satan-run--spawn-running)` → a no-child run, no rename, no pop,
     streak-transparent. A nil `cred` means acquisition was skipped as busy. It
     stays `run_busy` even if the child has since exited, so a run is never
     spawned without having acquired its key. The flag is re-checked because
     a queued trigger can arrive while a prompt blocks.
   - `budget_denied`: unchanged.
   - `(:deferred)` → `credential_deferred`; `(:unavailable ERR)` →
     `credential_unavailable` (sec-5).
   - otherwise → `(satan-broker--spawn mode prepare dir cred)`.

   `perceive_failed` beats `run_busy` deliberately. A perception failure is a
   real fault and is announced even when the run was busy anyway.
5. `--spawn` takes the verdict: its `:env` is appended to `provider-env`, and
   its base env replaces the second `satan-broker--direnv-env` call. The
   `key-val` binding, its `condition-case`, `satan-broker--read-env` and the
   `my/*` declarations are deleted. `my/scrub-op-refs-env` → `satan-credential-scrub`.

**Why `run_busy`.** `satan-broker-run` never refuses while a child is live.
`satan-memory-store--current-run-id` and `most-recent` are process-global and
race under overlap. Overlap is possible today (a tick has a 1800 s timeout), and
a blocking prompt makes it likely: every trigger that queued behind the dialog
fires the moment it is answered.

**Consequences.**
- A prompt accepted at 11:40 yields an 11:40 run id, `time_now` and percept.
  No expiry exists.
- **R1:** the prompt now fires before perceive, never inside it. Defer-mode
  runs only call `session-p` (`op whoami`, no dialog) at that point.
- A prompt can be wasted when the run is then `session_blocked` or
  `budget_denied`. This is rare and accepted in DEC-020.
- A daily mode whose trigger queued behind another run's prompt is refused as
  `run_busy` and waits for its next day (DEC-023; accepted, skip-only per DEC-020).
- Acquisition is not inside `satan-trace-with-tick`, because the run id does
  not exist yet. The verdict is stamped as the trace outcome in the `cond`.

<!-- doctrine:section sec-4 -->
## 4. Per-mode policy and escalation (DEC-022)

**Mode spec keys** (`satan/satan-mode.el`), beside `:provider`/`:profile`:

- `:credential-policy` — `prompt` or `defer`. **Absent means `defer`**:
  unattended code never starts a session unasked (IMP-021, objective 7).
- `:credential-escalate-after` — seconds; absent → defcustom
  `satan-credential-escalate-after` (default 14400, 4 h).

These are two flat plist keys rather than DEC-022's nested
`(defer :escalate-after D)`: the flat form is idiomatic elisp and profile-mergeable
(`satan-mode--apply-profile`), and DEC-022 carries a note to that effect (RV-013
F-8). `satan-mode-register` validates both: the policy must be `prompt` or `defer`,
and the duration a non-negative number. Anything else signals at registration,
never at run time. The effective duration, which may come from the defcustom,
is re-checked by the policy function; a bad value signals inside sec-3's
acquisition boundary and is recorded as `credential_unavailable` (RV-013 N6).

**Status, not only reason** (RV-013 N8). `final.json`'s reason is a free string
a model's own final may carry, so both predicates require `status failed`. The
same guard is added to the existing skip predicate in
`satan-broker--failure-streak`, which today matches transparent reasons alone.

`morning` and `motd` set `:credential-policy prompt`. `tick-*` (via
`satan-tick-register` defaults) and every other mode inherit `defer`.

**Effective policy**, `(satan-broker--credential-policy mode)`, a pure function
over the mode, the attended flag (sec-8), the current time and the streak:

```
attended                              → prompt
:credential-policy prompt             → prompt
defer and escalation due              → prompt   (context says "escalated")
defer                                 → defer
```

**Escalation due** when the mode's current credential streak is older than
`:credential-escalate-after`:

```elisp
(satan-run-outcome-streak
  slug
  (lambda (o) (and (eq (plist-get o :status) 'failed)                ; counts
                   (equal (plist-get o :reason) "credential_deferred")))
  (lambda (o) (and (eq (plist-get o :status) 'failed)                ; skips
                   (member (plist-get o :reason)
                           '("session_blocked" "run_busy")))))
```

Age = now − `(satan-run-id-time (plist-get oldest :run-id))`, where `oldest` is
the last element of the streak. `satan-run-id-time` is a new helper in
`satan-run.el` that parses the `%Y%m%dT%H%M%S` prefix `satan-run-mint-id`
writes. Any other outcome ends the streak: a success, a dismissed escalation
(`credential_unavailable`), or a spawned failure. The next escalation is
therefore a full threshold later. `run_busy` is skipped too. No state is added
(ADR-018 D5, DEC-014).

Run ids carry local time with no zone, so across a DST change the measured age
can be off by up to an hour against a 4 h threshold. That is accepted (RV-013
F-9). Ordering within the repeated hour is DEC-014's walk, which predates this
slice.

**No quiet-hours logic.** Tick does not run in quiet hours, motd/morning prompt
anyway, and patch never escalates (sec-7). A streak that starts just before quiet
hours escalates at the first tick after them.

<!-- doctrine:section sec-5 -->
## 5. Outcomes and announcement

| verdict | status | `final.json` reason | `.FAILED` rename | pop | journal | failure-streak |
|---|---|---|---|---|---|---|
| busy | `failed` | `run_busy` | no | no | no | transparent (added to `satan-broker--streak-transparent-reasons`) |
| deferred | `failed` | `credential_deferred` | no | no | yes | transparent (already in `satan-broker--streak-transparent-reasons`) |
| prompt read failed / dismissed | `failed` | `credential_unavailable` | yes | DEC-015 back-off | yes | its own same-cause streak |
| provider 401 after spawn | `failed` | `auth` (DEC-019) | yes | always, critical | yes | its own; triggers sec-6 |

Both new verdicts are written by the existing `satan-broker--write-no-child-run`
with a synthetic final (`:summary`, `:actions []`, `:reason`), as
`session_blocked` is:

- `credential_deferred`: `:rename-announce nil`, plus one journal-only
  `satan-announce` line (`:title nil`, `:journal "credential_deferred <mode> <run-id>"`),
  so a locked vault is visible in `journalctl --user -t satan` without popping
  every 30 min.
- `credential_unavailable`: through `satan-broker--write-failed-no-child-run`
  (rename + announce), passed the verdict's condition object ERR, which that
  helper renders with `error-message-string` (RV-013 F-4).
- `run_busy`: `:rename-announce nil`, no journal line: overlap is routine and
  visible in the run bundles.

`credential_unavailable` is deliberately **not** the `auth` class. The keeper
dismissing a dialog is intent, not a dead key, so it must not trigger critical
pops or eviction. `op` cannot reliably distinguish a dismissal from other read
errors, so every failed prompting read is treated this way.

Initialisation failures of the form `KEY not set` (DEC-019's `failed/unknown`)
disappear for ref-backed keys. They remain only for a var that is unset
altogether, which is a configuration error.

<!-- doctrine:section sec-6 -->
## 6. Rotation self-heal

In `satan-broker--finalize`, once status and `failure-reason` are final and
before the announce, a new step `(satan-broker--evict-on-auth run-ctx)` runs.

**Trigger** (RV-013 N4): status `failed` **and** the broker-classified
`failure-reason` slot (DEC-019, set by `satan-broker--on-error` from the
harness error payload) is exactly `"auth"`. `final.json`'s reason is not
consulted: a model's final can carry any string. The step then evicts the ref
the run actually used. The acquisition verdict carries `:refs ((VAR . REF) …)`,
and `--spawn` stores it in a new `satan-run` slot, `credential-refs`, so a later
env change cannot redirect the eviction. The next run
finds no cached value, re-reads the ref (silently if a session is live,
otherwise per policy), and picks up the rotated key. `my/op-forget` stops
being a manual step.

Guards (DEC-019 consequences):
- Only a classified `auth`. `credits`, `rate_limit`, `server`, `unknown` and a
  moderation 403 (`unknown`) never evict.
- It evicts a single ref, never the whole cache: other consumers' secrets in
  `my/op--cache` survive.
- **Non-critical** (RV-013 F-5, N3). `satan-credential-forget` never signals
  (sec-2) and returns ERR on failure. The broker then records a `broker`
  `evict-failed` audit event with the ordinary audit write. No further guard is
  added: if the audit itself cannot write, finalize fails regardless, and the
  sentinel reset below still runs.
- Evicting twice is harmless (`remhash` of an absent key), so no once-only
  flag is needed.

**Sentinel reset (ISS-020, absorbed).** `satan-broker--make-sentinel` records
`child-exit` and runs `--finalize`, and only then clears
`satan-run--spawn-running`, with no `unwind-protect`. A signal from either step
leaves the flag set. The MCP server then refuses sessions, and with DEC-023's
`run_busy` every scheduled run is refused until Emacs restarts. The whole body
after the timer cancel is wrapped in `unwind-protect` (the `child-exit` record
**and** finalize), with the reset as its unwind form (RV-013 N1). The error
still propagates, as it does today: this is a reset, not suppression.

The patch adapter's results carry no error class. Patch runs therefore never
evict (residual; IMP-005 remainder). A rotated key used only by patch is healed
by the next broker `auth` failure on the same ref, or by `my/op-forget`.

<!-- doctrine:section sec-7 -->
## 7. Patch runner

The pi adapter resolves all seven `satan-patch-adapter-pi-api-key-vars` in
`--resolved-env`, *after* `satan-patch-runner-tick` has claimed the job
(`queued → claimed`). A deferral there would strand a claimed job. Requiring all
seven strictly would let one stale, unrelated key block every job (RV-013 F-6).
The gate therefore splits in two: **check readiness before the claim, resolve
leniently after it.**

In `satan-patch-runner-tick`, when enabled and idle:

1. **Peek**: `(satan-patch-store-list :state "queued" :limit 1)`, using the
   existing function with no new SQL (RV-013 F-7):
   - `(ok . nil)` → return nil, with no `op` call: an idle runner never probes.
   - `(error . MSG)` → `message`, return nil, as `claim-next` errors are
     handled today.
   - `(ok . ROWS)` → continue. The peeked row is never used as the job.
2. **Readiness**: `(satan-credential-ready-p process-environment
   satan-patch-adapter-pi-api-key-vars)`.
   Nil → `message` plus a journal-only line `credential_deferred patch`, then
   return nil. The job stays `queued` and the next idle-timer poke retries it
   (DEC-020). Nothing is read, so nothing prompts.
3. **Claim**: `claim-next` as today. `(ok . nil)` (another runner won) → return
   nil. The readiness probe was the only cost.
4. **Resolve**: `(satan-credential-resolve process-environment vars
   "satan patch-adapter/pi")`,
   passed to the adapter in the input plist as `:env`. Per-var failures become
   entries in the adapter result's `:warnings`. The runner's failure path
   (`satan-patch-runner--finish-with-row`, `adapter_failed`) persists
   `:warnings` alongside `:error`, so a key failure is recorded on the failure
   it explains (RV-013 N9). The job proceeds, and pi fails
   loudly on its own if the provider it needed is the one that failed.
   `satan-patch-adapter-pi-invoke` binds `process-environment` to
   `(satan-credential-scrub (append ENV process-environment))`. `--resolved-env`
   and the `my/*` declarations are deleted.

Patch **never escalates** (DEC-022). The 1Password session is shared, so any
accepted prompt (motd, morning, or an escalated tick) warms it for the runner.
The residual is that jobs starve if every broker mode stops running. They stay
visible as `queued`. The A2 race (the session expires between readiness and
resolve) costs one visible prompt, as for broker runs.

**The var list is a superset, and SATAN cannot narrow it** (RV-013 F-6, N2).
The runner calls `satan-patch-prompt-build` with no `:provider`, so pi picks its
provider from its own configuration and SATAN never learns which key a job
needs. Readiness over all seven vars therefore holds a job back while *any*
listed ref is cold and no session exists, even when the key pi will use is
cached. The cost is bounded: the job runs at the first live session, which any
accepted prompt provides. Narrowing `satan-patch-adapter-pi-api-key-vars` to
the provider pi is configured for is the keeper's config lever. Choosing the
provider per job is future work (the design debt below).

Design debt noted, not addressed: the runner names the pi adapter's var list,
and only pi rows exist. With a second adapter, or per-job providers, the
required keys should become an adapter protocol operation.

<!-- doctrine:section sec-8 -->
## 8. Attended override

```elisp
(defvar satan-run-attended nil
  "Non-nil while a run was started by a human at the keyboard.")
```

Defined in `satan-broker.el` beside the policy function. `satan-run`
(`satan/satan.el`) binds it only when `(called-interactively-p 'interactive)`:

```elisp
(let ((satan-run-attended (called-interactively-p 'interactive)))
  (satan-broker-run name))
```

Every other entry, including the systemd `emacsclient --eval "(satan-run …)"`
shims, `satan-tick` (`satan-tick.el:141`), the patch idle timer and MCP, leaves it
nil, so they are unattended by default (fail closed). An attended run's effective
policy is `prompt` whatever the mode says (sec-4).

<!-- doctrine:section sec-9 -->
## 9. Verification, risks and rollout

**Test seam.** Every behaviour is testable against a fake
`satan-credential-function`: a plist-driven closure recording calls and
returning scripted `lookup`/`session-p`/`read`/`forget` results. Acquisition
functions take ENV as an argument, so tests pass a literal env list. Tests that need
real runs use the existing temp runs-dir fixtures. No test calls `op`.

| VT | behaviour |
|---|---|
| VT-1 | acquire: literal / unset / cached / session-live-read / no-session-defer / no-session-prompt / prompt-read-signals → `:unavailable` |
| VT-2 | defer mode, no session → `credential_deferred` no-child run; backend saw only `lookup`/`session-p`, never `read` |
| VT-3 | prompt mode, no session → `read` called with the mode's context label |
| VT-4 | escalation: streak older than threshold → `read`; younger → deferred; `session_blocked` skipped; a success resets |
| VT-5 | live session, cold cache → spawns without prompting (`read` after `session-p` t) |
| VT-6 | classified `auth` failure → `forget` on the ref the run used; `credits`/`unknown` → no `forget`; a `done` run, or a final whose reason is `"auth"` without a classified slot → no `forget` (N4) |
| VT-7 | patch: nothing queued → zero backend calls; deferred → job stays `queued`; ok → adapter env carries resolved key, refs scrubbed |
| VT-8 | attended `satan-run` → prompt even for a `defer` mode |
| VT-9 | acquisition precedes allocation: a blocking `read` stub advances the clock and the run id carries the later time |
| VT-10 | `rg 'my/op-\|my/scrub-op' satan/` finds nothing; `rg '(error nil)\|ignore-errors'` finds none around key resolution |
| VT-11 | no backend: a ref-valued var → defer mode `:deferred`, prompt mode `:unavailable`; a literal passes; `scrub` removes the ref from a child env (F-1) |
| VT-12 | a signal from each backend op (`lookup`, `session-p`, `read`) → `acquire` returns `:unavailable`, `ready-p` returns nil, `resolve` records a per-var failure; none escapes (F-2) |
| VT-13 | broker end-to-end `credential_unavailable`: `.FAILED` dir, `final.json` reason, journal line, same-cause streak position (F-4) |
| VT-14 | `run_busy`: with `spawn-running` set, no acquisition call and a `run_busy` no-child run; still `run_busy` when the flag clears before the `cond` (nil `cred`); skipped by both the failure and credential streaks (F-3) |
| VT-15 | `forget` signals during an `auth` finalize → `evict-failed` audit event; rename, announce and the `spawn-running` reset still happen (F-5) |
| VT-19 | a signal from the sentinel's `child-exit` record **or** from finalize still clears `satan-run--spawn-running` (ISS-020, N1) |
| VT-20 | a key ref present only in the direnv-merged env is acquired, and the child receives exactly that base env (N5) |
| VT-21 | an invalid defcustom duration, or a signalling streak walk → recorded `credential_unavailable` run, not a lost trigger (N6) |
| VT-22 | busy at entry plus a perceive error → `perceive_failed`; busy plus session active → `session_blocked` (N7 precedence) |
| VT-23 | a `done` run whose final reason is `credential_deferred`/`run_busy`/`session_blocked` ends both streaks rather than extending or being skipped (N8) |
| VT-24 | patch `adapter_failed` job row carries the per-var resolution warnings (N9) |
| VT-16 | patch: peek error → no backend call; readiness passes but claim returns nil → no resolve; one failing var of seven → job runs with a warning (F-6, F-7) |
| VT-17 | unattended entry: `satan-run` called non-interactively, and `satan-tick`, leave `satan-run-attended` nil, so a `defer` mode defers (F-10) |
| VT-18 | registration refuses a policy other than `prompt`/`defer` and a negative or non-numeric duration (F-8) |

**VA/VH.**
- VH-1: **watch, not validate** (corrected at /plan, 2026-09-23). ASM-002's open
  case is a session that reports live yet later demands re-auth; positive reads
  cannot rule it out. Any dialog raised by a defer-mode run whose context lacks
  "escalated", while `op whoami` reported live, invalidates ASM-002 (see its
  validation plan). Closure does not wait on it.
- VH-2: with 1Password locked, a tick writes `credential_deferred` and no dialog
  appears. After the threshold, the next tick raises one labelled dialog.
- VH-3: the 08:15 motd raises a labelled dialog; accepting later runs motd with
  a fresh run id.

**Risks.**
- R2: when the cache is cold, each run adds one `op whoami` (~0 s). A warm
  cache makes no `op` call at all.
- A2 race (the session expires between the probe and the read): costs one
  visible prompt, including in defer modes. Accepted.
- `run_busy` refuses a daily mode whose trigger queued behind another run's
  prompt. That day's run is lost (DEC-023). Revisit if it bites.
- DST can skew the escalation age by up to an hour (sec-4).

**Rollout (two repos, order matters).**
1. `dl-secret.el` first: add `my/op-session-p` and `my/satan-credential`, and
   set `satan-credential-function` in config (inert until SATAN reads it).
2. SATAN: the credential module, gate, policy, patch runner and eviction in
   phases, `just check` green at each.
3. Restart Emacs (the live Emacs loads the working tree), then VH-2, VH-3, and arm the VH-1 watch.

