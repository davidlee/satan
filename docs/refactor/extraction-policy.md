---
name: satan-refactor-extraction-policy
description: SATAN module extraction policy — lives in doctrine as POL-001 (re-homed 2026-07-22)
metadata:
  type: policy
  topic: satan-refactor
  status: superseded
  updated_at: 2026-07-22
---

# Extraction policy → POL-001

This living doc migrated to a governance layer on 2026-05-30 (then
`spec-driver`, since superseded by `doctrine`). The standing extraction test,
the earns-the-seat / anti-candidate lists, the triggers, and the principles
live in policy **POL-001**, re-homed into this repository's corpus on
2026-07-22:

```
doctrine policy show POL-001
```

Its destination — what the extractions converge on — is **ADR-017** (Emacs is
a client) with the topology and ordering in **ADR-018**.

The trigger-gated extraction **candidates** are backlog items (`IMPR-` in the
prior tool's prefix, `IMP-` in doctrine's):

| Candidate | Backlog |
| --- | --- |
| Patch runner → `satan-patcher` | `IMP-006` |
| Memory substrate → `satan-memoryd` | `IMP-007` |
| Audit verifier → `satan-audit` CLI | `IMP-008` |
| Observer → daemon | `IMP-009` |
| Active beachhead: `satan-attrd` capsule render | `IMP-003` (resolved; not migrated) |

Companions unchanged: [`plan.md`](plan.md) (active refactor themes),
[`../governance.md`](../governance.md) (broker trust boundary),
[`../attributes/design-contract.md`](../attributes/design-contract.md).

POL-001's seat lists were written against `.emacs.d/` paths and pre-extraction
assumptions; they need a mechanical pass, not a re-argument (ADR-018 D6).

The full prior text lives in git history.
