-- 0004_grammar_v2_fixture.sql
-- Smallest possible grammar bump exercising the renormalize CLI.
-- v1 phase aliases are absent, so a hint of `phase:"planning"' is
-- rejected; v2 adds `planning -> phase:orientation' so the same hint
-- now produces a `phase:orientation' handle.  Tests cl-letf the elisp
-- grammar constants and run `dl-satan-memory-renormalize' against the
-- new version to flip old `trace_handles' rows to inactive and insert
-- the v2 set.
--
-- Weights and existing aliases are copied forward unchanged; only the
-- one new alias differs from v1.

INSERT INTO grammar_versions (version, notes) VALUES
  (2, 'fixture bump for renormalize golden test --- planning phase alias');

INSERT INTO handle_weights (namespace, value, weight, grammar_version)
  SELECT namespace, value, weight, 2
    FROM handle_weights
   WHERE grammar_version = 1;

INSERT INTO handle_aliases (alias, canonical_handle, grammar_version)
  SELECT alias, canonical_handle, 2
    FROM handle_aliases
   WHERE grammar_version = 1;

INSERT INTO handle_aliases (alias, canonical_handle, grammar_version) VALUES
  ('planning', 'phase:orientation', 2);
