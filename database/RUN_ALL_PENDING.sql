-- RUN_ALL_PENDING.sql — what is left (1 Nov 2026). Claude already applied 296, 294, 293, 298, 300, 301.
-- These three delete old data, so run them yourself: Supabase → SQL Editor → paste → Run.
-- Then run each VACUUM FULL line from the bottom of patch_292 on its own.
-- patch_295 (encryption on for everyone) is separate: only after the two-phone test.

-- >>>>>>>>>>>>>>>> database/patch_297_home_church_only.sql
-- =====================================================================
--  PATCH 297 — one church per member: the home church
--  STATUS: not yet applied
--
--  Owner, 1 Nov 2026: "Remove the Follow button on churches. Members only
--  belong to their home church… To follow another church, it must create
--  a Page." The app no longer offers following (same release). This
--  brings the server in line, so admins see and reach their real members:
--
--   1. church_member_list / church_member_count / church_admin_stats
--      counted church_FOLLOWERS. Now: members whose profiles.church_id is
--      this church (328 members have one set today).
--   2. fanout_announcement sent to followers UNION members. Now: members
--      only — a church's announcements reach its own congregation.
--   3. The 9 follows of a church that is NOT the member's home church are
--      removed (checked live: 334 follows, 325 of them the home church).
--      Following one's own home church is harmless and kept.
--
--  CLAUDE.md checklist: no profiles change; no triggers. Signatures and
--  security settings are restated exactly as they are live.
-- =====================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.church_member_list(p_church_id bigint)
RETURNS TABLE(user_id uuid, full_name text, profile_photo_url text,
              joined_at timestamp with time zone)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT p.id, p.full_name, p.profile_photo_url, p.created_at
    FROM public.profiles p
   WHERE p.church_id = p_church_id
     AND COALESCE(p.is_banned, FALSE) = FALSE
     AND (
       public.is_super_admin()
       OR EXISTS (
         SELECT 1 FROM public.church_admins ca
          WHERE ca.church_id = p_church_id
            AND ca.user_id = auth.uid()
            AND ca.status = 'approved'
       )
     )
   ORDER BY p.full_name ASC NULLS LAST;
$function$;

CREATE OR REPLACE FUNCTION public.church_member_count(p_church_id bigint)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT CASE
    WHEN public.is_super_admin()
      OR EXISTS (
        SELECT 1 FROM public.church_admins ca
         WHERE ca.church_id = p_church_id
           AND ca.user_id = auth.uid()
           AND ca.status = 'approved'
      )
    THEN (SELECT count(*)::int FROM public.profiles p
           WHERE p.church_id = p_church_id
             AND COALESCE(p.is_banned, FALSE) = FALSE)
    ELSE 0
  END;
$function$;

