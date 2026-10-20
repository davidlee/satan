Observed 2026-10-20 (SL-027 PHASE-06, jailed-malebolge).

To check what a *running* jail can see/do (flake text probes only prove the
launcher's argv):

```
P=<pid of the jailed process, e.g. the node under bwrap>
JP=$(tr '\0' '\n' < /proc/$P/environ | grep '^PATH=' | cut -d= -f2-)
nsenter -t $P -U -m -n --preserve-credentials \
  /nix/store/<coreutils>/bin/env -i PATH="$JP" HOME=/home/david bash -s < probe.sh
```

- Unprivileged works: bwrap's user namespace is owned by your uid.
- Inside the mount ns only bound store paths exist: `env` at `/usr/bin` is
  absent, so call it by its store path (from the jail's PATH).
- `/sys/class/net` and `/proc/net` are absent; test the network with a
  socket connect (python3 `errno.errorcode`) — `ENETUNREACH` proves the
  offline netns; curl's rc 6/7 wording is not "Network is unreachable".
- Confirm you are in: compare `readlink /proc/$P/ns/{user,mnt,net}` with
  `/proc/self/ns/*`.

Launching the jailed daemon from an agent's Bash tool: `nohup … &` dies with
the tool's process group; use `setsid -f bash -c '<launcher> > log 2>&1
< /dev/null'` and stop it with `kill -TERM -- -<pgid>`.
