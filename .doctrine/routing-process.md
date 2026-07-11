**Route before you act.** At the start of ANY substantive work, choose the
governing skill *before* inspecting files, running commands, or writing code.
When unsure, route to the stricter skill. No code without an approved plan.


| When | Skill |
|---|---|
| Correctness depends on project governance / unfamiliar subsystem / "right way?" | `/canon` + `/retrieve-memory` |
| Substantive work, path not yet clear | `/preflight` |
| Understanding an artifact is the whole task, no change intended | `/walkthrough` (no slice) |
| Reviewing code for quality / correctness — ledgered findings | `/code-review` |
| Authoring or evolving a product / tech spec | `/spec-product` / `/spec-tech` |
| Code-changing intent, no governing slice | `/slice` |
| Slice exists, design missing / stale / unapproved | `/design` (→ `/inquisition` on request) |
| Design locked, no plan | `/plan` |
| Expanding the next phase just before executing | `/phase-plan` |
| Plan approved, phase active | `/execute` |
| Plan approved, driving phases via workers in isolated worktrees | `/dispatch` |
| Implementation done — evidence / reconciliation | `/audit` → `/reconcile` → `/close` |
| Slice exists, audit RV resolved, reconciliation brief written | `/reconcile` |

Unsure where the lifecycle stands: `doctrine status` / `doctrine reports next`.

**Conduct postures** layer on the routed stage — orthogonal to it, composable
with each other, never routed to *instead* of it:

| Posture | Layer it on when |
|---|---|
| `/pair` | working side-by-side with the human in the loop |
| `/walkthrough` | comprehension overlay mid-work (when understanding *is* the task, it's the stage above) |
| `/rigour` | at the edge of capacity — high complexity / uncertainty, costly context, hard-to-reverse steps |

A walkthrough that surfaces a concrete change re-enters `/route`.

Mid-flight, any stage: unanticipated obstacle / tradeoff / emergent complexity →
`/consult` (don't improvise past it). Receiving review findings / corrections →
`/feedback` (adjudicate on evidence; close the loop). Durable gotcha / pattern →
`/record-memory`.
Latent **work** intent (issue / improvement / chore / risk / idea) → `backlog
new` instead of losing it; check `backlog list` at the start of substantive work
(already captured?). Work vs knowledge vs decision boundary: `using-doctrine.md`.
Finished a coherent unit → `/notes`. Handing off to fresh context → `/next`.
Agent confusion / stale memory corpus → `/reviewing-memory`.

**Core process:** `slice new` (scope) → `slice design` (author + adversarial
review until locked) → `slice plan` → `slice phases` → per phase: `phase-plan`
the runtime sheet, flip `in_progress`, implement TDD red/green/**refactor**, end
green, flip `completed` → `/audit` → reconcile → `/close`.

**Guardrails:** use the CLI (prefer the MCP tools if available); don't guess
ids / command shapes / paths — and **read entities via `doctrine <kind> show
<ID>`, not raw files**: structured/queried data lives in `*.toml`, prose in
`*.md`, and `show` synthesizes both tiers (a `.md` body may be empty by design
— never judge an entity from one tier). The plan is not higher authority than
the design or `/canon`. Phase ids (`PHASE-NN`) and criteria ids (`EN-/EX-/VT-`)
are immutable — edits append, never renumber.

**Reference forms.** Entity ids — prefixed, 3-digit zero-padded (`SL-023`,
`ADR-005`, `REQ-059`); cite the durable id, never a mobile membership label
(`FR-`/`NF-`). Doc-local enumerations — bare (`OQ-1`, `D1`, `R1`, `Q1`, `C1`).
Criteria modes — `VT` by test / `VA` by agent / `VH` by human.

**Reference docs (read on demand).** `glossary.md` — kinds, ids, full reference
forms, verification taxonomy. `using-doctrine.md` — which verb for which intent,
reading via `show`, storage tiers, and hand-editing / edit-preserving rules.
