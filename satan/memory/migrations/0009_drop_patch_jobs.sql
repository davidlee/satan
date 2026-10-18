-- 0009_drop_patch_jobs.sql
-- SL-023: the patch runner (malebolge) owns patch jobs; Postgres no
-- longer holds them.
--
-- Drops patch_job_events, patch_jobs and the patch_jobs_set_updated_at()
-- trigger function created by 0005 (the trigger goes with its table).
--
-- Design: SL-023 sec-5.3 "Leaving Postgres"; DEC-063 (cutover, step 3).
--
-- Forward-only.  Refuses (RAISE) while any job is non-terminal
-- (queued, claimed, preparing_worktree, running): dropping the table
-- would lose work nothing else holds.  The terminal set is the one in
-- 0005's CHECK minus the live states.  apply-one runs this file with
-- --single-transaction and ON_ERROR_STOP=1, so a refusal leaves the
-- tables and schema_migrations untouched.

DO $$
DECLARE
  live integer;
BEGIN
  SELECT count(*) INTO live FROM patch_jobs
   WHERE state NOT IN ('needs_review','failed','cancelled',
                       'accepted_external','stale');
  IF live > 0 THEN
    RAISE EXCEPTION
      '0009: % non-terminal patch_jobs row(s) (queued/claimed/preparing_worktree/running); finish or cancel them before dropping',
      live;
  END IF;
END
$$;

DROP TABLE patch_job_events;
DROP TABLE patch_jobs;
DROP FUNCTION patch_jobs_set_updated_at();
