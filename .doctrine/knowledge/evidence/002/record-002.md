## Sites

- `~/dev/goad/crates/goad-emit/src/main.rs` — the exit-code doc comment on `exchange` and its three arms: `Ok(Answered::Accepted) => ExitCode::SUCCESS`, `Ok(refused) => to_stderr(refused_line); ExitCode::from(1)`, `Err(fault) => to_stderr(fault_line); ExitCode::from(2)`.
- `~/dev/goad/crates/goad-emit/src/render.rs:59` — the reason **token is first** deliberately, "so a wrapper can branch on it".
- `~/dev/goad/crates/goad-emit/tests/binary/exchange.rs` — asserts the codes (0/1/2) and that the refusal text lands on stderr.
- `~/dev/satan/satan/satan-trace.el:227-266` — `satan-trace-call` returns `(:exit N :stdout STR :timed-out BOOL)`.

## The correction

SL-016's research round recorded (thread 2, X4) that `satan-trace-call` "returns stdout only and discards stderr", and concluded the doorbell would need the raw two-buffer `call-process` pattern plus new refusal-parsing mechanism with no template in the tree.

That is wrong. `satan-trace-call` uses `call-process` with DESTINATION `t`, which mixes stderr into the destination buffer. Verified:

```
$ emacs --batch --eval '(with-temp-buffer (let ((exit (call-process "sh" nil t nil "-c" "echo OUT; echo ERR 1>&2; exit 1"))) (princ (format "exit=%s buffer=%S\n" exit (buffer-string)))))'
exit=1 buffer="OUT\nERR\n"
```

So both the exit code and the refusal line reach the caller through the ledgered path.

## Why it is unambiguous

goad's success is silent (005/D-7 — "a message that prints on success trains its owner to ignore it"), and a refusal writes one stderr line and nothing to stdout. So the mixed buffer holds at most one line, ever. There is no interleaving hazard to design around.

## The timeout is mandatory

`render.rs` USAGE: *"The host answers when it has judged the event, and takes as long as that takes; emit sets no deadline of its own. Wrap it if you need one."* goad-emit will block while the host deliberates. ADR-018's cited failure mode — handlers run synchronously in the broker's host process — therefore binds for real, and `satan-trace-call`'s `timeout -k 2` wrapper is the correct tier rather than a nicety.

## What this settles for SL-016

The ledgered tier suffices; no raw two-buffer call-process and no structured-refusal parser. goad-emit's contract is a three-value exit code (main.rs, exchange): 0 accepted and silent, 1 host refused with one line on stderr, 2 no usable answer with one line on stderr. satan-trace-call returns (:exit N :stdout STR :timed-out BOOL), so :exit alone carries the accepted/refused/faulted tri-state the doorbell needs. The claim that satan-trace-call discards stderr is false: it calls call-process with DESTINATION t, which mixes stderr into the same buffer, so the refusal line is also in :stdout. Verified empirically. Unambiguous because success is silent (goad 005/D-7) and a refusal writes exactly one line and nothing to stdout, so at most one line ever appears. The refusal reason token is first by design (render.rs:59, 'so a wrapper can branch on it'). retry_after_ms is the only thing a parser would add, and goad reports it as advice never obeyed, which matches delta 5's no-retry-machinery finding. Separately: goad-emit sets no deadline of its own and says to wrap it, so ADR-018's timeout(1) requirement is mandatory, not stylistic, and satan-trace-call's timeout -k 2 is the right tier.