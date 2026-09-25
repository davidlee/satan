# A green full suite can hide an order-dependent test

Selecting one broker test with `ert-run-tests-batch-and-exit` reports a
different verdict from the full run:

```
$ SATAN_TEST_ALLOW_NO_DB=1 emacs --batch -L ./satan -L ./dev -L ./satan/test \
    -l satan-test -l satan-broker-test \
    --eval '(ert-run-tests-batch-and-exit "run-emits-one-tick-row-outcome-spawned")'
  FAILED  satan-broker/run-emits-one-tick-row-outcome-spawned
  (should (equal "spawned" (plist-get row :outcome)))
    -> "credential_unavailable"
```

In the full suite it passes: an earlier test leaves a credential stub in place.
So the test's verdict depends on what ran before it, and a targeted run is a
reliable source of false red.

**Do:** treat a single-test red as unproven until reproduced in a full run —
and the inverse, a single-test green, as unproven until the full run agrees.
When hunting a failure, run the whole suite; when a full run is green, do not
claim the isolated test passes.
