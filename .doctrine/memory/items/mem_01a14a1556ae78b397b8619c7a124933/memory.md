# LLM gateway (LiteLLM 1.102) error and reasoning shapes

Probed live on 127.0.0.1:4000 and read from the litellm 1.102.1 store path,
2026-10-18 (SL-022):

| condition | HTTP | body `type` / message |
|---|---|---|
| bad or revoked key | 401 | auth error |
| key budget exhausted | **429** | `budget_exceeded`, "Budget has been exceeded! …" (`exceptions.py` BudgetExceededError, `proxy/auth/auth_exception_handler.py`) |
| model not on the key's model list | 403 | "… not allowed to access model …" (`proxy/auth/auth_checks.py`) |

- A 429 budget error looks like rate limiting unless the client checks the
  error type; the openai SDK exposes it as `e.type` and retries a 429 twice
  by default.
- `deepseek-flash` returns `reasoning_content` through the gateway and accepts
  it echoed back on an assistant turn.
