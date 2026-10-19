# EVD-011: pi-env: two concurrent clients on one room user are independent; non-login ssh PATH has the room base

Bears on SL-027 inq-2 (shape of the shared room module: a session both
clients hold, not two thin adapters — malebolge RFC-001 §5's caution) and
inq-4 (a daemon outside any repo launches pi-env directly; `session` is not
needed for the room base on PATH).

Consistent with the code reading in SL-027 research (Thread 2 Q2): each
`Connection` spawns its own `ssh … serve --token` child
(`pi/env/src/connection.ts:268-283`).
