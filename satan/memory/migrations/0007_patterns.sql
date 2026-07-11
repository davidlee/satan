-- 0007_patterns.sql
-- DE-009: SATAN pattern records and scars — outcome-linked pattern-local learning.
--
-- Adds the audited attribution input (percept_handles_json snapshot on
-- satan_interventions), durable pattern definitions (satan_patterns, synced
-- from patterns.eld), and the rebuildable pattern-outcome projection
-- (satan_pattern_outcomes + satan_pattern_stats view).
--
-- Design: DR-009 §4.1; also DEC-4 (snapshot), DEC-5 (schema), DEC-6 (rebuild).
--
-- This migration is forward-only; ADD COLUMN … DEFAULT '[]' backfills
-- existing rows harmlessly.  The projection is empty until Phase 02
-- delivers satan-pattern-rebuild.

-- ============================================================
-- audited attribution input: snapshot of the run's percept
-- handles at fire time.  Existing rows backfill to '[]' (predate
-- the feature → match nothing; acceptable).
-- ============================================================
ALTER TABLE satan_interventions
  ADD COLUMN percept_handles_json JSONB NOT NULL DEFAULT '[]'::jsonb;

CREATE INDEX satan_interventions_percept_handles_gin
  ON satan_interventions USING GIN (percept_handles_json jsonb_path_ops);

-- ============================================================
-- satan_patterns
-- ============================================================
-- Curated pattern definitions, synced idempotently from
-- satan/patterns.eld by satan-pattern-sync (Phase 02).
-- enabled gates future action (out-of-scope for v1), NOT
-- historical attribution — a disabled pattern keeps its scars.

CREATE TABLE satan_patterns (
  id                    TEXT PRIMARY KEY,
  label                 TEXT NOT NULL,
  cue_handles_json      JSONB NOT NULL,
  default_intervention  TEXT,
  intrusion_ceiling     TEXT,
  priority              INTEGER NOT NULL DEFAULT 0,
  enabled               BOOLEAN NOT NULL DEFAULT true,
  notes                 TEXT,
  updated_at            TIMESTAMPTZ NOT NULL
);

-- ============================================================
-- satan_pattern_outcomes
-- ============================================================
-- Rebuildable projection: one row per unique (pattern_id,
-- intervention_id) for mature, non-unknown outcomes whose
-- intervention's percept snapshot ⊇ the pattern's cue_handles.
--
-- No FK to satan_interventions: 0006's rebuild does TRUNCATE
-- satan_intervention_outcomes, satan_interventions and
-- PostgreSQL refuses to truncate a table with an un-listed FK
-- child referencing it.  intervention_id is a plain indexed
-- column; the rebuild only ever inserts live ids, so it cannot
-- dangle in practice (DR-009 §4.1).

CREATE TABLE satan_pattern_outcomes (
  pattern_id      TEXT NOT NULL REFERENCES satan_patterns(id) ON DELETE CASCADE,
  intervention_id TEXT NOT NULL,
  classification  TEXT NOT NULL CHECK (classification IN
                      ('worked','neutral','ignored','contradicted','harmful')),
  ts              TIMESTAMPTZ NOT NULL,
  PRIMARY KEY (pattern_id, intervention_id)
);

CREATE INDEX satan_pattern_outcomes_intervention_idx
  ON satan_pattern_outcomes(intervention_id);

-- ============================================================
-- satan_pattern_stats
-- ============================================================
-- Derived view over satan_patterns + satan_pattern_outcomes.
-- unknown/pending and immature outcomes are excluded at rebuild
-- time (Phase 02), so the view never treats a pending row as
-- "tested" (Codex MAJOR).  The last_outcome tie-breaker
-- (ts DESC, intervention_id DESC) is deterministic across
-- interventions sharing a run's frozen time_now (Codex MAJOR).

CREATE VIEW satan_pattern_stats AS
SELECT
  p.id AS pattern_id,
  count(*) FILTER (WHERE o.classification = 'worked')       AS success_count,
  count(*) FILTER (WHERE o.classification = 'ignored')      AS ignored_count,
  count(*) FILTER (WHERE o.classification = 'contradicted') AS contradicted_count,
  count(*) FILTER (WHERE o.classification = 'harmful')      AS harmful_count,
  max(o.ts)                                                 AS last_tested_at,
  (SELECT o2.classification FROM satan_pattern_outcomes o2
     WHERE o2.pattern_id = p.id
     ORDER BY o2.ts DESC, o2.intervention_id DESC LIMIT 1)  AS last_outcome
FROM satan_patterns p
LEFT JOIN satan_pattern_outcomes o ON o.pattern_id = p.id
GROUP BY p.id;
