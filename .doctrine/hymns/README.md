# Hymn Corpus — Authoring Convention

## Band Registry

| Band      | Segment     | Purpose                                                              |
|-----------|-------------|-----------------------------------------------------------------------|
| preamble  | `preamble`  | Universal preface (every resolution)                                 |
| harness   | `harness`   | Harness-specific guidance                                            |
| model     | `model`     | Trait-keyed classification vocabulary (adherence, capability trees)  |
| role      | `role`      | Orchestrator vs worker envelope                                      |
| stage     | `stage`     | Phase-contextual prose                                               |
| project   | `project`   | Project-specific / user-authored                                     |

Bands are a **closed registry, fixed order**. A band decides WHERE a snippet
lands in the composed output; it never enters matching. A selector may pin
ANY axis regardless of its own snippet's band (a `role/worker` snippet may
pin a model trait). Trait trees WITHIN the model band are **open** —
extending the model vocabulary never touches the band registry.

## The model band is a trait vocabulary, not a model registry

Model identity (`vendor/name`) is a leaky proxy for a trait tuple — it does
not carry to the next model and mis-fires when a model's real traits diverge
from its vendor path. The honest axes are TRAITS, authored as orthogonal
trees within the model band: `adherence/*` (e.g. `adherence/low`),
`capability/code/*`, `capability/reasoning/*`. A `vendor/name` identity key
stays expressible — it is just another path — but carries no privileged
semantics. Keys are opaque to the engine; meaning lives entirely in the
authored corpus. There is no central model registry, and the vocabulary is
user-definable.

## Path → Slot Rule

`<band>/<label>.md` → slot `{ band, label }`. The label is the full relative
key under the band — a model label (e.g. `anthropic/claude-sonnet-4`) or a
trait path (e.g. `adherence/low`) alike. The filename stem (minus `.md`)
becomes the slot label. Directory structure under a band maps exactly to slot
labels.

## Sidecar Overlay

A `.toml` file adjacent to the `.md` overlays selector axes. Example:

```toml
# harness/claude.toml
harness = "claude"
model = "anthropic/_default"
```
The sidecar overrides the path-derived defaults; undeclared axes keep their default.

## Seal / Expose

Two sides of one coin, both **single-emit**:

- **sealed** slot: the framework (embedded) snippet is authoritative — a
  user-provenance twin at that slot is dropped BEFORE matching. Framework
  wins by active exclusion of its disk twin.
- **exposed** slot: the projector writes an editable starter to disk AND
  writes a sidecar `replaces = <own slot>`. The user twin self-`replaces` its
  own framework origin, making it the unique strict top of the slot — user
  wins by SUPPRESSION, not by the provenance tiebreak below.

## Provenance

- `Framework`: shipped with the binary (embedded under `install/hymns/`).
- `User`: on-disk under `.doctrine/hymns/`.

Precedence key (ascending; last word wins):

    band → specificity → provenance(framework < user) → alpha(full slot path)

Specificity dominates provenance — a framework exact-trait snippet outranks a
user broad one. The provenance leg is **ordering only**: it reorders
same-slot twins, it never suppresses one. `replaces` is the only suppression
mechanism (see Seal / Expose above) — there is no "user always wins at equal
specificity" rule.
