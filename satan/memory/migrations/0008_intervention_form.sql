-- 0008_intervention_form.sql
-- SL-016: the ask's answer form on the intervention record.
--
-- Adds a nullable form_json to satan_interventions: the form an `ask'
-- intervention carried on its intervention.created payload, so the goad
-- queue can be rebuilt from the projection (design sec-3).
--
-- Design: SL-016 sec-3, sec-6; DEC-024 (form-conditional INSERT).
--
-- Nullable, no default, no backfill: existing rows predate forms.
-- Forward-only.  The INSERT names form_json only for a payload that
-- carries a form, so every other kind (and a formless ask) still
-- projects on a database where this migration has not run.  Applying
-- it is a landing step that must precede enabling `satan-goad-enabled'.

ALTER TABLE satan_interventions ADD COLUMN form_json JSONB;
