# Corpus-integration tests skip-unless the ~/satan corpus is present

Tests reading SATAN's host-only model-facing corpus (`satan-corpus-root`,
default `~/satan`) must skip-unless the file is present — it is not shipped in
the package (SL-012 D4/POL). Mirrors the DB skip-unless idiom.

```elisp
(skip-unless (file-readable-p
              (expand-file-name "memory_mark.md" satan-tools-descriptions-dir)))
```

**Resolve the path through the defcustom** (`satan-prompts-dir`,
`satan-tools-descriptions-dir`, `satan-system-framing-file`, …) — never
re-derive it (`(expand-file-name "satan/prompts" satan-notes-root)`). A
skip-unless test with a hand-built path does not fail when the corpus moves: it
skips, and the suite stays green. SL-015 PHASE-03 caught four such tests in
`satan-context-test.el` only because the skip *count* rose.

Corollary for any change that relocates or hides the corpus: compare the
skipped-test **set** before and after, not just the unexpected count. With the
corpus present the bar is 3 skips; without it, 10 (the 7 corpus-gated tests).

See [[mem.concept.satan.three-roots]].
