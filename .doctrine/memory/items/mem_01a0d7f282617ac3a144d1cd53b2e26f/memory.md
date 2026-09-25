`satan-jsonl-send` serialises with `:null-object :null :false-object :false`.
Under those arguments a plain elisp `nil` is **not** JSON `null` and not
`false` — it renders as `{}`:

    (json-serialize (satan-jsonl-prepare (list :truncated nil))
                    :null-object :null :false-object :false)
    ;; => {"truncated":{}}

So a result field whose *false* value is `nil` reaches the model as an empty
object, which is ambiguous (truthy in JS/Python, empty-looking in prose). The
codebase's wire-false marker is the keyword `:false`; `t` renders as `true`:

    ;; {"truncated":false}   {"truncated":true}

Emit `(if FLAG t :false)` for any boolean result field. Precedents, all in tool
result payloads: `satan-tools-content.el` `:truncated_results` (:265, :338),
`satan-tools-goad.el` `:asked`/`:delivered`, `satan-tools-notify.el`
`:delivered`, and `satan-tools.el`'s own `:ok :false`.

Sharp edge: `:false` is **truthy in elisp** (`(eq v :false)`, never
`(null v)`), so an elisp consumer must test for the keyword. There are no such
consumers today for `:truncated`.

An empty *list* cannot be fixed this way — `:matches '()` is nil too and also
renders `{}`; making it `[]` needs a vector on the elisp side. That remains the
system-wide question (ISS-033; ISS-027 and IMP-015 in the family).

Found by the SL-020 audit (RV-020 F-7), fixed there in `5dca87c`.
