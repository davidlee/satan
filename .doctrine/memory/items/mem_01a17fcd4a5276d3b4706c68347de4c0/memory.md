satan-mcp (the Emacs MCP server) returns tool results as **printed Lisp** in the
text content, e.g. `(:scope current :presence "typing" …)`, not JSON. A
TypeScript client reads them by pattern: malebolge's `presenceOf`
(`src/wake/presence.ts`) takes the first `:presence "<word>"` by regex and maps
no match, `:status "missing"` or `isError` to `unknown`. Treat any other field
the same way: parse narrowly, fail to a neutral value. Related wire trap:
[[mem.fact.satan.tool-result-nil-renders-as-empty-object]] (nil → `{}`).
