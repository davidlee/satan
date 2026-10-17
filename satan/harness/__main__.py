"""SATAN gptel harness entrypoint.

Drives a chat-completions loop against the LLM gateway (one
OpenAI-compatible endpoint). Speaks the SATAN JSONL protocol on
stdin/stdout: ready -> 0..N tool_calls (results back on stdin) -> final.

Termination signal from the model is a tool call to `satan_final`
(summary, actions[]); the adapter intercepts and emits the broker's
`final` record.

Env (set by the broker):
  SATAN_RUN_ID, SATAN_RUN_DIR    bind/mount paths inside the jail
  SATAN_MODEL                     gateway model alias (e.g. deepseek-flash)
  SATAN_BUDGET_TOKENS             cumulative input+output ceiling (int)
  SATAN_MAX_BUDGET_TOKENS         hard backstop ceiling (int)
Env (set by the jail launcher, not the broker):
  LLM_GATEWAY_URL, LLM_GATEWAY_KEY   gateway base URL and its key

Modules under this directory are flat (no top-level `__init__.py`); the
bootstrap below ensures `import protocol` / `import bundle` /
`import runloop` resolve from this dir whether invoked as
`python __main__.py` or `python -m unittest test_gptel_harness` from
within it.
"""

from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from runloop import main  # noqa: E402


if __name__ == "__main__":
    sys.exit(main())
