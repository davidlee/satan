# Room jail: Jev loopback bridge and screwtape credential for malebolge classify

malebolge SL-007 (classified mail) decided, operator 2026-10-29 (malebolge
DEC-059), that the room daemon's mail tools run `screwtape classify` inside
the jail. The contract malebolge relies on:

1. **Bridge.** `mkJailedMalebolge`'s launcher wraps the daemon *inside* the
   jail: start `socat TCP-LISTEN:4000,bind=127.0.0.1,fork,reuseaddr
   UNIX-CONNECT:<gatewayClientSocket>`, then exec the daemon. Port 4000
   matches the host relay, so screwtape's one config (`jev.baseUrl =
   http://127.0.0.1:4000`) serves both. Probed: loopback is up under
   `--unshare-net`, and a socat loopback-to-unix bridge works there.
   Unverified: whether `makeJailedAgent` admits a wrapper agent command.
2. **Credential.** `malebolge-room.service` decrypts screwtape's Jev
   credential (flakes IMP-055). Bind `$CREDENTIALS_DIRECTORY` (the unit's
   `/run/user/1000/credentials/malebolge-room.service`) read-only into the
   jail and `set-env MALEBOLGE_SCREWTAPE_CREDENTIALS` to it. Malebolge hands
   it to the classify child only, as `CREDENTIALS_DIRECTORY`.
3. Unset variable: malebolge's mail tools refuse every call, naming the reason.

To confirm in passing: the gateway's client socket serves Jev's path
(`/v1/systemone`) as the relay does (malebolge SL-007 probes it first).
