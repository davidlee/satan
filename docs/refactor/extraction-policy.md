---
name: satan-refactor-extraction-policy
description: SATAN module extraction policy — migrated to spec-driver POL-001 (2026-05-30)
metadata:
  type: policy
  topic: satan-refactor
  status: superseded
  updated_at: 2026-05-30
---

# Extraction policy → spec-driver POL-001

This living doc has been **migrated to the spec-driver governance layer**
(2026-05-30). The standing extraction test, the earns-the-seat / anti-candidate
lists, the triggers, and the principles now live in policy **POL-001**:

```
spec-driver show policy POL-001
```

The trigger-gated extraction **candidates** are now backlog items:

| Candidate | Backlog |
| --- | --- |
| Patch runner → `satan-patcher` | `IMPR-006` |
| Memory substrate → `satan-memoryd` | `IMPR-007` |
| Audit verifier → `satan-audit` CLI | `IMPR-008` |
| Observer → daemon | `IMPR-009` |
| Active beachhead: `satan-attrd` capsule render | `IMPR-003` |

Companions unchanged: [`plan.md`](plan.md) (active refactor themes),
[`../governance.md`](../governance.md) (broker trust boundary),
[`../attributes/design-contract.md`](../attributes/design-contract.md).

The full prior text lives in git history.
