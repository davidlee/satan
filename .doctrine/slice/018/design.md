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
  ├─ acquire (sec-3)            satan-credential-acquire VARS POLICY CONTEXT
  │     cached?  ── yes ─────────────────────────────┐
  │     session-p (op whoami)? ── yes → read (silent) ┤
  │     policy (sec-4):                               │
  │        prompt → read (dialog, may block) ─────────┤→ (:env …)
  │               └ read fails ──────────────────────→ (:unavailable MSG)
  │        defer  ───────────────────────────────────→ (:deferred)
  │
  ├─ satan-run-new-ctx          run_id / time_now allocated AFTER acquisition
  ├─ perceive                   unconditional (ISSUE-001)
  └─ cond: perceive_failed │ session_blocked │ budget_denied
           │ credential_deferred   (no rename, no pop; journal line)
           │ credential_unavailable (.FAILED, DEC-015 back-off)
           │ spawn with (:env …)
```

Two repos change: `~/dev/satan` (policy, gate, seam) and
`~/.emacs.d/lisp/dl-secret.el` (the 1Password backend).

<!-- doctrine:section sec-2 -->
## 2. Credential seam (DEC-021)

New module `satan/satan-credential.el` owns the seam and the acquisition
algorithm. It knows nothing about 1Password.

**Backend protocol.** One function variable:

```elisp
(defcustom satan-credential-function nil
  "Backend called as (OP &rest ARGS); nil means no backend.")
```

| OP | args | returns | may prompt? |
|---|---|---|---|
| `ref-p` | VALUE | non-nil when VALUE is a backend reference | no |
| `lookup` | REF | cached plaintext or nil; no subprocess | no |
| `session-p` | — | non-nil when a session is live | no |
| `read` | REF CONTEXT | plaintext; signals on failure | **yes** |
| `forget` | REF | — (evicts REF from the cache) | no |

CONTEXT is the label the backend shows in its announce (IMP-021), e.g.
`"satan broker/tick-pulse"` or `"satan broker/tick-pulse (escalated: deferred 4h)"`.

**SATAN side (public API):**

- `satan-credential-acquire (vars policy context)` → `(:env ("K=v" …))`,
  `(:deferred)` or `(:unavailable MESSAGE)`. Pure over the backend: for each VAR,
  `getenv`; unset → skipped (unchanged behaviour); not `ref-p` → literal; else
  `lookup`. Refs still missing are *pending*. No pending → `:env`. Pending and
  `session-p` → `read` each. Pending, no session: POLICY `prompt` → `read` each,
  and a signal becomes `:unavailable`; POLICY `defer` → `:deferred`.
- `satan-credential-scrub (env)` → ENV without `K=ref` entries (replaces
  `my/scrub-op-refs-env`).
- `satan-credential-forget (var)` → `forget` on VAR's current ref, if it is one.

**No backend** (`satan-credential-function` nil): nothing is a ref, so values
pass through literally, which is correct for a host that keeps plain keys in its
environment. A host that has `op://` refs but no backend loaded ships the literal
ref and gets a provider 401 → `auth` failure (loud, critical pop). That is the
fail-closed residual (REQ-010): no silent success, no dialog.

**dl-secret adapter** (outside this repo): `my/satan-credential (op &rest args)`,
a `pcase` over the five ops mapping to `string-prefix-p "op://"`,
`gethash … my/op--cache`, a new `my/op-session-p` (`op whoami`, exit 0),
`my/op-read` with `my/op-read-context` bound to CONTEXT, and `remhash`. The keeper's
config sets `satan-credential-function` to it. `my/op-read` itself is unchanged.

After this slice no `my/*` symbol remains in `satan-broker.el` or
`satan-patch-adapter-pi.el`.

<!-- doctrine:section sec-3 -->
## 3. Acquisition and ordering in `satan-broker-run` (DEC-020)

Today `satan-broker-run` allocates (`satan-run-new-ctx`), perceives, runs the gate
`cond`, and only then, inside `--spawn`, reads the key. New order:

