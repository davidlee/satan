## What this settles

Three things the wire contract needs and the locked design (revision 80) does not
name. They are settled here rather than by reopening the design, and they fold back
into it through a reconcile-time REV.

### 1. `tools-not-allowed`

`pi_agent.tools` may only narrow the profile's set (design sec-2). A request naming
a tool outside the profile's **snapshotted** set is refused `tools-not-allowed` at
validation step 3–4, before the session step, with a `detail` naming the first
offending tool. The effective set is the intersection; because pi's `--tools`
*replaces* the selection, the whole narrowed list is passed, not the caller's
subset.

Why a new token: `profile-not-allowed` blames the policy's allowlist, which is not
what failed. The call asked for authority it does not have.

### 2. `request-invalid`

A malformed params object — not an object, `prompt` or `profile` absent, an unknown
key, a wrong type — is refused `request-invalid` with a `detail` naming the field.
It is a tool result (`content` + `isError`), never a JSON-RPC error, per sec-1;
`refusal.reason` carries the token and `session` is `null`, since nothing ran and
none was minted.

Why a new token: none of `policy-invalid`, `profile-invalid` or `session-invalid`
describes the request's own shape, and reusing one would point an operator at the
wrong artefact.

### 3. Cancellation

`notifications/cancelled` carrying `requestId` aborts exactly that call through the
one termination ladder (SIGTERM group, 2 s, SIGKILL group, reap, drain, audit) and
the call reports `state: cancelled` / `termination: cancelled`. A `requestId` that
names no in-flight call is ignored, not an error.

stdin EOF is a different act and a different outcome: the client is gone, so
nothing can be delivered. The server stops admitting new calls, aborts in-flight
runs through the same ladder, flushes the audit and exits — no attempt to send a
result down a closed channel.

Why this needs stating: `cancelled` is in both sec-5 enums and sec-4 says a
blocking result never blocks cancellation, but no mechanism was named. A driver
that closes stdin and a driver that cancels one call of two are indistinguishable
without it, and getting it wrong either loses a finished answer or leaves a child
behind.

## What it commits

The SL-029 plan writes these into phase criteria (PHASE-02 for the wire methods and
`request-invalid`, PHASE-03 for `tools-not-allowed`, PHASE-06 for the cancellation
semantics). Until the REV lands at reconcile, the design's sec-2 token list plus
this record are the contract; an audit that reads only one of them will report a
divergence that is already accounted for.
