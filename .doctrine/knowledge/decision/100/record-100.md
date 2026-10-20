## Decision

The server serves **both** postures. The choice is an operator declaration in the policy artefact (DEC-097), `mode = "per-call" | "static"`, fixed for the life of the process. It is not a per-call argument: a caller must not be able to pick its own confinement.

### `mode = "per-call"` (default)

As settled by DEC-089 / DEC-098: the server runs on the host, resolves the root against the allowlist (DEC-095), and launches the flake-provided wrapped form once per call with the call's root as its cwd. Capability (`read` / `write`), posture per call, multiple roots, both capabilities in one server.

### `mode = "static"`

The server itself is the jailed process (`makeJailedAgent { agent = pi-mcp; profile = … }`). Its children inherit, and nesting intersects authority (`mem.fact.jail.nesting-is-additive`) — so the launch jail is the whole confinement story and there is no child wrapper. The policy then declares what the jail already decided:

- `root` — the one root bound at launch. A `cwd` that is not the declared root is refused (`cwd-not-supported`); absent `cwd` means the declared root.
- `filesystem` — the launch jail's mode. A profile declaring the other capability is refused (`capability-mismatch`) rather than silently downgraded.
- `session_dir` and `run_dir` — **must already be bound writable at launch**. The server cannot add binds, so it validates their writability at start-up and refuses to serve (`bind-unavailable`) rather than discovering it mid-run. Both must live outside the root, or a read-only root cannot host them.
- `agent` — the executable to run, resolved from `PATH` inside the jail (the jail already provides `pi`).

The policy artefact must itself be readable inside the jail.

## What the server can and cannot verify

In static mode the server cannot prove it is jailed; it trusts the launch configuration, the same class of trust it already extends to the policy file. The honest statement is: static mode is an operator declaration, and the check that it holds is a flake check on the launcher (the `jailProbes` pattern), not a runtime assertion by the server.

## Why both

Per-call wrapping is the part that is genuinely new relative to what `jailed-agents` already provides: one surface, many roots, mixed capabilities. Static mode is worth keeping because a simple session with fixed requirements should not pay for a wrapper per call, and because jailing the server also confines the server's own writes (run dir, audit log, session dir).

## Consequence

DEC-098's `wrapper_read` / `wrapper_write` keys are per-call-mode keys. In static mode the same policy file carries `agent` and one `filesystem`, and the wrapper keys must be absent or ignored — the server refuses a policy that sets both (`policy-invalid`), so the two postures cannot be half-configured.


## Build status (2026-10-20): static mode designed, not built

The operator's call, made after the cost was measured: the initial build ships
**per-call only**. DEC-100 stays as the design of record — `sec-3`'s static half
and the second branch here are unaffected — but the slice's build scope excludes
it.

Reasoning, for whoever revisits:

- The per-call overhead is negligible: bwrap launch is 3-4 ms, node ~16 ms, so
  the marginal cost of a fresh jail per call is one pi process against model
  latency.
- Static mode is a convenience optimisation that pays with security: F-1/F-2 left
  it unable to keep evidence out of a co-resident child's reach, and unable to
  give per-session isolation, in a single-uid jail.
- The convenience case is better served by cheap defaults than by a second
  posture: a policy `default_profile` naming a read-only profile, and the launch
  cwd as the default root. Both keep one authority story.

What this removes from the build: the static derivation (`flake.nix`), the
posture switch and its `policy-invalid` cross-check, the start-up validation of
launch-bound dirs, and the memory-buffered evidence path. What it keeps: every
contract in sec-2, sec-4, sec-5, sec-6 and the per-call half of sec-3.


## RV-046 F-1: the initial build refuses a static policy instead of guessing

The build note above says the initial build ships per-call only, but left open
what the server does when it *reads* `mode = "static"` — ignore it and run
another posture, or take a bare host agent path. "Deferred" must not mean
"unspecified at a security boundary".

Rule for the initial build: `mode` accepts exactly `per-call`. A policy declaring
`static`, or carrying any static-only field (`agent`, `root`, `filesystem`,
`session_home`, `run_dir`, `evidence_dir`), is refused **`posture-unsupported`**
at validation step 1, before any spawn. No downgrade to per-call, no agent-only
fallback, no silent ignore of the field it could not honour. The static half of
the design stays as the record of what a future build must implement.
