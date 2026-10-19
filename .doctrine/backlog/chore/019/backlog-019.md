# CHR-019: SL-023 residue: stale SL-006-provisional comments, CeilingLatch name, unused resume event kind, stale data-collection doc

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

**Origin:** SL-023 audit RV-029 F-21 (and F-7, F-11).

- Comments that oubliette SL-006 is unshipped / the room adapter provisional —
  SL-006 is done and the adapter matches its locked design (RV-029 F-7):
  `~/dev/malebolge/src/runner/room.ts:6,262`, `src/runner/config.ts:84`,
  `test/runner/room-fixture.ts:20`, `test/runner/config-fixture.ts:60`.
- `CeilingLatch`/`ceilingLatch` (`src/runner/ceiling-latch.ts`, `run.ts`) also
  carries `host_key`; rename (e.g. `RunLatch`).
- `vocab.ts` `EVENT_KINDS` keeps `resume`, which nothing writes (the
  `waiting_room → running` transition is the resume's record); drop it or
  write it — follow whatever reconcile writes into design §5.3.
- `~/dev/satan/docs/data-collection.md:349` still names
  `satan_patch.patch_jobs` + a worktree as the patch-job target.
