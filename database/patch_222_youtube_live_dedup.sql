-- =====================================================================
--  PATCH 222 — stop the YouTube live fan-out notifying the same stream
--               over and over
--
--  Reported as "I can't see YouTube notifications being sent". They are
--  being sent. Measured 19 Aug 2026:
--
--    110,366  youtube_live notifications ever
--    107,191  of them still unread
--      4,872  in the last 24 hours, to all 213 members  (~23 each, PER DAY)
--        844  for ONE video (Oo7Erc-2ptI) — 213 members x 4 separate rounds
--      1,481  for one channel (2CBN TV) in 24 hours
--         51 MB  notifications table
--
--  Nobody "sees" them because at 23 a day the OS collapses and throttles
--  them, and a member who has not already uninstalled has muted the app.
--
--  --------------------------------------------------------------------
--  WHY IT REPEATS
--
--  `youtube_fanout_notification` had NO de-duplication of any kind: every
--  call inserted a row for every profile. The only guard lived in the
--  edge function — `if (videoId !== channel.live_notified_video_id)` —
--  which remembers just the LAST video notified per channel. So:
--
--    * a channel whose live video id flaps between two values ping-pongs
--      past the check forever, and the live cron runs EVERY MINUTE;
--    * if the RPC succeeds but the follow-up UPDATE of
--      live_notified_video_id fails, the next tick re-notifies 60s later;
--    * two simultaneous streams on one channel alternate indefinitely.
--
--  A "last one wins" memory cannot express "already told everyone about
--  this broadcast". That needs a set, and it needs to be checked in the
--  same statement that claims it, or the every-minute cron will race.
--  --------------------------------------------------------------------
--
--  THE FIX: claim the video id in a table with a PRIMARY KEY, inside the
--  function, before sending anything. `ON CONFLICT DO NOTHING` makes the
--  claim atomic — whoever inserts the row is the one who notifies, and
--  every later call for that video returns 0 and sends nothing. The edge
--  function's own check stays as a cheap first filter; it is no longer
--  load-bearing.
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.youtube_live_notified (
  video_id    TEXT PRIMARY KEY,
  notified_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  recipients  INTEGER
);

COMMENT ON TABLE public.youtube_live_notified IS
  'One row per video the live fan-out has already announced. The PRIMARY '
  'KEY is the de-duplication: youtube_fanout_notification claims the id '
  'here first and sends nothing if the claim fails. Do not delete rows '
  'for videos that could still be live - that re-arms the notification.';

-- SEED so this patch does not itself trigger one last round for whatever
-- is live right now. Everything announced in the past 30 days counts as
-- already done.
INSERT INTO public.youtube_live_notified (video_id, notified_at)
SELECT reference_id, max(created_at)
  FROM public.notifications
 WHERE type = 'youtube_live'
   AND reference_id IS NOT NULL
   AND created_at > now() - INTERVAL '30 days'
 GROUP BY reference_id
ON CONFLICT (video_id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.youtube_fanout_notification(
  p_title TEXT,
  p_body TEXT,
  p_video_id TEXT
) RETURNS INTEGER AS $$
DECLARE
  v_count INTEGER;
  v_claimed INTEGER;
BEGIN
  -- System fan-out only. Service-role calls have a NULL auth.uid(); a real
  -- signed-in user must never be able to spam everyone.
  IF auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'Not authorized.' USING ERRCODE = '42501';
  END IF;

  IF p_video_id IS NULL OR btrim(p_video_id) = '' THEN
    RAISE EXCEPTION 'A video id is required.' USING ERRCODE = '22023';
  END IF;

  -- Claim it. This is the whole de-duplication: exactly one caller can
  -- insert a given video_id, and only that caller goes on to notify.
  INSERT INTO public.youtube_live_notified (video_id)
  VALUES (p_video_id)
  ON CONFLICT (video_id) DO NOTHING;
  GET DIAGNOSTICS v_claimed = ROW_COUNT;

  IF v_claimed = 0 THEN
    -- Already announced. Not an error: the every-minute cron is EXPECTED
    -- to keep seeing the same stream and is expected to stay quiet.
    RETURN 0;
  END IF;

  INSERT INTO public.notifications
    (user_id, title, body, type, reference_id, reference_type)
  SELECT p.id, p_title, p_body, 'youtube_live', p_video_id, 'video'
    FROM public.profiles p
   WHERE COALESCE(p.is_banned, FALSE) = FALSE;
  GET DIAGNOSTICS v_count = ROW_COUNT;

  UPDATE public.youtube_live_notified
     SET recipients = v_count
   WHERE video_id = p_video_id;

  RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ---------------------------------------------------------------------
--  Verification — run tomorrow, not immediately.
-- ---------------------------------------------------------------------
-- SELECT count(*) AS videos_claimed FROM public.youtube_live_notified;
--
-- SELECT count(*) AS youtube_live_last_24h
--   FROM public.notifications
--  WHERE type='youtube_live' AND created_at > now() - interval '24 hours';
--   -- was 4,872. Expect it to fall to roughly the number of genuinely NEW
--   -- live streams x 213 - a handful a day, not thousands.
--
-- SELECT reference_id, count(*) FROM public.notifications
--  WHERE type='youtube_live' AND created_at > now() - interval '24 hours'
--  GROUP BY 1 HAVING count(*) > 213;
--   -- expect ZERO rows: no video should ever exceed one per member.
