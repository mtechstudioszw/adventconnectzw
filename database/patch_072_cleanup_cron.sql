-- =====================================================================
--  PATCH 072 — Storage hygiene: delete expired content + prune old rows
--
--  Audit finding: nothing ever DELETES expired stories — RLS only hides
--  them (expires_at), so story rows accumulate forever. notifications
--  also grow unbounded. This adds a daily cleanup + cron.
--
--  NOTE: this frees DATABASE space (rows). Story PHOTO files in the
--  storage bucket are purged separately by the `purge-storage` edge
--  function (deleting storage.objects via SQL does NOT remove the
--  underlying S3 file, so it must go through the storage API).
-- =====================================================================

CREATE OR REPLACE FUNCTION public.cleanup_expired_content()
RETURNS VOID AS $$
BEGIN
  -- 1. Expired stories (24h) — actually delete the rows.
  DELETE FROM public.stories WHERE expires_at < now();

  -- 2. Notifications: drop read ones after 45 days and ANY after 90 days
  --    so the table stays small (it's append-only churn).
  DELETE FROM public.notifications
   WHERE (is_read = TRUE AND created_at < now() - INTERVAL '45 days')
      OR created_at < now() - INTERVAL '90 days';

  -- 3. Resolved/dismissed reports older than 60 days.
  DELETE FROM public.reports
   WHERE status IN ('actioned', 'dismissed')
     AND created_at < now() - INTERVAL '60 days';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Run daily at 03:10 UTC.
SELECT cron.schedule(
  'cleanup-expired-content',
  '10 3 * * *',
  'SELECT public.cleanup_expired_content();'
);
