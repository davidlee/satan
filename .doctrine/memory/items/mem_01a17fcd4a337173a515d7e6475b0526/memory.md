Found in SL-034 PHASE-03 (RV-062 F-13, demonstrated through the real
openai-completions adapter):

- pi-ai's `timeoutMs` stops at response **headers** on the openai-completions
  path: the OpenAI SDK clears its timer when `fetch` returns, so a stream that
  sends headers (or one chunk) and then stalls hangs the run forever.
- pi-durable retries a model error only when `stopReason` is `error` **and** the
  message matches pi-ai's retryable patterns (`utils/retry.ts`). Wording such as
  "timed out" is retryable — the run then sleeps in backoff instead of failing.
- malebolge's fix: `withStreamDeadline(api, ms)` in `src/models.ts` (2 h,
  `MODEL_STREAM_DEADLINE_MS`) bounds request start → end of body, aborts the
  inner request and ends the stream with `model stream exceeded 2h`, which is
  deliberately non-retryable. Its test pins the request count, so a wording
  change that becomes retryable fails it.
