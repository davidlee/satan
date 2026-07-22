# SATAN jailed agent loopback

# SATAN jailed agent loopback reachability

## Summary

For the current `~/flakes/pub/jailed-agents.nix` specDev profile, jailed-agent
wrappers share host loopback networking. A DE-004 Phase 01 probe using the
generated `jailed-pi` bwrap runtime closure args reached a host Supabase
Postgres listener at `127.0.0.1:54322`.

## Context

- Source of truth: `/home/david/flakes/pub/jailed-agents.nix` has `specDev =
  [ (persist-home "agent") network ]`; the generated bwrap command observed in
  DE-004 had no `--unshare-net`.
- Generated agent binaries such as `jailed-pi` run the actual agent, not an
  arbitrary shell. For diagnostic probes, either add the needed tool to the jail
  packages or reuse the generated runtime closure bind-args/profile shape with a
  temporary diagnostic payload.
- DE-004 evidence: host `pg_isready -h 127.0.0.1 -p 54322 -U postgres` returned
  accepting connections; the bwrap-profile TCP probe returned
  `TCP_OK_127.0.0.1_54322`.
- Limit: this proves TCP reachability only. It does not prove `psql` auth from
  inside the final agent wrapper until `postgresql` is included in the jail
  package set.
