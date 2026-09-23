The `goad_ask` handler validates the form before step 4 (record). An invalid form is a refusal returned to the model with the reason — like the quiet-window refusal it records no suppression, because nothing was decided about the question. Validation is SATAN's closed subset of goad SPEC-001: the tool's `:args-schema` fixes the shape (field `kind` from the five, `min`/`max` only on number, `options` required on choice and carrying id + label only, no other keys — SATAN emits no hints), and one pure elisp function checks what a schema cannot: at least one option, unique option ids, unique field ids within an option, unique alternative ids within a choice field (R-14, R-52), `min <= max`, and ids matching `[a-z0-9_-]+`.

`backend.py` does not re-validate the protocol. Its per-entry shape check (PHASE-02 A3) extends only to: `form` absent, or a non-empty list of objects each carrying string `id` and `label`; otherwise the entry is malformed and dropped, as today. The queue's only writer has validated the form, and the host degrades safely on anything else (SPEC-001 §3).

Rejected: validating in both languages (two rule sets to drift apart); validating only in backend.py (the ask would already be recorded and projected, so a bad form would cost an undelivered verdict and teach the model nothing).

Residual risk: a hand-edited queue whose form passes the backend's check but not the host's makes goad show nothing until that ask expires (at most 60 minutes, sec-3).


**Amended (RV-015 F-1, F-7, F-8, F-10).** SATAN's `:args-schema` validator has no closed objects and no rules keyed to the field kind (`satan-tools.el` `satan-tool--validate-value`: extra keys pass, and nothing conditions a key on `kind`). The schema therefore only declares `form` as an optional array. **One pure function, `satan-goad-form-validate`, owns every rule:**
- closed keys at every level, so an unknown key is refused (SATAN emits no hints);
- `min` / `max` only on a number and `options` only on a choice (R-50);
- a choice alternative is exactly `{id, label}` (R-53);
- the uniqueness rules (R-14, R-52);
- `min <= max`;
- the id pattern `[a-z0-9_-]+`;
- a present-but-empty `form` is refused, not read as "no form" (a JSON `[]` decodes to nil);
- size caps: at most 8 options, at most 8 fields per option, each label at most 200 characters, and the serialised form at most 8 KiB.

It returns the form rebuilt from the named keys, and only that value is recorded. The handler calls it at step 3, before record (step 5).