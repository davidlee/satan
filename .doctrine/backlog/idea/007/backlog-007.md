# IDE-007: Persistent owned microVM for SATAN proposals: plain git inside, host-initiated sync, LiteLLM-held keys

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Direction agreed 2026-10-16. It replaces the satan-patcher bridge: ISS-030,
ISS-038, ISS-039 and ISS-041 are not being fixed in place. Prior thinking:
`docs/brief.broker.local.md` (untracked); ~/flakes IDE-003 and IDE-004.

The host side is planned in oubliette's `docs/plan-f-assistant.md` ("Plan F",
commit `fb241c4`), which supersedes this record's first sketch: a reserved
capsule slot, and fetching straight into `refs/remotes/satan/*`.

## Shape

- **One persistent microVM, as an oubliette room, not a capsule slot.** A
  capsule is one agent, one repo, one unit of work; an assistant has many
  repos and no unit of work (Plan F, "The one-line answer"; oubliette Plan E is
  the room design). It holds clones of about seven of the user's repos, with
  `/home` on a volume that survives reboots.
- **No egress by default.** The room's network namespace has no uplink, no
  proxy and no route. The model path is a socket door, not egress (below).
- **Plain git inside the VM, with no shim.** The guest's clones are its own, so
  a destructive command (`reset --hard`, `clean`, `stash`) can only damage
  them. The brief's git shim assumed a bwrap jail sharing host repos;
  Firecracker has no shared folders (oubliette NOTES item 22), so the shim
  doesn't apply here.
- **The host starts every git transfer, and proposals land in quarantine.**
  The guest holds no git credentials and has no route to git remotes.

  ```
  host repo ── push (host-initiated) ──▶ guest clone              refresh code
  guest clone ── host fetch ──▶ quarantine/<repo> ── human promote ──▶ host repo
  ```

  Fetches go into a separate quarantine repository per repo, never into the
  real repo: guest-authored packs are attacker-shaped, and oubliette's size
  bound covers one packfile, not the whole transfer (oubliette NOTES item 34,
  RSK-006). Promoting into the real repo is the human's step.
- **Model credentials through a socket door.** The LLM gateway (~/flakes
  SL-011: LiteLLM on a host unix socket) is reached by a forwarder running
  inside the room's network namespace (`socat` TCP to that socket); nothing
  routes from guest to host. The socket's directory is 0750, so the forwarder
  needs `SupplementaryGroups=llm-gateway`. The guest holds only a gateway key
  from the gateway's own SQLite store (not a LiteLLM virtual key; flakes
  DEC-046, DEC-050), limited to named models, with its own budget, and
  revocable on the host.
- **Per-repo tools via a launcher.** Each repo's tool set is built on the host
  and baked into the image; nix-direnv can't work in a guest with no egress.
  `session <repo> -- <cmd>` puts that repo's tools on `PATH`, `cd`s into its
  clone and runs the command. One session is one repo.
- **The runner ssh's in, and lives in SATAN.** Scheduling, the queue, prompt
  composition and result classification are SATAN's. Oubliette provides the
  door: a non-root agent user reached through a relay.

## Carried over from satan-patcher

Worth porting: policy layering, prompt composition, result classification
(commits, diffstat, checks), and the `patch_jobs` contract. Fix ISS-041 in the
contract: `base_ref` must be a branch name, or something the consumer resolves
to one. The Emacs approval surface stays in Emacs (ADR-017); it now includes
promoting from quarantine.

## Open

1. Oubliette's prerequisites, in order (Plan F, "Sequencing"): its IMP-015
   (the repo list and tool sets move into the operator's consumer flake), then
   the shared room namespace, then the model door and the per-repo git channel
   in parallel.
2. Is the runner on this host (unix-socket relay) or on the tailnet? Plan F
   expects this host.
3. ADR-017's authority ledger changes owner for credential resolution (the
   LiteLLM service) and for the queue consumer.
4. Operational cost: a room that is always up blocks every oubliette probe,
   which refuses while any VM is running (Plan F, "Two operational costs").
5. Cleanup on adoption: disable the `satan-patcher` unit and
   `satan-patch-runner-enabled`; close ISS-030, ISS-038, ISS-039 and CHR-003 as
   superseded; retire `~/dev/satan-patcher`.
