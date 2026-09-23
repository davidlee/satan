# ISS-012: motd and morning runs fail at turn 0 on an expired API key; tick runs succeed

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Every scheduled `motd` and `morning` run since late August ends `.FAILED` at
turn 0:

    {"type": "error", "error": "{\"class\": \"auth\", \"detail\": \"Error code: 401 -
     ... 'API key expired.' ...\", \"tokens_total\": 0, \"turn\": 0}"}

e.g. `~/.local/state/satan/runs/2026-09-14/20260914T130956-motd-006d80.FAILED`.
In the same minute `20260914T131029-tick-agent-2f0a48` completed a real model
turn — so the tick modes resolve a different provider/key than motd/morning.

Two things to fix:
1. Renew the key, or point motd/morning at the working provider.
2. Nothing surfaced this for ~3 weeks (`status: invalid` is silent — cf.
   IMP-005). A run that fails on auth should be loud.

Seen in SL-015 PHASE-02 (F-4) and PHASE-03; unrelated to the corpus move.

---

## Superseded diagnosis (2026-09-23)

**Both numbered fixes above are wrong.** Corrected by a live triage:

1. *"Renew the key, or point motd/morning at the working provider."* The key
   was genuinely expired and has been rotated — that half was right. But
   motd/morning and the tick modes resolve the **same** provider and the
   **same** ref. The difference was never provider configuration: tick runs
   happened to fire while the user was present and 1Password was unlocked, and
   motd/morning fire at 07:47/08:15/09:15, into the gap left by the 1Password
   app's own session-expiry cycle (`authorized_session.rs:217`, observed
   07:00:57 — 46 minutes before that morning's failed motd).

2. The two error strings alternate by **cache state**, not configuration:
   - `init failed: KEY not set` — op resolution failed; `my/scrub-op-refs-env`
     dropped the unresolved ref. Misleading: the var is present.
   - `401 API key expired` — op resolution **succeeded** and the provider
     rejected a real key string.

   A literal `op://` ref can never reach the provider, so a 401 naming an
   expired key proves resolution worked that day.

## What actually needs deciding

Not "which provider" but **how an unattended run acquires a credential at all**:

- **service-account token** — resolves headlessly, but puts a long-lived token
  on disk, against the argv/disk discipline established in
  `flakes/pub/jailed-agents.nix`; and it fixes the failure without fixing the
  blocking (below).
- **defer-when-locked** — the run defers rather than fails when the vault is
  locked. Preserves the posture, and a deferred run at 09:30 beats a failed one
  at 07:47.

Weighing them requires [[mem.fact.satan.op-read-blocks-emacs-server]]: a
cache-cold `op read` wedges the **entire Emacs server**, not just the run. A
token removes the failure but leaves that hazard on every cold path.

Also true and not captured here: rotating the key does not reach a running
Emacs — see [[mem.fact.satan.op-cache-has-no-invalidation]].

Item 2 of the original ("a run that fails on auth should be loud") stands, and
is now better served by [[ISS-016]] — the alert path that would have shouted is
itself broken.

---

## Split (2026-09-23)

The "should be loud" half now lives in [[ISS-017]], owned by SL-017. This item
is **credential acquisition only**. A service-account token was considered and
rejected by the keeper (2026-09-23); governance and the off-disk / off-argv
posture both point the same way (see SL-017 preflight). The open decision is:
*when an unattended run lacks a cached credential, does it call `op` at all?*
— cache-only vs probe-then-read (`op whoami` does not prompt).
