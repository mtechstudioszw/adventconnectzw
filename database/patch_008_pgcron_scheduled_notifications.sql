-- =====================================================================
--  PATCH 008 — pg_cron scheduled notifications
--
--  WHY:  Two Part 23 triggers are time-based, not event-based:
--          - Event reminder 24h before start → RSVPd members
--          - Job post expiring in 3 days     → poster
--        Both need a recurring job, not an INSERT/UPDATE trigger. We
--        run them inside Postgres with pg_cron so there's no external
--        worker to babysit — Supabase already operates pg_cron.
--
--  WHAT THIS PATCH DOES:
--    1. CREATE EXTENSION pg_cron (enable once; harmless if already on).
--    2. Defines public.enqueue_event_reminders():
--         For every approved event starting in (NOW()+23h, NOW()+24h]
--         (Africa/Harare wall-clock), insert one notification per
--         'going' RSVP. NOT EXISTS dedupe keeps re-runs safe.
--    3. Defines public.enqueue_job_expiry_warnings():
--         For every open job whose expires_at falls in
--         (NOW()+3d, NOW()+3d+1d], notify the poster once. Dedupe
--         via NOT EXISTS.
--    4. Registers two cron entries:
--         enqueue_event_reminders   — runs every 30 minutes
--         enqueue_job_expiry_warns  — runs daily at 09:00 UTC (11:00 CAT)
--       Old entries with the same jobname are unscheduled first so
--       re-running this patch doesn't pile up duplicate schedules.
--
--  PUSH PIPELINE: each notifications INSERT triggers the existing
--                 Database Webhook → notify-fcm Edge Function, same as
--                 patch_002 / patch_006. Nothing else to wire.
--
--  TIMEZONE NOTE: events.start_date is DATE, events.start_time is TEXT
--                 'HH:mm' (V4 spec). We assemble a Africa/Harare local
--                 timestamp and AT TIME ZONE 'Africa/Harare' → UTC for
--                 the NOW() comparison. start_time NULL is treated as
--                 09:00 local so untimed events still get a reminder.
--
--  PREREQUISITES: schema.sql + patch_001..patch_007 already applied.
--                 The pg_cron extension must be available — on Supabase,
--                 enable it via Dashboard → Database → Extensions if it
--                 doesn't auto-create from CREATE EXTENSION below.
--  IDEMPOTENT:    yes — extension is IF NOT EXISTS, functions are
--                 CREATE OR REPLACE, schedule entries are unscheduled
--                 before being re-scheduled.
-- =====================================================================


-- ----- 1. Enable pg_cron --------------------------------------------
-- Supabase ships pg_cron as an available extension; this is a no-op if
-- it's already enabled in the dashboard.
CREATE EXTENSION IF NOT EXISTS pg_cron;


-- =====================================================================
--  2) Event reminder enqueuer — runs every 30 minutes
--
--  Window: events starting within the next 23–24 hours (Africa/Harare
--  local time). A 30-minute cron + 1-hour window means each event
--  triggers in two consecutive runs; the NOT EXISTS dedupe drops the
--  second one so the user only gets one notification.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.enqueue_event_reminders()
RETURNS INTEGER AS $$
DECLARE
  inserted_count INTEGER;
BEGIN
  WITH due AS (
    SELECT
      e.id,
      e.title,
      ((e.start_date + COALESCE(NULLIF(e.start_time, '')::time, '09:00'::time))
        AT TIME ZONE 'Africa/Harare') AS start_at_utc
    FROM public.events e
    WHERE e.status = 'approved'
  ),
  pending AS (
    SELECT
      d.id,
      d.title,
      r.user_id
    FROM due d
    JOIN public.event_rsvps r
      ON r.event_id = d.id AND r.status = 'going'
    WHERE d.start_at_utc > NOW() + INTERVAL '23 hours'
      AND d.start_at_utc <= NOW() + INTERVAL '24 hours'
      AND NOT EXISTS (
        SELECT 1
        FROM public.notifications n
        WHERE n.user_id = r.user_id
          AND n.type = 'event_reminder'
          AND n.reference_id = d.id::text
      )
  )
  INSERT INTO public.notifications (
    user_id, title, body, type, reference_id, reference_type
  )
  SELECT
    p.user_id,
    'Event tomorrow',
    '"' || COALESCE(p.title, 'An event you RSVPd to') ||
      '" starts in about 24 hours.',
    'event_reminder',
    p.id::text,
    'event'
  FROM pending p;

  GET DIAGNOSTICS inserted_count = ROW_COUNT;
  RETURN inserted_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;


-- =====================================================================
--  3) Job expiry warning enqueuer — runs once per day
--
--  Window: open jobs whose expires_at lands within the next 3 to 4
--  days. A daily cron + 1-day window means each job triggers exactly
--  once (the NOT EXISTS dedupe is belt-and-braces in case the cron
--  fires twice or the patch is re-applied on the same day).
-- =====================================================================
CREATE OR REPLACE FUNCTION public.enqueue_job_expiry_warnings()
RETURNS INTEGER AS $$
DECLARE
  inserted_count INTEGER;
BEGIN
  WITH pending AS (
    SELECT j.id, j.title, j.poster_id, j.expires_at
    FROM public.jobs j
    WHERE j.status = 'open'
      AND j.expires_at > NOW() + INTERVAL '3 days'
      AND j.expires_at <= NOW() + INTERVAL '4 days'
      AND j.poster_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1
        FROM public.notifications n
        WHERE n.user_id = j.poster_id
          AND n.type = 'job_expiring'
          AND n.reference_id = j.id::text
      )
  )
  INSERT INTO public.notifications (
    user_id, title, body, type, reference_id, reference_type
  )
  SELECT
    p.poster_id,
    'Job post expiring soon',
    '"' || COALESCE(p.title, 'Your job post') ||
      '" expires in 3 days. Mark it as filled or repost to refresh.',
    'job_expiring',
    p.id::text,
    'job'
  FROM pending p;

  GET DIAGNOSTICS inserted_count = ROW_COUNT;
  RETURN inserted_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;


-- =====================================================================
--  4) Schedule the two jobs
--
--  Unschedule any old entry with the same jobname first so re-running
--  this patch doesn't accumulate duplicate schedules. Using SELECT
--  inside DO blocks is fine — cron.* returns void/bigint we ignore.
-- =====================================================================

-- 4a) Event reminders — every 30 minutes
DO $$
BEGIN
  PERFORM cron.unschedule(jobid)
    FROM cron.job
    WHERE jobname = 'enqueue_event_reminders';
END $$;

SELECT cron.schedule(
  'enqueue_event_reminders',
  '*/30 * * * *',
  $$SELECT public.enqueue_event_reminders();$$
);


-- 4b) Job expiry warnings — daily at 09:00 UTC (11:00 Africa/Harare)
DO $$
BEGIN
  PERFORM cron.unschedule(jobid)
    FROM cron.job
    WHERE jobname = 'enqueue_job_expiry_warnings';
END $$;

SELECT cron.schedule(
  'enqueue_job_expiry_warnings',
  '0 9 * * *',
  $$SELECT public.enqueue_job_expiry_warnings();$$
);


-- =====================================================================
--  END OF PATCH 008
--
--  To inspect or tear down:
--    SELECT * FROM cron.job;
--    SELECT * FROM cron.job_run_details
--      ORDER BY start_time DESC LIMIT 20;
--    -- Disable a job:
--    SELECT cron.unschedule('enqueue_event_reminders');
-- =====================================================================
