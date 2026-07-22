# SATAN git sensor bwrap-blind

# SATAN git sensor is bwrap-blind to jailed-agent commits

## Summary

The SATAN git-activity sensor systematically undercounts commits. The
evidence-window git feed only sees commits made on the **host**; commits made
by bwrap-jailed agents (e.g. `clanker`, i.e. Claude Code running in the agent
sandbox) **never reach the feed at all**. This makes the LLM-generated
observation traces conclude the user is "idle / reading" while an agent is in
fact shipping large volumes of code.

This is **not author-filtering.** `satan/bin/satan-git-post-commit` records
`%an` verbatim — no author filter. The cause is environmental.

## Root cause

The feed is produced by a global git `post-commit` hook wired via
`core.hooksPath` → `~/.config/git/hooks/post-commit` (manual, **not**
Nix-managed). A bwrap jail breaks all three legs it stands on:

- the `~/.config/git/hooks/` symlink is not bind-mounted → `core.hooksPath`
  resolves to nothing → hook never runs;
- `~/.local/state/behaviour/segments/` is not mounted writable in the jail →
  even if it ran, the row goes nowhere;
- the overlaid `$HOME` has no `~/.gitconfig` → `core.hooksPath` is unset.

Any one leg alone kills capture.

## Evidence (verified 2026-06-05)

- `~/dev/forgettable` last 50 commits: 30 `clanker`, 20 `David Lee`.
- The 06-04 segment file (`~/.local/state/behaviour/segments/git-2026-06-04.jsonl`)
  held 16 `forgettable` rows — **all `David Lee`, zero `clanker`**. The 30
  jailed `clanker` commits left no row.
- Secondary undercount even for host commits: feed is 24h-windowed
  (`dl-satan-memory-evidence-git-window-minutes` = 1440) and capped by
  `seg-limit` — older-than-24h and over-cap commits silently drop.

## Why it matters

Downstream, `dl-satan-observer` / tick-pulse is an LLM reading this window. A
deaf sensor → it hallucinates idleness. Don't trust "no commits since X" in
traces; it means the sensor didn't *see* them, not that they didn't happen.

## Correct fix (placement decided, not yet built)

Capture belongs in **panopticon** (`~/dev/panopticon`, the host-side
behaviour-capture system that owns `~/.local/state/behaviour/`), as a new
host-side producer modeled on `sway_watcher` — poll tracked repos with
`git log`, dedup by sha, append segments. Host-side polling is env-agnostic so
it catches jailed commits; the sandbox stays sealed (do NOT mount the segments
tree into the jail).

- panopticon is 100% Python; the producer is **Python**, not Rust — Python is
  the house language and the workload (git subprocess + small parse) is
  syscall-bound, so Rust buys nothing. Rust-in-`satan-attrd` was rejected:
  that daemon owns the attribute projection, not behaviour capture.
- POL-001 agrees: a git poller fails "does it use the editor as an editor?" →
  it should not keep its `.emacs.d` seat.

Related: [[mem.fact.satan.jailed-agent-loopback]] (sibling
jail-boundary footgun).
