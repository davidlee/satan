# glossary

The kinds below group into a small set of durable entities + typed facets.

| kind                         | abbr     | folder |
|------------------------------|----------|:------:|
| **specs**                    | --       |        |
| product requirements doc     | PRD-001  |   y    |
| technical specification      | SPEC-001 |   y    |
| revision                     | REV-001  |   y    |
| requirement                  | REQ-001  |   y    |
| requirement label (membership) | FR-001 / NF-001 |  |
| **slices**                   | --       |        |
| slice                        | SL-001   |   y    |
| tech design                  | DES-001  |        |
| design review                | RVW-001  |        |
| implementation plan          | PLN-001  |        |
| phase sheet                  | PHASE-01 | phases |
| audit                        | AUD-001  |   y    |
| **governance**               | --       |        |
| policy                       | POL-123  |        |
| standard                     | STD-123  |        |
| architecture decision record | ADR-001  |        |
| **knowledge records**         | --       |        |
| assumption                   | ASM-001  |   y    |
| decision                     | DEC-001  |   y    |
| question                     | QUE-001  |   y    |
| constraint                   | CON-001  |   y    |
| evidence                     | EVD-001  |   y    |
| hypothesis                   | HYP-001  |   y    |
| **backlog**                  | --       |        |
| issue                        | ISS-001  |   y    |
| improvement                  | IMP-001  |   y    |
| chore                        | CHR-001  |   y    |
| risk                         | RSK-001  |   y    |
| idea                         | IDE-001  |   y    |

## reference forms

How to cite things in prose, commits, and comments. The id is identity; the slug
is never authoritative.

**Entity ids — prefixed, 3-digit zero-padded** (the `abbr` column above):
`SL-020`, `ADR-004`, `PRD-009`, `REQ-059`, `RSK-004`, `ASM-001`. Cite the *durable*
id, never a mobile membership label (`FR-`/`NF-` move per spec — use the `REQ-NNN`
they label).

**Document-local enumerations — bare** (prefix + integer, no zero-pad, no dash):
they are scratch refs within one document, not entity ids.

| ref | meaning | authored in |
|---|---|---|
| `OQ-1` | open question | spec / slice / design |
| `D1`   | decision | design §7 |
| `R1`   | review finding | design §10 |
| `Q1`   | design question | design / slice |
| `C1`   | charge | inquisition |

**Phase ids — `PHASE-01`** (2-digit, immutable; edits append, never renumber). The
sheet *file* is `phase-01.md` (lowercase).

**Criteria ids** (authored in `plan.toml`, immutable; bare, no pad):

| ref | meaning |
|---|---|
| `EN-1` | entry criterion |
| `EX-1` | exit criterion |
| `VT-1` | verification by **test** (automated) |
| `VA-1` | verification by **agent** check |
| `VH-1` | verification by **human** acceptance |

`VT`/`VA`/`VH` are the three verification modes — pick by *who/what* confirms the
criterion. Non-retroactive: existing `VT-` criteria stay valid as "by test."

## knowledge record lifecycle vocabulary

Each knowledge record kind carries a status vocabulary:

| kind       | status vocabulary |
|------------|-------------------|
| assumption | `pending \| proven \| disproven \| withdrawn` |
| decision   | `pending \| active \| superseded \| withdrawn` |
| question   | `open \| answered \| settled \| withdrawn` |
| constraint | `active \| relaxed \| removed \| withdrawn` |
| evidence   | `captured \| disputed \| confirmed \| retracted \| superseded` |
| hypothesis | `proposed \| confirmed \| refuted` |

Evidence (`EVD`) and hypothesis (`HYP`) records may be linked to other knowledge
records via `supports` / `disputes` evidentiary edges (`doctrine link EVD-1
supports DEC-2`). An EVD's `confirmed` status is deliberately non-terminal — it
can be reopened or superseded by subsequent evidence. A HYP's `confirmed` means
the hypothesis is supported by evidence; `refuted` means it has been falsified.

## directory layout

### `.doctrine/slice/nnn/` — a slice's authored home

| file | tier | purpose |
|---|---|---|
| `slice-nnn.toml` | authored | metadata, relations, lifecycle status |
| `slice-nnn.md` | authored | scope document |
| `design.md` | authored | canonical technical design |
| `plan.toml` | authored | phase plan (objectives, EN/EX/VT criteria, links) |
| `plan.md` | authored | plan prose — rationale & sequencing (no queried data) |
| `notes.md` | authored | durable implementation notes (on-demand) |
| `audit.md` | authored | verification / code-review / drift findings |
| `handover.md` | **runtime** (gitignored) | disposable agent context |
| `phases/` | **runtime** (gitignored) | symlink into `.doctrine/state/slice/nnn/phases/` |

Also permitted inside a slice, spec, or backlog dir:
- `research/*`
- `context/*`

### `.doctrine/adr/nnn/` — architecture decision records

`adr-nnn.toml` + `adr-nnn.md`, plus an `nnn-slug` symlink alias. Authored, project-global.

### `.doctrine/memory/items/nnn/` — memory store

`memory.toml` + `memory.md` per item, with `mem.<key>` symlink aliases for direct lookup.

### `.doctrine/governance.md`

User-owned governance pointer layer — projected into the boot snapshot.

### `.doctrine/state/` — runtime phase tracking

`.doctrine/state/slice/nnn/phases/phase-NN.{toml,md}` — gitignored, disposable.
