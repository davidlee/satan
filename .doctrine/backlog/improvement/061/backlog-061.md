# IMP-061: Expose room checkout divergence to interactive SATAN

Provide a no-argument `room_behind` tool for interactive SATAN. Run `just room-behind` from `~/flakes`, return its TSV output, and surface failures and timeouts. The recipe compares the room checkouts with configured host branches.

## Sketch

Expose a native pi-durable interactive tool. The daemon runs jailed, while the recipe needs host access and the capsule socket, so identify a host-side execution bridge. Bound execution and output; report nonzero exits and launch errors. Verify registration, successful output, timeout, and failure handling with focused tests. The host bridge and native tool must avoid duplicate model-facing registrations.

## Implementation

The native interactive `room_behind` tool calls a dedicated socket-activated host helper. The helper runs `just room-behind` in `~/flakes` with pipefail and a deadline; the jail receives a read-only socket-directory bind. The service and jail configuration require deployment and a daemon restart. A local helper probe reported an SSH configuration ownership error, so successful live output remains unverified.
