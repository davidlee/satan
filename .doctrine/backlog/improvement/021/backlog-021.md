# IMP-021: 1Password prompts are unattributable: label op reads by calling consumer

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

A 1Password desktop authorization prompt arrives with no indication of which
consumer triggered it, or why. Observed 2026-09-23: a diagnostic
`(satan-broker--read-env "OPENROUTER_API_KEY")` eval queued a prompt that
surfaced ~20 minutes later, by which time nothing on screen connected it to its
cause.

## Why there is nothing to go on

Five consumers read the *same* ref, so every prompt is byte-identical:

    op://API_KEYS/<PROVIDER>_API_KEY/credential
       ├─ Emacs broker          my/op-read-env → session cache → env → make-process
       ├─ Emacs patch adapter   my/op-read-env → same cache → jailed-pi FD forward
       ├─ satan-patcher (Rust)  opBin/apiKeyRefs → own resolve + retry loop
       ├─ jailed agents         op run --env-file (flakes/pub/jailed-agents.nix)
       └─ ~/nushell/keys.nu

`op` has no `--reason` / `--label` flag (verified against op 2.x `--help`):
there is no first-class prompt-annotation API to call.

## What the prompt actually shows (observed 2026-09-23)

    ┌─────────────────────────────────────────┐
    │      1Password Access Requested         │
    │         [>_] ──✓── [1P]                 │
    │  Allow .ghostty-wrapped to get CLI      │
    │              access                     │
    │  ▸  Our Family                          │
    │            [Cancel]  [Authorize]        │
    └─────────────────────────────────────────┘

Two properties settle the design:

1. It is a **per-binary CLI-access grant**, not a per-read prompt. It names an
   *account* (`Our Family`) and never names the ref being read.
2. The binary it attests is the **GUI ancestor** — `.ghostty-wrapped`, the
   terminal — not `op`, and not the consumer. An Emacs-originated read attests
   Emacs; the broker and the patch adapter are therefore indistinguishable.

## Levers, resolved

| lever | verdict |
|---|---|
| Per-consumer item/vault naming | **dead** — the prompt never shows the ref |
| Distinct wrapper binary per caller | **dead** — attestation resolves to the GUI ancestor, not the shim |
| Out-of-band announce (log / `notifications-notify`) | **chosen** — the only lever that can name the actual consumer |

`op` has no `--reason` / `--label` flag (verified against `op --help`), so there
is no first-class annotation API to reach for.

## Coupling to the unattended-credential question

The prompt feels unattributable largely because resolution is **lazy,
unpredictably timed, and spread across three code paths**. If credential
acquisition were one explicit step — warm the cache when the user unlocks,
rather than when a timer happens to fire — prompts would arrive in a context
that labels them for free.

That is the same defect as the unattended-run failure in ISS-012: see the
1Password app session-expiry cycle (`authorized_session.rs:217`, 2026-09-23
07:00:57) landing 46 minutes before the 07:47 motd run. Whatever resolves that
(service-account token vs defer-when-locked) should resolve this too. Do not
design them separately.

Related: [[ISS-012]] (expired key + unattended resolution failure).
