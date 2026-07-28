-- =====================================================================
--  PATCH 174 — Scheduled announcements
--
--  WHY: founder request (2026-07-28). A church secretary writes Sabbath's
--  notices on Thursday night and wants them to land Sabbath morning.
--
--  NO NEW COLUMN NEEDED. `announcements.publish_at TIMESTAMPTZ` has been
--  in the schema since patch_002 (line 170) and was never wired to
--  anything — nothing read it, nothing wrote it. This patch gives it the
--  meaning it was always named for.
--
--  WHAT:
--    1. A cron job every 5 minutes publishes announcements whose
--       publish_at has passed and which have not been fanned out.
--    2. Idempotence comes from patch_173's notified_at, not from the
--       cron: fanout_announcement() returns 0 without doing anything for
--       an announcement already sent. A cron double-fire, a manual run
--       and a retry are all harmless.
--    3. A 7-day floor on how far back the publisher will look, so
--       restoring an old backup can never spam a congregation with
--       months of announcements at once.
--
--  READ PATH: members must not see an announcement before its time.
--  ChurchService.fetchAnnouncements filters on publish_at (see the Dart
--  side of this change). That filter is a UX guarantee, not a security
--  boundary — an announcement is church-public content either way, and
--  tightening the announcements RLS policy would mean dropping a live
--  policy that this session cannot read first. Flagged deliberately.
--
--  PREREQUISITES: patch_173 (fanout_announcement, notified_at).
--  IDEMPOTENT: yes.
-- =====================================================================

CREATE INDEX IF NOT EXISTS idx_announcements_pending_publish
  ON public.announcements (publish_at)
  WHERE notified_at IS NULL AND publish_at IS NOT NULL;


CREATE OR REPLACE FUNCTION public.publish_due_announcements()
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  r        RECORD;
  v_total  INTEGER := 0;
BEGIN
  FOR r IN
    SELECT id FROM public.announcements
     WHERE notified_at IS NULL
       AND publish_at IS NOT NULL
       AND publish_at <= NOW()
       -- Backup-restore guard: anything more than a week overdue is not
       -- news, it is history. Left unnotified rather than silently sent.
       AND publish_at > NOW() - INTERVAL '7 days'
     ORDER BY publish_at
     LIMIT 50
  LOOP
    v_total := v_total + public.fanout_announcement(r.id);
  END LOOP;
  RETURN v_total;
END;
$$;

REVOKE ALL ON FUNCTION public.publish_due_announcements() FROM PUBLIC, anon, authenticated;


-- ---------------------------------------------------------------------
--  Schedule. Unschedule first so re-running this patch doesn't stack
--  duplicate jobs (the pattern used by patch_114).
-- ---------------------------------------------------------------------
DO $$
BEGIN
  PERFORM cron.unschedule('publish-due-announcements')
    WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'publish-due-announcements');
EXCEPTION WHEN OTHERS THEN
  NULL;  -- pg_cron not installed in this environment; skip scheduling
END $$;

DO $$
BEGIN
  PERFORM cron.schedule(
    'publish-due-announcements',
    '*/5 * * * *',
    $cron$ SELECT public.publish_due_announcements(); $cron$
  );
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_cron unavailable — schedule publish_due_announcements() manually.';
END $$;


-- =====================================================================
--  VERIFY
--    -- Queue one two minutes out, then watch it flip:
--    SELECT id, title, publish_at, notified_at, sent_count
--      FROM announcements
--     WHERE publish_at IS NOT NULL ORDER BY publish_at DESC LIMIT 10;
--
--    SELECT jobname, schedule, active FROM cron.job
--     WHERE jobname = 'publish-due-announcements';
--
--  Unschedule: SELECT cron.unschedule('publish-due-announcements');
-- =====================================================================
