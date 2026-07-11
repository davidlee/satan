-- 0001_init.sql
-- Initial schema for SATAN memory substrate.
-- Mirrors memory.design.md §6.2.

-- ============================================================
-- bookkeeping
-- ============================================================

CREATE TABLE schema_migrations (
  version      INTEGER PRIMARY KEY,
  filename     TEXT NOT NULL,
  applied_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  checksum     TEXT NOT NULL
);

CREATE TABLE grammar_versions (
  version          SMALLINT PRIMARY KEY,
  introduced_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  notes            TEXT
);

-- ============================================================
-- traces
-- ============================================================

CREATE TABLE traces (
  id                      TEXT PRIMARY KEY,
  kind                    TEXT NOT NULL CHECK (kind IN
                            ('observation','intervention','prediction','outcome')),
  trace_origin            TEXT NOT NULL CHECK (trace_origin IN
                            ('llm_mark','auto_rule','external')),
  source                  TEXT NOT NULL,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  observed_start_at       TIMESTAMPTZ NOT NULL,
  observed_end_at         TIMESTAMPTZ NOT NULL,

  payload                 TEXT NOT NULL,
  valence                 TEXT CHECK (valence IN
                            ('positive','negative','neutral','mixed','unknown')),
  outcome                 TEXT,

  strength                DOUBLE PRECISION NOT NULL DEFAULT 1.0
                            CHECK (strength >= 0),
  base_strength           DOUBLE PRECISION NOT NULL DEFAULT 1.0
                            CHECK (base_strength >= 0),
  last_accessed_at        TIMESTAMPTZ,
  last_reinforced_at      TIMESTAMPTZ,
  access_count            INTEGER NOT NULL DEFAULT 0
                            CHECK (access_count >= 0),
  reinforcement_count     INTEGER NOT NULL DEFAULT 0
                            CHECK (reinforcement_count >= 0),

  schema_version          SMALLINT NOT NULL,
  grammar_version         SMALLINT NOT NULL REFERENCES grammar_versions(version),

  metadata_json           JSONB NOT NULL,
  retention_json          JSONB NOT NULL DEFAULT '{"policy":"normal"}'::jsonb,

  CHECK (observed_start_at <= observed_end_at),
  CHECK (retention_json->>'policy' IN ('normal','ephemeral','pinned','audit'))
);

CREATE INDEX traces_kind_idx           ON traces(kind);
CREATE INDEX traces_origin_idx         ON traces(trace_origin);
CREATE INDEX traces_observed_end_idx   ON traces(observed_end_at DESC);
CREATE INDEX traces_strength_idx       ON traces(strength DESC);

-- ============================================================
-- handles (versioned for re-normalization)
-- ============================================================

CREATE TABLE trace_handles (
  trace_id          TEXT NOT NULL REFERENCES traces(id) ON DELETE CASCADE,
  grammar_version   SMALLINT NOT NULL REFERENCES grammar_versions(version),
  handle            TEXT NOT NULL
                    CHECK (handle ~ '^[a-z][a-z0-9_]*:[A-Za-z0-9][A-Za-z0-9_.+>-]*$'),
  source            JSONB NOT NULL,
  active            BOOLEAN NOT NULL DEFAULT TRUE,
  PRIMARY KEY (trace_id, grammar_version, handle)
);

CREATE INDEX trace_handles_handle_active_idx
  ON trace_handles(handle)
  WHERE active;

CREATE INDEX trace_handles_trace_active_idx
  ON trace_handles(trace_id, grammar_version)
  WHERE active;

-- ============================================================
-- links
-- ============================================================

CREATE TABLE trace_links (
  trace_id        TEXT NOT NULL REFERENCES traces(id) ON DELETE CASCADE,
  relation        TEXT NOT NULL CHECK (relation IN
                    ('derived_from','supports','contradicts','supersedes')),
  target_trace_id TEXT NOT NULL REFERENCES traces(id) ON DELETE CASCADE,
  PRIMARY KEY (trace_id, relation, target_trace_id)
);

CREATE INDEX trace_links_target_idx    ON trace_links(target_trace_id);

-- ============================================================
-- grammar tables (versioned)
-- ============================================================

CREATE TABLE handle_aliases (
  alias             TEXT NOT NULL,
  canonical_handle  TEXT NOT NULL
                    CHECK (canonical_handle ~ '^[a-z][a-z0-9_]*:[A-Za-z0-9][A-Za-z0-9_.+>-]*$'),
  grammar_version   SMALLINT NOT NULL REFERENCES grammar_versions(version),
  PRIMARY KEY (alias, grammar_version)
);

CREATE TABLE handle_weights (
  namespace         TEXT NOT NULL,
  value             TEXT NOT NULL DEFAULT '__default__',
  weight            DOUBLE PRECISION NOT NULL,
  grammar_version   SMALLINT NOT NULL REFERENCES grammar_versions(version),
  PRIMARY KEY (namespace, value, grammar_version)
);
