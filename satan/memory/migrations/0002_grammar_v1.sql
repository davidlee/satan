-- 0002_grammar_v1.sql
-- Seed grammar v1: version row, alias map (§2.3), namespace default weights (§2.4).

INSERT INTO grammar_versions (version, notes) VALUES
  (1, 'v1 initial grammar — see memory.design.md §2.2-2.4');

-- ============================================================
-- aliases (§2.3)
-- ============================================================

INSERT INTO handle_aliases (alias, canonical_handle, grammar_version) VALUES
  ('reference',     'domain_kind:docs',     1),
  ('manual',        'domain_kind:docs',     1),
  ('documentation', 'domain_kind:docs',     1),
  ('tutorial',      'domain_kind:learning', 1),
  ('guide',         'domain_kind:learning', 1),
  ('howto',         'domain_kind:learning', 1);

-- ============================================================
-- namespace default weights (§2.4)
-- ============================================================

INSERT INTO handle_weights (namespace, value, weight, grammar_version) VALUES
  ('project',            '__default__', 1, 1),
  ('surface',            '__default__', 1, 1),
  ('app',                '__default__', 1, 1),
  ('mode',               '__default__', 1, 1),
  ('domain_kind',        '__default__', 2, 1),
  ('file_kind',          '__default__', 1, 1),
  ('event',              '__default__', 2, 1),
  ('surface_transition', '__default__', 3, 1),
  ('event_transition',   '__default__', 3, 1),
  ('domain_transition',  '__default__', 2, 1),
  ('artifact',           '__default__', 3, 1),
  ('phase',              '__default__', 2, 1),
  ('intervention',       '__default__', 2, 1),
  ('outcome',            '__default__', 3, 1),
  ('topic',              '__default__', 1, 1),
  ('bough_kind',         '__default__', 1, 1),
  ('bough_status',       '__default__', 2, 1),
  ('bough_event',        '__default__', 2, 1),
  ('bough_project',      '__default__', 1, 1),
  ('bough_node',         '__default__', 0, 1),
  ('workspace',          '__default__', 1, 1),
  ('queue',              '__default__', 1, 1),
  ('day',                '__default__', 1, 1),
  ('week',               '__default__', 1, 1);
