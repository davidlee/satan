# RSK-021: Model-output jails may reach 1Password's abstract desktop-integration socket

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Risk

1Password's desktop app serves CLI integration on the abstract Unix socket
`@1PASSWORD_SDK_INTERGATIONS`. Abstract sockets live in the network
namespace, not the filesystem, so `$HOME` shadowing and bind-mount scans
(screwtape's proposed `op-unjailed` check) don't hide it from a jail that
shares the host network namespace.

The argument that it is safe today is 1Password's documented GID check: the
app resets connections whose peer GID is not `onepassword-cli`, which only the
setgid `op` wrapper confers, and `no_new_privs` in jails stops setgid
(screwtape ASM-003; https://www.1password.dev/cli/app-integration-security).
That argument is unvalidated.

## Probe (the owned check)

From inside each class of jail that holds model output:

1. record effective uid/gids and `NoNewPrivs` from `/proc/self/status`;
2. attempt to connect to `@1PASSWORD_SDK_INTERGATIONS` and exchange a
   request, with no secret involved;
3. run a safe control that distinguishes an authorisation reset from an
   unrelated connection failure (for example, the same connect from an
   unjailed shell without the `onepassword-cli` group, which should be reset
   the same way, and from `op` itself, which should succeed);
4. pass if every jail class is refused the same way as the unprivileged
   control; fail otherwise and treat it as an NF-004 (SPEC-002 REQ-016)
   violation needing remediation (e.g. `--unshare-net` or a network policy).

## Origin

Raised as screwtape RV-001 F-13/F-21 (SL-001 design review, 2026-10-26). The
exposure predates screwtape: the vault already holds higher-value items, and
screwtape only calls `op` once at provisioning. Related: ISS-028 (wider jail
bypasses).
