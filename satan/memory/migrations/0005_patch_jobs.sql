-- 0005_patch_jobs.sql
-- Patch-agent job substrate.
-- Mirrors satan/patch-harness.md §7 and satan/patch-harness.plan.md §2.1.
--
-- Independent of 0004 grammar fixture: no foreign keys into trace state.

-- ============================================================
-- patch_jobs
-- ============================================================

CREATE TABLE patch_jobs (
  id                  TEXT PRIMARY KEY,
  state               TEXT NOT NULL CHECK (state IN
                        ('queued','claimed','preparing_worktree','running',
                         'needs_review','failed','cancelled',
                         'accepted_external','stale')),
  mode                TEXT NOT NULL,
  directive           TEXT NOT NULL,

  repo                TEXT NOT NULL,
  base_ref            TEXT NOT NULL,
  branch              TEXT NOT NULL,
  worktree_path       TEXT NOT NULL,

  adapter             TEXT NOT NULL DEFAULT 'pi',

  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  started_at          TIMESTAMPTZ,
  finished_at         TIMESTAMPTZ,

  source_json         JSONB NOT NULL DEFAULT '{}'::jsonb,
  context_json        JSONB NOT NULL DEFAULT '{}'::jsonb,
  allowed_paths_json  JSONB NOT NULL,
  checks_json         JSONB NOT NULL DEFAULT '[]'::jsonb,

  result_json         JSONB,
  error_json          JSONB
);

CREATE INDEX patch_jobs_state_idx       ON patch_jobs(state);
CREATE INDEX patch_jobs_created_idx     ON patch_jobs(created_at DESC);
CREATE INDEX patch_jobs_repo_branch_idx ON patch_jobs(repo, branch);

-- ============================================================
-- patch_job_events
-- ============================================================
-- Append-only audit log for state transitions, harness output lines,
-- check results, and warnings.  ON DELETE CASCADE so cleanup of a
-- failed/aborted job removes its events with it.

CREATE TABLE patch_job_events (
  id         BIGSERIAL PRIMARY KEY,
  job_id     TEXT NOT NULL REFERENCES patch_jobs(id) ON DELETE CASCADE,
  at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  kind       TEXT NOT NULL,        -- transition|log|warning|check|...
  payload    JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX patch_job_events_job_idx ON patch_job_events(job_id, at);

-- ============================================================
-- updated_at trigger
-- ============================================================

CREATE OR REPLACE FUNCTION patch_jobs_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER patch_jobs_updated_at
  BEFORE UPDATE ON patch_jobs
  FOR EACH ROW
  EXECUTE FUNCTION patch_jobs_set_updated_at();
