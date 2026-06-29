-- =====================================================================
--  PATCH 156 — YouTube live-stream push fan-out
--
--  When a monitored channel goes LIVE, the youtube-sync edge function
--  calls youtube_fanout_notification() once (deduped via the new
--  youtube_channels.live_notified_video_id) to drop a notification into
--  every non-banned user's feed — which the notify-fcm webhook also
--  pushes. reference_type='video' so the tap opens the in-app player
--  (main.dart + DeepLinkService handle the 'video' case).
--
--  Service-role only: the function rejects authenticated callers and is
--  granted to service_role (the edge function), like a system fan-out.
-- =====================================================================
ALTER TABLE public.youtube_channels
  ADD COLUMN IF NOT EXISTS live_notified_video_id text;

CREATE OR REPLACE FUNCTION public.youtube_fanout_notification(
  p_title TEXT, p_body TEXT, p_video_id TEXT
)
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE v_count INTEGER;
BEGIN
  -- System fan-out only. Service-role calls have a NULL auth.uid(); a real
  -- signed-in user must never be able to spam everyone.
  IF auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'Not authorized.' USING ERRCODE = '42501';
  END IF;
  INSERT INTO public.notifications
    (user_id, title, body, type, reference_id, reference_type)
  SELECT p.id, p_title, p_body, 'youtube_live', p_video_id, 'video'
    FROM public.profiles p
   WHERE COALESCE(p.is_banned, FALSE) = FALSE;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.youtube_fanout_notification(TEXT, TEXT, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.youtube_fanout_notification(TEXT, TEXT, TEXT)
  TO service_role;