1. `mode` ← `satan-mode-resolve`.
2. `cred` ← `(satan-broker--acquire mode)`: the mode's key var
   (`satan-broker-provider-key-vars` over `:provider`; none → `(:env nil)`), the
   effective policy (sec-4) and the context label, passed to
   `satan-credential-acquire`. A prompting read blocks here, before any run exists.
3. `prepare` ← `satan-run-new-ctx`; perceive, unchanged.
4. `cond`, extended after the existing branches:
   - `perceive_failed`, `session_blocked`, `budget_denied`: unchanged and
     first, so DEC-8 and budget precedence are preserved.
   - `(:deferred)` → `credential_deferred` (sec-5).
   - `(:unavailable MSG)` → `credential_unavailable` (sec-5).
   - otherwise → `(satan-broker--spawn mode prepare dir (plist-get cred :env))`.
5. `--spawn` takes the env list and appends it to `provider-env`. The
   `key-val` binding, its `condition-case`, `satan-broker--read-env` and the
   `my/*` declarations are deleted. `my/scrub-op-refs-env` → `satan-credential-scrub`.

**Consequences.**
- A prompt accepted at 11:40 yields an 11:40 run id, `time_now` and percept.
  No expiry exists.
- **R1:** the prompt now fires before perceive, never inside it. Defer-mode
  runs only call `session-p` (`op whoami`, no dialog) at that point.
- A prompt can be wasted when the run is then `session_blocked` or
  `budget_denied`. This is rare and accepted in DEC-020.
- Acquisition is not inside `satan-trace-with-tick`, because the run id does
  not exist yet. The verdict is stamped as the trace outcome in the `cond`, as
  the other gates are.

<!-- doctrine:section sec-4 -->
## 4. Per-mode policy and escalation (DEC-022)

**Mode spec keys** (`satan/satan-mode.el`), beside `:provider`/`:profile`:

- `:credential-policy` — `prompt` or `defer`. **Absent means `defer`**:
  unattended code never starts a session unasked (IMP-021, objective 7).
- `:credential-escalate-after` — seconds; absent → defcustom
  `satan-credential-escalate-after` (default 14400, 4 h).

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
  (lambda (o) (equal (plist-get o :reason) "credential_deferred"))   ; counts
  (lambda (o) (equal (plist-get o :reason) "session_blocked")))      ; skips
