# REV REV-005 — reconcile SL-022

Revision — a pending revise-intent against authored governance/spec
truth. The structured `[[change]]` payload lives in the sister `revision-NNN.toml`;
this prose companion carries the rationale and the free-text before/after excerpts
for prose-body section edits.

## Rationale

<!-- Why this revision: what authored truth needs to change and why, the scope of
     the staged delta, and (for ADR/POL/STD/prose rows) the before/after excerpts
     the structured payload only labels. Seeded at `revision new`. -->

## Rationale

SL-022 moved every SATAN model call onto the host LLM gateway and deleted the
provider-key surface (DEC-041, DEC-042, DEC-044, DEC-049). The jail launcher
reads a gateway client key and passes `LLM_GATEWAY_KEY` to the harness over a
file descriptor, and sets `LLM_GATEWAY_URL`. The broker resolves no key and
emits no `SATAN_PROVIDER`. A child that ends with neither `ready` nor `final`,
and no `error`, is a `spawn_failed` run, and perception frontiers commit on
the first `ready`. The specs and the ADR-017 ledger still described provider
custody. Approved by the user in session, 2026-10-18 ("agreed" to the RV-024
reconcile proposal).

## Reconcile narrative (SL-022, RV-024 F-8)

- **SPEC-003** — spawn contract: the `key` row becomes "none: the jail
  launcher supplies `LLM_GATEWAY_KEY` by fd, and sets `LLM_GATEWAY_URL`";
  `SATAN_PROVIDER` leaves the model+budget row; the base-env paragraph drops
  acquisition, key lookup and the scrub; "Failure at spawn" states the
  `spawn_failed` rule and frontiers-on-`ready`. Overview, diagram and
  responsibilities (md + toml) stop naming the provider and credentials.
- **REQ-020** — restated, not withdrawn: criterion 1 (no buffer-local env
  reaches the child, ISS-037) is live and the spawn contract cites it. Title
  and description now say "one base: the editor's global environment"; the
  key-lookup and `op://` criteria are dropped (ref exclusion moves to REQ-025);
  rationale retires the SL-018 RV-013 N5 coupling. Tag `credentials` removed.
- **REQ-022** — description: the harness reads run identity, model, budgets
  and the gateway pair from env; it holds no provider key.
- **REQ-025** — description: the jail forwards only the declared `SATAN_*`
  vars; the launcher sets the gateway URL and passes the key by fd. Criterion
  4 names the gateway key. New criterion 6: nothing outside the declared
  forwards is visible in the jail (takes over REQ-020's ref exclusion).
  Rationale gap list: ISS-029's gaps closed for the harness. Status stays
  `pending`.
- **SPEC-002** — overview drops the editor's credential backend and names the
  host gateway; the Harness container talks to models through the gateway;
  Transports gains "HTTP, OpenAI-compatible: harness / jailed pi → LLM
  gateway, data plane, per-client key by fd".
- **REQ-016** — rationale: tracked gaps become ISS-028 and ISS-043
  (satan-attrd keys on argv, split from ISS-029). Status stays `pending`.
- **ADR-017** `authority-ledger.md` — Standing notes: provider-credential
  custody is not a SATAN authority item; it left the inventory for the host
  gateway (DEC-049). No new row; RFC-018 D3's proposed row 8 is not added.

Not REV rows (direct edits in the same reconcile): RFC-018 D3/D5
annotations; `docs/governance.md` loses its "until SL-022's reconcile"
sentence; knowledge (DEC-041..049 accepted; DEC-020/021/022 superseded;
ASM-002 obsolete; QUE-001 gate list); ISS-023 closed, ISS-029 resolved.

