-- 0003_memory_functions.sql
-- PL/pgSQL + SQL functions backing satan-memory-store.el (step 7).
-- §5.1 memory_mark · §5.2 memory_resonate · §5.3 memory_show.
--
-- Multi-step transactions live in SQL per memory.design.md §6.1 so the
-- elisp side stays a one-liner per call.

-- ============================================================
-- handle_weight_for: per-value override or namespace default, per
-- grammar_version.  Falls back to 1.0 if nothing matches.
-- ============================================================

CREATE OR REPLACE FUNCTION handle_weight_for(
  p_handle          TEXT,
  p_grammar_version SMALLINT
) RETURNS DOUBLE PRECISION
LANGUAGE sql STABLE AS $$
  SELECT COALESCE(
    (SELECT hw.weight
       FROM handle_weights hw
      WHERE hw.namespace = split_part(p_handle, ':', 1)
        AND hw.value = substring(p_handle from position(':' in p_handle) + 1)
        AND hw.grammar_version = p_grammar_version),
    (SELECT hw.weight
       FROM handle_weights hw
      WHERE hw.namespace = split_part(p_handle, ':', 1)
        AND hw.value = '__default__'
        AND hw.grammar_version = p_grammar_version),
    1.0
  );
$$;

-- ============================================================
-- memory_mark_trace: insert one trace, its handles, and its links
-- in one statement (called inside an outer transaction by the caller).
-- Returns the trace_id from the payload.  Enforces the outcome
-- invariant (§9.12).
-- ============================================================

CREATE OR REPLACE FUNCTION memory_mark_trace(p_payload JSONB)
RETURNS TEXT
LANGUAGE plpgsql AS $$
DECLARE
  v_trace_id        TEXT;
  v_outcome         TEXT;
  v_grammar_version SMALLINT;
BEGIN
  v_trace_id        := p_payload->>'trace_id';
  v_outcome         := p_payload->>'outcome';
  v_grammar_version := (p_payload->>'grammar_version')::smallint;

  INSERT INTO traces (
    id, kind, trace_origin, source,
    observed_start_at, observed_end_at,
    payload, valence, outcome,
    schema_version, grammar_version,
    metadata_json, retention_json
  ) VALUES (
    v_trace_id,
    p_payload->>'kind',
    p_payload->>'trace_origin',
    p_payload->>'source',
    (p_payload->>'observed_start_at')::timestamptz,
    (p_payload->>'observed_end_at')::timestamptz,
    p_payload->>'payload',
    p_payload->>'valence',
    v_outcome,
    COALESCE((p_payload->>'schema_version')::smallint, 1::smallint),
    v_grammar_version,
    COALESCE(p_payload->'metadata_json', '{}'::jsonb),
    COALESCE(p_payload->'retention_json', '{"policy":"normal"}'::jsonb)
  );

  INSERT INTO trace_handles (trace_id, grammar_version, handle, source, active)
  SELECT
    v_trace_id,
    COALESCE((h->>'grammar_version')::smallint, v_grammar_version),
    h->>'handle',
    h->'source',
    TRUE
  FROM jsonb_array_elements(COALESCE(p_payload->'handles', '[]'::jsonb)) AS h;

  INSERT INTO trace_links (trace_id, relation, target_trace_id)
  SELECT
    v_trace_id,
    l->>'relation',
    l->>'target_trace_id'
  FROM jsonb_array_elements(COALESCE(p_payload->'links', '[]'::jsonb)) AS l;

  -- §9.12 outcome invariant
  IF v_outcome IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM trace_handles
      WHERE trace_id = v_trace_id
        AND handle = 'outcome:' || v_outcome
        AND grammar_version = v_grammar_version
        AND active
    ) THEN
      RAISE EXCEPTION
        'memory_mark_trace: outcome=% requires matching outcome:<value> handle',
        v_outcome;
    END IF;
  END IF;

  RETURN v_trace_id;
END;
$$;

-- ============================================================
-- memory_resonate: inverted-index lookup + scoring per §6.4.
-- v1 has no recency decay; score = sum(weight * 1.0) * trace.strength.
-- ============================================================

CREATE OR REPLACE FUNCTION memory_resonate(
  p_cue_handles      TEXT[],
  p_grammar_version  SMALLINT,
  p_min_score        DOUBLE PRECISION DEFAULT 0.0,
  p_max_results      INTEGER          DEFAULT 25,
  p_kinds            TEXT[]           DEFAULT NULL
) RETURNS TABLE(
  trace_id         TEXT,
  score            DOUBLE PRECISION,
  matched_handles  TEXT[]
)
LANGUAGE sql STABLE AS $$
  WITH matches AS (
    SELECT
      th.trace_id,
      th.handle,
      handle_weight_for(th.handle, th.grammar_version) AS w
    FROM trace_handles th
    WHERE th.active
      AND th.handle = ANY(p_cue_handles)
      AND th.grammar_version = p_grammar_version
  ),
  scored AS (
    SELECT
      m.trace_id,
      SUM(m.w) * t.strength AS score,
      ARRAY_AGG(m.handle ORDER BY m.handle) AS matched_handles
    FROM matches m
    JOIN traces t ON t.id = m.trace_id
    WHERE p_kinds IS NULL OR t.kind = ANY(p_kinds)
    GROUP BY m.trace_id, t.strength
  )
  SELECT s.trace_id, s.score, s.matched_handles
  FROM scored s
  WHERE s.score >= p_min_score
  ORDER BY s.score DESC, s.trace_id DESC
  LIMIT p_max_results;
$$;

-- ============================================================
-- memory_show_trace: round-trip a trace with handles + links.
-- Returns NULL JSONB if the trace_id does not exist.
-- ============================================================

CREATE OR REPLACE FUNCTION memory_show_trace(p_trace_id TEXT)
RETURNS JSONB
LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'trace', to_jsonb(t.*),
    'handles', COALESCE(
      (SELECT jsonb_agg(
                jsonb_build_object(
                  'handle', th.handle,
                  'source', th.source,
                  'grammar_version', th.grammar_version
                )
                ORDER BY th.handle)
       FROM trace_handles th
       WHERE th.trace_id = t.id AND th.active),
      '[]'::jsonb),
    'links', COALESCE(
      (SELECT jsonb_agg(
                jsonb_build_object(
                  'relation', l.relation,
                  'target_trace_id', l.target_trace_id))
       FROM trace_links l
       WHERE l.trace_id = t.id),
      '[]'::jsonb)
  )
  FROM traces t
  WHERE t.id = p_trace_id;
$$;
