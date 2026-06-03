-- =====================================================================
--  PATCH 039 — Job lifecycle + tier
--
--  WHY: Jobs currently live forever. We want a 30-day shelf life
--       (matches the founder's call + most regional job-board
--       conventions) with a 5-days-before-expiry reminder push and
--       a one-tap "Renew" that bumps the expiry forward another 30
--       days. Also adds a `level` column so the JobsScreen can
--       filter by entry / mid / senior — same job category may
--       attract very different audiences depending on tier.
--
--  WHAT:
--   1. jobs.expires_at TIMESTAMPTZ — default `created_at + 30 days`
--      via a column default expression. Existing rows are
--      back-filled to `created_at + 30 days` (a hard sweep) so they
--      enter the new lifecycle window immediately.
--   2. jobs.level TEXT NOT NULL DEFAULT 'mid' CHECK (in entry, mid,
--      senior). Existing rows default to 'mid' so the post-launch
--      filter still surfaces them.
--   3. RPC renew_job(p_job_id BIGINT) — owner-only, bumps expires_at
--      to NOW() + 30 days regardless of current state. Useful both
--      for jobs about to expire and ones that already lapsed.
--   4. pg_cron job `0 9 * * *` runs daily at 09:00 Africa/Harare and
--      inserts notifications for every job that's exactly 5 days
--      from expiry (a notification per job, idempotent via the
--      reminder-key column to avoid re-firing the same day).
--   5. jobs_expiry_reminded_at TIMESTAMPTZ NULL — set by the cron
--      job after the reminder lands so re-runs in the same window
--      don't double-notify.
--
--  IDEMPOTENT: yes — IF NOT EXISTS + CREATE OR REPLACE throughout.
-- =====================================================================


-- ----- 1. Columns ---------------------------------------------------
ALTER TABLE public.jobs
  ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;
ALTER TABLE public.jobs
  ADD COLUMN IF NOT EXISTS level TEXT NOT NULL DEFAULT 'mid';
ALTER TABLE public.jobs
  ADD COLUMN IF NOT EXISTS expiry_reminded_at TIMESTAMPTZ;

-- Backfill expiry on rows that pre-date this patch — treat them as
-- "30 days from posting" so they enter the same window as any
-- newly-posted job. Rows already in the future are left alone.
UPDATE public.jobs
   SET expires_at = created_at + INTERVAL '30 days'
 WHERE expires_at IS NULL;

-- After backfill, lock the column NOT NULL and switch the default to
-- the live "now + 30 days" expression for new inserts.
ALTER TABLE public.jobs
  ALTER COLUMN expires_at SET NOT NULL;
ALTER TABLE public.jobs
  ALTER COLUMN expires_at SET DEFAULT (NOW() + INTERVAL '30 days');

-- Level CHECK.
ALTER TABLE public.jobs
  DROP CONSTRAINT IF EXISTS jobs_level_check;
ALTER TABLE public.jobs
  ADD CONSTRAINT jobs_level_check CHECK (level IN ('entry','mid','senior'));


-- ----- 2. renew_job RPC ---------------------------------------------
CREATE OR REPLACE FUNCTION public.renew_job(p_job_id BIGINT)
RETURNS public.jobs AS $$
DECLARE
  v_caller UUID := auth.uid();
  v_row public.jobs;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Sign in to renew a job.';
  END IF;

  UPDATE public.jobs
     SET expires_at          = NOW() + INTERVAL '30 days',
         expiry_reminded_at  = NULL,
         status              = CASE
                                 WHEN status = 'expired' THEN 'active'
                                 ELSE status
                               END
   WHERE id = p_job_id
     AND poster_id = v_caller
  RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'Job % not found or not yours.', p_job_id;
  END IF;

  RETURN v_row;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

REVOKE ALL ON FUNCTION public.renew_job(BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.renew_job(BIGINT) TO authenticated;


-- ----- 3. Daily expiry-reminder cron --------------------------------
-- Fires at 09:00 Africa/Harare every day. Picks every job whose
-- expires_at lands in the next ~24h window of (now + 4d, now + 5d]
-- (i.e. "5 days left, rounded to days"). Inserts a notification per
-- job, then stamps expiry_reminded_at so re-running the cron in the
-- same window doesn't double-notify.
CREATE OR REPLACE FUNCTION public.enqueue_job_expiry_reminders()
RETURNS INTEGER AS $$
DECLARE
  v_count INTEGER := 0;
  v_row RECORD;
BEGIN
  FOR v_row IN
    SELECT j.id, j.poster_id, j.title
      FROM public.jobs j
     WHERE j.expires_at > NOW() + INTERVAL '4 days'
       AND j.expires_at <= NOW() + INTERVAL '5 days'
       AND COALESCE(j.is_active, TRUE) = TRUE
       AND COALESCE(j.status, 'active') NOT IN ('expired','filled','closed')
       AND j.expiry_reminded_at IS NULL
  LOOP
    INSERT INTO public.notifications (
      user_id, title, body, type, reference_id, reference_type
    ) VALUES (
      v_row.poster_id,
      'Job expires in 5 days',
      '"' || v_row.title || '" will be removed from the marketplace in 5 days. Renew it from your job listing to keep it visible.',
      'job_expiry_reminder',
      v_row.id::text,
      'job'
    );

    UPDATE public.jobs
       SET expiry_reminded_at = NOW()
     WHERE id = v_row.id;

    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

REVOKE ALL ON FUNCTION public.enqueue_job_expiry_reminders() FROM PUBLIC;
-- No GRANT to authenticated — only the cron / service role should call.

-- Register the cron entry (09:00 Africa/Harare = 07:00 UTC).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'jobs_expiry_reminder_5d') THEN
    PERFORM cron.unschedule('jobs_expiry_reminder_5d');
  END IF;
  PERFORM cron.schedule(
    'jobs_expiry_reminder_5d',
    '0 7 * * *',
    'SELECT public.enqueue_job_expiry_reminders();'
  );
END;
$$;
