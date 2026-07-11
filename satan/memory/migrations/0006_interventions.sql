-- 0006_interventions.sql
-- T7 projection of intervention audit-events into queryable tables.
--
-- These tables are a PROJECTION; the audit log (transcript.jsonl in
-- each run directory) is the source of truth.  `satan-rebuild-interventions'
-- replays the audit stream and re-populates these tables byte-identically.
--
-- Vocabulary, invariants, and verdict shape pinned by
-- docs/satan/attributes/outcome-semantics.md §9 and attributes.brief §5.
-- The audit-side validator (satan-audit-validate-intervention-event)
-- enforces the same invariants pre-write; these CHECKs enforce them
-- post-projection as a defence-in-depth guard against direct INSERTs.

-- ============================================================
-- satan_interventions
-- ============================================================
-- One row per intervention.created audit event.  Immutable once written.

CREATE TABLE satan_interventions (
  id                      TEXT PRIMARY KEY,
  run_id                  TEXT NOT NULL,
  ts                      TIMESTAMPTZ NOT NULL,
  mode                    TEXT NOT NULL,
  kind                    TEXT NOT NULL CHECK (kind IN
                            ('inbox','notify','visible_sign','proposal',
                             'patch_job','accuse','ask','delay',
                             'quarantine','surface')),
  target_surface          TEXT NOT NULL,
  message                 TEXT NOT NULL,
  related_motive_id       TEXT,
  cue_handles_json        JSONB NOT NULL DEFAULT '[]'::jsonb,
  expected_outcome        TEXT NOT NULL,
  outcome_window_minutes  INTEGER NOT NULL CHECK (outcome_window_minutes >= 0),
  severity                TEXT NOT NULL CHECK (severity IN
                            ('low','medium','high'))
);

CREATE INDEX satan_interventions_run_idx       ON satan_interventions(run_id);
CREATE INDEX satan_interventions_ts_idx        ON satan_interventions(ts);
CREATE INDEX satan_interventions_mode_kind_idx ON satan_interventions(mode, kind);

-- ============================================================
-- satan_intervention_outcomes
-- ============================================================
-- One row per intervention_id, reflecting the LATEST verdict per
-- outcome-semantics §6.3.  Updated atomically with each
-- intervention.outcome_classified / outcome_revised audit event.  The
-- audit log retains the full revision chain; this row only carries
-- the head.

CREATE TABLE satan_intervention_outcomes (
  intervention_id   TEXT PRIMARY KEY
                      REFERENCES satan_interventions(id) ON DELETE CASCADE,
  classification    TEXT NOT NULL CHECK (classification IN
                      ('worked','neutral','ignored','contradicted',
                       'harmful','unknown')),
  confidence        TEXT NOT NULL CHECK (confidence IN
                      ('low','medium','high')),
  evidence_json     JSONB NOT NULL DEFAULT '{}'::jsonb,
  maturity          TEXT NOT NULL CHECK (maturity IN
                      ('pending','mature','stale')),
  next_revisit_at   TIMESTAMPTZ NOT NULL,
  source            TEXT NOT NULL CHECK (source IN ('auto','manual')),
  classified_at     TIMESTAMPTZ NOT NULL,
  revises           TEXT,
  marked_by         TEXT,
  notes             TEXT,
  -- Invariants mirroring outcome-semantics §2 and §9.
  CONSTRAINT outcome_harmful_manual_only
    CHECK (NOT (classification = 'harmful' AND source = 'auto')),
  CONSTRAINT outcome_contradicted_manual_only_v1
    CHECK (NOT (classification = 'contradicted' AND source = 'auto')),
  CONSTRAINT outcome_pending_implies_unknown
    CHECK (NOT (maturity = 'pending' AND classification <> 'unknown'))
);

CREATE INDEX satan_intervention_outcomes_classification_idx
  ON satan_intervention_outcomes(classification);
CREATE INDEX satan_intervention_outcomes_revisit_idx
  ON satan_intervention_outcomes(next_revisit_at);
CREATE INDEX satan_intervention_outcomes_maturity_idx
  ON satan_intervention_outcomes(maturity);
