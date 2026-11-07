`satan-attribute-listener--handle` rejects by writing `satan_audit_replies` and dropping the audit inbox row. The daemon's `process_reply_row` logs `broker rejected attribute.delta_applied` and deletes the reply row. By then the delta and the event row are in Postgres; only the `transcript.jsonl` line is lost.

So an event row does not prove the broker accepted the event, and an empty `satan_audit_replies` proves nothing. To check acceptance, match the reason in the run's `transcript.jsonl` (other sensors write the same event to the same file) and search the `satan-attrd` journal.
