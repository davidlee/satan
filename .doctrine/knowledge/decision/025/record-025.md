Every rendered option of a SATAN ask — the default Yes / No included — gets the id `opt:<option-id>:ask:<intervention_id>`. `answer()` keeps its single verb split (`opt`), then splits the option id off at its first `:`; the remainder is the item id, exactly as today. SATAN option ids are therefore restricted to `[a-z0-9_-]+`, which also keeps them clear of goad's reserved verbs. `later:ask:<id>` and `enough:` are unchanged, and `yes:` / `no:` remain the checklist's verbs only.

An ask's answer is stored as `value: {"option": <option-id>, "values": <response.values verbatim>}` beside `at`, merged into the ask's record so `presented_at` survives (PHASE-02's A7 rule). The backend never interprets the values: goad SPEC-001 R-57 fixes each value's JSON type by its field kind, and R-58 fixes which keys are present. Checklist answers keep their boolean `value`.

The observer is unchanged in logic: the answer predicate (sec-5) tests only that `value` is present and `at` falls in the window, and DEC-011's trace carries the value — now this object — verbatim.

Rejected: a boolean `value` for form-less asks beside an object for form asks (two shapes for one record kind, and every reader would branch).


**What the values can tell (RV-015 F-6).** goad submits a value for every field it drew, untouched ones included: `false`, `""`, the number's `min` or `0`, the first choice alternative, the epoch for a datetime (SPEC-001 §6.2). A stored value therefore cannot tell *answered* from *left alone*. A form that needs that distinction has to build it in: an explicit "skip" alternative on a choice, for example. `tools/goad_ask.md` teaches this. `yes:` / `no:` are `backend.py`'s checklist verbs; goad itself reserves no option ids.