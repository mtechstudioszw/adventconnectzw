-- =====================================================================
--  PATCH 292 — free database space and keep it free
--  STATUS: APPLIED 2 Nov 2026 (by the owner, verified by Claude)
--
--  Owner, 1 Nov 2026: the Free plan's 500 MB database is at ~392 MB and
--  there is no budget to upgrade. "Only the useful things will take up
--  the storage."
--
--  Measured on the live database before writing this:
--
--    youtube_videos   172 MB   search_tsv alone 61 MB: every word of
--                              every description, 71,735 videos, and NO
--                              index on it (search scanned all rows).
--    notifications     56 MB   78,634 rows; 35,767 daily-devotion,
--                              18,689 YouTube-live, 10,508 Sabbath,
--                              3,946 maintenance, 3,362 admin broadcast,
--                              2,428 quiz nudges — one row PER MEMBER per
--                              broadcast, kept up to 90 days.
--    e2ee_prekeys      32 MB   188,211 spare keys; 117,597 beyond 100 per
--                              device (an app bug uploaded a new batch
--                              whenever the "how many left" check failed;
--                              fixed in e2ee_service.dart, same commit).
--    supabase_functions.hooks  25 MB  webhook call log, 50,073 rows in 5
--                              days; nothing reads it.
--    auth.refresh_tokens 17 MB 49,136 of 49,925 are revoked.
--
--  What this does, nothing a member would miss:
--    1. Video search keeps title + channel + the FIRST 300 characters of
--       the description (where the topic and speaker are), and gets the
--       GIN index patch_154 meant to have (idx_yt_videos_fts was missing).
--       Smaller AND faster — youtube_search timed out on the Nano DB.
--    2. Mass broadcast notifications are kept 7 days (personal ones —
--       messages, likes, friends, prayers — keep the existing 45/90 days).
--    3. Each phone keeps its newest 100 unused encryption prekeys (the
--       app's own batch size); used ones go after 30 days.
--    4. Webhook log kept 2 days (was 7). Revoked login tokens kept 7 days.
--    5. Usage analytics (app_events, app_sessions) kept 120 days.
--    6. All of it runs NOW once, then nightly inside the existing jobs
--       (cleanup-expired-content 03:10, prune-operational-logs 03:50).
--
--  Space: deleting frees room INSIDE the tables for new rows at once. To
--  see the dashboard number drop, run the VACUUM FULL lines at the bottom
--  afterwards, ONE AT A TIME (each takes a few seconds and briefly locks
--  that one table). youtube_videos needs none — step 1 rewrites it.
--
--  CLAUDE.md checklist: no profiles change; no new triggers.
-- =====================================================================

BEGIN;

-- 1. Video search: smaller column + the index it never had ------------
ALTER TABLE public.youtube_videos
  ALTER COLUMN search_tsv SET EXPRESSION AS (
    setweight(to_tsvector('english'::regconfig, COALESCE(title, '')), 'A')
    || setweight(to_tsvector('english'::regconfig,
                             left(COALESCE(description, ''), 300)), 'B')
    || setweight(to_tsvector('english'::regconfig,
                             COALESCE(channel_title, '')), 'C')
  );

CREATE INDEX IF NOT EXISTS idx_yt_videos_fts
  ON public.youtube_videos USING gin (search_tsv);

-- 2-5. Nightly rules, folded into the jobs that already run ------------

-- Broadcast notifications: one row per member per event. A week is
-- plenty for an inbox; the push already reached the phone.
CREATE OR REPLACE FUNCTION public.cleanup_expired_content()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- 1. Expired stories (24h) — actually delete the rows.
  DELETE FROM public.stories WHERE expires_at < now();

  -- 2. Notifications: drop read ones after 45 days and ANY after 90 days
  --    so the table stays small (it's append-only churn).
  DELETE FROM public.notifications
   WHERE (is_read = TRUE AND created_at < now() - INTERVAL '45 days')
      OR created_at < now() - INTERVAL '90 days';

  -- 2b. (patch 292) Mass broadcasts — one row per member each — after 7
  --     days. These were half the table.
  DELETE FROM public.notifications
   WHERE type IN ('devotion', 'youtube_live', 'sabbath_approaching',
                  'sabbath_begins', 'maintenance', 'quiz_nudge',
                  'admin_broadcast', 'birthday', 'profile_incomplete',
                  'ai_service')
     AND created_at < now() - INTERVAL '7 days';

  -- 3. Resolved/dismissed reports older than 60 days.
  DELETE FROM public.reports
   WHERE status IN ('actioned', 'dismissed')
     AND created_at < now() - INTERVAL '60 days';
END;
$function$;

CREATE OR REPLACE FUNCTION public.prune_operational_logs()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'net', 'cron'
AS $function$
BEGIN
  DELETE FROM net._http_response WHERE created < now() - interval '1 day';

  -- VACUUM FULL removed: Postgres forbids VACUUM inside a function, which made
  -- this whole job fail and roll back. The weekly cron job 'vacuum-operational-logs'
  -- already compacts net._http_response.

  DELETE FROM cron.job_run_details WHERE end_time < now() - interval '2 days';

  DELETE FROM public.rate_limits WHERE hit_at < now() - interval '2 days';

  DELETE FROM public.call_events WHERE created_at < now() - interval '30 days';

  -- Webhook invocation log; nothing reads it. (patch 292: 7 → 2 days;
  -- ~10,000 rows a day.)
  DELETE FROM supabase_functions.hooks WHERE created_at < now() - interval '2 days';

  -- patch 292: spare encryption prekeys. Each device keeps its newest 100
  -- unused ones (the app's batch size); used ones go after 30 days.
  DELETE FROM public.e2ee_prekeys k
   USING (
     SELECT user_id, device_id, key_id,
            row_number() OVER (PARTITION BY user_id, device_id
                               ORDER BY created_at DESC, key_id DESC) AS rn
       FROM public.e2ee_prekeys
      WHERE claimed_at IS NULL
   ) x
   WHERE x.rn > 100
     AND k.user_id = x.user_id AND k.device_id = x.device_id
     AND k.key_id = x.key_id AND k.claimed_at IS NULL;
  DELETE FROM public.e2ee_prekeys
   WHERE claimed_at IS NOT NULL AND claimed_at < now() - interval '30 days';

  -- patch 292: usage analytics older than 120 days.
  DELETE FROM public.app_events   WHERE created_at < now() - interval '120 days';
  DELETE FROM public.app_sessions WHERE started_at < now() - interval '120 days';

  -- patch 292: revoked login tokens can never be used again. Guarded:
  -- if this role may not touch the auth schema, skip it rather than fail
  -- the whole nightly job.
  BEGIN
    DELETE FROM auth.refresh_tokens
     WHERE revoked AND updated_at < now() - interval '7 days';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'refresh_tokens prune skipped: no privilege';
  END;
END;
$function$;

-- 6. Run both once now ---------------------------------------------------
SELECT public.cleanup_expired_content();
SELECT public.prune_operational_logs();

ANALYZE public.youtube_videos;
ANALYZE public.notifications;
ANALYZE public.e2ee_prekeys;

COMMIT;

-- ---------------------------------------------------------------------
--  AFTERWARDS, to give the space back (run each line ON ITS OWN):
-- ---------------------------------------------------------------------
-- VACUUM FULL public.notifications;
-- VACUUM FULL public.e2ee_prekeys;
-- VACUUM FULL public.app_events;
--
--  Check (read-only):
-- SELECT pg_size_pretty(pg_database_size(current_database())) AS db,
--        pg_size_pretty(pg_total_relation_size('public.youtube_videos')) AS videos,
--        pg_size_pretty(pg_total_relation_size('public.notifications')) AS notifications,
--        pg_size_pretty(pg_total_relation_size('public.e2ee_prekeys')) AS prekeys;
