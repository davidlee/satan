# IMP-062: Expose room synchronization to interactive SATAN

Provide a no-argument native pi-durable interactive `sync_room` tool for `just sync-room`. The recipe pushes host refs and fast-forwards clean room checkouts; it skips dirty or divergent checkouts.

## Sketch

Reuse the deployed host bridge pattern with a separate socket-activated fixed-command service and a longer deadline. Prevent concurrent syncs with a host lock. The model-facing tool is unsafe to replay, returns bounded output, and reports that a failed or interrupted operation may have partially completed. Verify with isolated socket and subprocess fixtures; do not run the real synchronization as a test.

## Implementation

Added native `sync_room` with unsafe replay semantics, a dedicated socket-activated host service, a nonblocking sync lock, a five-minute helper deadline and bounded output. Errors warn of partial completion. Focused tests use a fake `just`; live synchronization, service activation and deployment remain unverified.
