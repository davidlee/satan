# IDE-007: Persistent owned microVM for SATAN proposals: plain git inside, host-initiated sync, LiteLLM-held keys

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Direction agreed 2026-10-16. It replaces the satan-patcher bridge: ISS-030,
ISS-038, ISS-039 and ISS-041 are not being fixed in place. Prior thinking:
`docs/brief.broker.local.md` (untracked); ~/flakes IDE-003 and IDE-004.

## Shape

- **One persistent, owned microVM.** Reserve an oubliette capsule for SATAN
  and use oubliette's network-egress confinement, but not its ingress/egress
  tooling. The VM holds checkouts of all the user's projects, and SATAN works
  inside it to raise proposals.
- **Plain git inside the VM, with no shim.** The guest's clones are its own, so
  a destructive command (`reset --hard`, `clean`, `stash`) can only damage
  them. The brief's git shim assumed a bwrap jail sharing host repos;
  Firecracker has no shared folders (oubliette NOTES item 22), so the shim
  doesn't apply here.
- **The host starts every git transfer.** The guest holds no git credentials
  and has no network route to git remotes.

  ```
  host repo ── push/fetch (host-initiated) ──▶ VM clones         refresh code
  VM clones ── host: git fetch satan/* ──▶ refs/remotes/satan/*  collect proposals
  ```

  A fetch into a remote-tracking namespace can't damage the host repo, so
  there's no ref policy to enforce. This is the oubliette git-channel
  pattern, extended to many repos.
- **Model credentials.** A host LiteLLM proxy holds the real keys. The guest
  holds only a virtual key, limited to certain models and with its own
  budget. See ~/flakes IDE-003.

## Carried over from satan-patcher

Worth porting: policy layering, prompt composition, result classification
(commits, diffstat, checks), and the `patch_jobs` contract. Fix ISS-041 in the
contract: `base_ref` must be a branch name, or something the consumer resolves
to one. The Emacs approval surface stays in Emacs (ADR-017).

## Open

1. Can an oubliette capsule hold many repos, or no target repo at all? Check
   against oubliette's `docs/contract-target.md`.
2. The capsule's egress allowlist must include the host LiteLLM endpoint.
3. ADR-017's authority ledger changes owner for credential resolution (the
   LiteLLM service) and for the queue consumer.
4. Cleanup on adoption: disable the `satan-patcher` unit and
   `satan-patch-runner-enabled`; close ISS-030, ISS-038, ISS-039 and CHR-003 as
   superseded; retire `~/dev/satan-patcher`.
