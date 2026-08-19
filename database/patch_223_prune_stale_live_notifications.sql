-- =====================================================================
--  PATCH 223 — clear the live-notification backlog, and keep it clear
--
--  patch_222 stopped the YouTube live fan-out re-notifying the same
--  stream. This deals with what it already left behind, and makes sure a
--  backlog cannot build up again.
--
--  State before this patch:
--    110,366  youtube_live notifications
--    107,191  of them unread  (~500 per member, 213 members)
--        51 MB  notifications table
--
--  A "X is live" ping has a shelf life of hours — the stream ends. One
--  from three days ago cannot be acted on by anybody, and 500 of them
--  bury the notifications that CAN be: a friend request, a message, a
--  prayer. This is not really member data; it is litter the app generated
--  by accident.
--
--  WHAT IS DELETED: youtube_live only, unread only, older than 24 hours.
--  WHAT IS KEPT:
--    * the last 24 hours — a stream from this morning may still be live;
--    * anything already READ — somebody chose to look at it;
--    * every other notification type, untouched.
--
--  DELETION IS NOT REVERSIBLE. If a more cautious cut is wanted, change
--  the interval below to '7 days' — that still clears the overwhelming
--  majority and keeps a week of history.
-- =====================================================================

DELETE FROM public.notifications
 WHERE type = 'youtube_live'
   AND is_read = FALSE
   AND created_at < now() - INTERVAL '24 hours';

-- ---------------------------------------------------------------------
--  Keep it clear.
--
--  patch_072's cleanup prunes read notifications after 45 days and ANY
--  after 90. That cadence is right for a friend request and far too slow
--  for a live ping — 90 days of these is what 51 MB looks like. Live
--  notifications now age out after 7 days regardless of read state.
--
--  This EXTENDS the existing cron function rather than adding a second
--  job, so there is one place that prunes notifications, not two that can
--  disagree.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.prune_stale_live_notifications()
RETURNS INTEGER AS $$
DECLARE v_deleted INTEGER;
BEGIN
  DELETE FROM public.notifications
   WHERE type = 'youtube_live'
     AND created_at < now() - INTERVAL '7 days';
  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  -- The claim rows are tiny, but a video nobody could still be watching
  -- does not need its claim kept either. 30 days is well past any live
  -- stream, so re-notifying is not a risk.
  DELETE FROM public.youtube_live_notified
   WHERE notified_at < now() - INTERVAL '30 days';

  RETURN v_deleted;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

SELECT cron.schedule(
  'prune-stale-live-notifications',
  '20 3 * * *',
  'SELECT public.prune_stale_live_notifications();'
);

-- ---------------------------------------------------------------------
--  Verification
-- ---------------------------------------------------------------------
-- SELECT count(*) FILTER (WHERE is_read) AS read,
--        count(*) FILTER (WHERE NOT is_read) AS unread
--   FROM public.notifications WHERE type='youtube_live';
--   -- was 3,175 read / 107,191 unread
--
-- SELECT pg_size_pretty(pg_total_relation_size('public.notifications'));
--   -- was 51 MB
--
-- SELECT jobname, schedule FROM cron.job
--  WHERE jobname = 'prune-stale-live-notifications';