```

Age = now − `(satan-run-id-time (plist-get oldest :run-id))`, where `oldest` is
the last element of the streak. `satan-run-id-time` is a new helper in
`satan-run.el` that parses the `%Y%m%dT%H%M%S` prefix `satan-run-mint-id`
writes. Any other outcome ends the streak: a success, a dismissed escalation
(`credential_unavailable`), or a spawned failure. The next escalation is
therefore a full threshold later. No state is added (ADR-018 D5, DEC-014).

**No quiet-hours logic.** Tick does not run in quiet hours, motd/morning prompt
anyway, and patch never escalates (sec-7). A streak that starts just before quiet
hours escalates at the first tick after them.

<!-- doctrine:section sec-5 -->
## 5. Outcomes and announcement

| verdict | status | `final.json` reason | `.FAILED` rename | pop | journal | failure-streak |
|---|---|---|---|---|---|---|
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
  (rename + announce), carrying the backend's error message.

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
before the announce, a new step `(satan-broker--evict-on-auth run-ctx)` does
the following. When the run's recorded reason (`satan-broker--failure-reason`)
is exactly `"auth"`, it calls `satan-credential-forget` on the mode's key var.
The next run then finds no cached value, re-reads the ref (silently if a
session is live, otherwise per policy), and picks up the rotated key.
`my/op-forget` stops being a manual step.

Guards (DEC-019 consequences):
- Only `auth`. `credits`, `rate_limit`, `server`, `unknown` and a moderation 403
  (`unknown`) never evict.
- It evicts a single ref, never the whole cache: other consumers' secrets in
  `my/op--cache` survive.
- It runs in finalize, which is idempotent, so a double finalize evicts twice,
  which is harmless.

The patch adapter's results carry no error class. Patch runs therefore never
evict (residual; IMP-005 remainder). A rotated key used only by patch is healed
by the next broker `auth` failure on the same ref, or by `my/op-forget`.

<!-- doctrine:section sec-7 -->
## 7. Patch runner

The pi adapter resolves `satan-patch-adapter-pi-api-key-vars` in
`--resolved-env`, *after* `satan-patch-runner-tick` has claimed the job
(`queued → claimed`). A deferral there would strand a claimed job.

New shape, in `satan-patch-runner-tick`, when enabled and idle:

1. Peek: `(satan-patch-store-list :state "queued" :limit 1)`, using the existing
   function with no new SQL. Nothing queued → return nil with no `op` call, so
   an idle runner never probes.
2. `(satan-credential-acquire satan-patch-adapter-pi-api-key-vars 'defer
   "satan patch-adapter/pi")`.
3. `(:deferred)` or `(:unavailable …)` → no claim; `message` plus a journal-only
   announce line; return nil. The job stays `queued` and the next idle-timer
   poke retries it (DEC-020).
4. `(:env …)` → `claim-next` as today, passing the env to the adapter in the
   input plist as `:env`. `satan-patch-adapter-pi-invoke` binds
   `process-environment` to `(satan-credential-scrub (append ENV
   process-environment))`. `--resolved-env` and the `my/*` declarations are
   deleted.

Patch **never escalates** (DEC-022). The 1Password session is shared, so any
accepted prompt (motd, morning, or an escalated tick) warms it for the runner.
The residual is that jobs starve if every broker mode stops running. They stay
visible as `queued`.

Design debt noted, not addressed: the runner names the pi adapter's var list.
With a second adapter, the var list should become an adapter protocol operation.

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
returning scripted `ref-p`/`lookup`/`session-p`/`read` results. Tests that need
real runs use the existing temp runs-dir fixtures. No test calls `op`.

| VT | behaviour |
|---|---|
| VT-1 | acquire: literal / unset / cached / session-live-read / no-session-defer / no-session-prompt / prompt-read-signals → `:unavailable` |
| VT-2 | defer mode, no session → `credential_deferred` no-child run; backend saw only `ref-p`/`lookup`/`session-p`, never `read` |
| VT-3 | prompt mode, no session → `read` called with the mode's context label |
| VT-4 | escalation: streak older than threshold → `read`; younger → deferred; `session_blocked` skipped; a success resets |
| VT-5 | live session, cold cache → spawns without prompting (`read` after `session-p` t) |
| VT-6 | `auth` failure → `forget` on the mode's ref; `credits`/`unknown` → no `forget` |
| VT-7 | patch: nothing queued → zero backend calls; deferred → job stays `queued`; ok → adapter env carries resolved key, refs scrubbed |
| VT-8 | attended `satan-run` → prompt even for a `defer` mode |
| VT-9 | acquisition precedes allocation: a blocking `read` stub advances the clock and the run id carries the later time |
| VT-10 | `rg 'my/op-\|my/scrub-op' satan/` finds nothing; `rg '(error nil)\|ignore-errors'` finds none around key resolution |

**VA/VH.**
- VH-1: validate ASM-002 on the live host (live session, cold ref → no dialog).
- VH-2: with 1Password locked, a tick writes `credential_deferred` and no dialog
  appears. After the threshold, the next tick raises one labelled dialog.
- VH-3: the 08:15 motd raises a labelled dialog; accepting later runs motd with
  a fresh run id.

**Risks.**
- R2: when the cache is cold, each run adds one `op whoami` (~0 s). A warm
  cache makes no `op` call at all.
- A2 race (the session expires between the probe and the read): costs one
  visible prompt, including in defer modes. Accepted.
- The no-backend residual in sec-2 (a literal ref leads to an `auth` failure):
  loud, never silent.

**Rollout (two repos, order matters).**
1. `dl-secret.el` first: add `my/op-session-p` and `my/satan-credential`, and
   set `satan-credential-function` in config (inert until SATAN reads it).
2. SATAN: the credential module, gate, policy, patch runner and eviction in
   phases, `just check` green at each.
3. Restart Emacs (the live Emacs loads the working tree), then VH-1..VH-3.