CREATE OR REPLACE FUNCTION public.church_admin_stats(p_church_id bigint)
RETURNS TABLE(members integer, announcements integer, events integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT
    (SELECT count(*)::int FROM public.profiles p
      WHERE p.church_id = p_church_id
        AND COALESCE(p.is_banned, FALSE) = FALSE),
    (SELECT count(*)::int FROM public.announcements a WHERE a.church_id = p_church_id),
    (SELECT count(*)::int FROM public.events e WHERE e.church_id = p_church_id)
  WHERE (
    public.is_super_admin()
    OR EXISTS (
      SELECT 1 FROM public.church_admins ca
       WHERE ca.church_id = p_church_id
         AND ca.user_id = auth.uid()
         AND ca.status = 'approved'
    )
  );
$function$;

CREATE OR REPLACE FUNCTION public.fanout_announcement(p_id bigint)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  a            public.announcements%ROWTYPE;
  cname        TEXT;
  is_obituary  BOOLEAN;
  is_urgent    BOOLEAN;
  v_count      INTEGER := 0;
BEGIN
  SELECT * INTO a FROM public.announcements WHERE id = p_id;
  IF a.id IS NULL THEN RETURN 0; END IF;
  IF a.notified_at IS NOT NULL THEN RETURN 0; END IF;

  is_obituary := (a.category = 'obituary');
  is_urgent   := (a.category IN ('urgent','obituary'));
  SELECT name INTO cname FROM public.churches WHERE id = a.church_id;

  INSERT INTO public.notifications (
    user_id, title, body, type, reference_id, reference_type
  )
  SELECT
    aud.user_id,
    CASE
      WHEN is_obituary THEN 'Obituary from ' || COALESCE(cname, 'your church')
      WHEN a.category = 'urgent' THEN 'Urgent: ' || a.title
      ELSE COALESCE(cname, 'Your church') || ' posted an update'
    END,
    COALESCE(substr(a.title, 1, 140), ''),
    CASE
      WHEN is_obituary THEN 'announcement_obituary'
      WHEN a.category = 'urgent' THEN 'announcement_urgent'
      ELSE 'announcement'
    END,
    a.id::text,
    'announcement'
  FROM (
    -- patch_297: the church's own members — home church only.
    SELECT p.id AS user_id FROM public.profiles p
     WHERE p.church_id = a.church_id
       AND COALESCE(p.is_banned, FALSE) = FALSE
  ) AS aud
  LEFT JOIN public.notification_preferences np
    ON np.user_id = aud.user_id AND np.church_id = a.church_id
  WHERE aud.user_id <> COALESCE(a.posted_by, '00000000-0000-0000-0000-000000000000'::uuid)
    AND (
      np.id IS NULL
      OR is_obituary
      OR (np.urgent_only = TRUE AND is_urgent)
      OR (np.all_notifications = TRUE AND COALESCE(np.none, FALSE) = FALSE)
    );

  GET DIAGNOSTICS v_count = ROW_COUNT;

  UPDATE public.announcements
     SET sent_count = v_count, notified_at = NOW()
   WHERE id = p_id;

  RETURN v_count;
END;
$function$;

-- 3. Follows of a church that is not the member's home church.
DELETE FROM public.church_followers f
 USING public.profiles p
 WHERE p.id = f.user_id
   AND p.church_id IS DISTINCT FROM f.church_id;

COMMIT;

-- Check (read-only): expect 0.
-- SELECT count(*) FROM public.church_followers f
--   JOIN public.profiles p ON p.id = f.user_id
--  WHERE p.church_id IS DISTINCT FROM f.church_id;

-- >>>>>>>>>>>>>>>> database/patch_292_storage_cleanup.sql
-- =====================================================================
--  PATCH 292 — free database space and keep it free
--  STATUS: not yet applied
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

-- >>>>>>>>>>>>>>>> database/patch_299_prune_e2ee_copies.sql
-- =====================================================================
--  PATCH 299 — keep the re-send tables small
--  STATUS: not yet applied. Run AFTER patch_298 and patch_292.
--
--  patch_298's request/copy tables only matter until the reader's phone
--  has picked a copy up. Copies older than 30 days and fulfilled
--  requests older than 7 days are pruned nightly, inside the existing
--  prune-operational-logs job (restated in full from patch_292).
--
--  CLAUDE.md checklist: no profiles change; no triggers.
-- =====================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.prune_operational_logs()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'net', 'cron'
AS $function$
BEGIN
  DELETE FROM net._http_response WHERE created < now() - interval '1 day';
  DELETE FROM cron.job_run_details WHERE end_time < now() - interval '2 days';
  DELETE FROM public.rate_limits WHERE hit_at < now() - interval '2 days';
  DELETE FROM public.call_events WHERE created_at < now() - interval '30 days';
  DELETE FROM supabase_functions.hooks WHERE created_at < now() - interval '2 days';

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

  -- patch 299: re-send copies and requests (patch_298).
  DELETE FROM public.e2ee_message_copies
   WHERE created_at < now() - interval '30 days';
  DELETE FROM public.e2ee_resend_requests
   WHERE (fulfilled_at IS NOT NULL AND fulfilled_at < now() - interval '7 days')
      OR created_at < now() - interval '30 days';

  DELETE FROM public.app_events   WHERE created_at < now() - interval '120 days';
  DELETE FROM public.app_sessions WHERE started_at < now() - interval '120 days';

  BEGIN
    DELETE FROM auth.refresh_tokens
     WHERE revoked AND updated_at < now() - interval '7 days';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'refresh_tokens prune skipped: no privilege';
  END;
END;
$function$;

COMMIT;
