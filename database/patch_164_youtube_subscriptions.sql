-- =====================================================================
--  PATCH 164 — Per-user channel subscriptions for the Watch tab
--
--  youtube_channels.subscriber_count is YouTube's OWN number, synced
--  from their API. Nothing in the app has ever recorded which channels
--  THIS user follows, so there was no way to build a "New from your
--  channels" feed. This is that table.
--
--  Deliberately minimal: a join table plus RLS. Counts are derived, not
--  stored — a denormalised counter would need a trigger and would drift.
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.youtube_subscriptions (
  user_id     uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  channel_id  text        NOT NULL REFERENCES public.youtube_channels(channel_id) ON DELETE CASCADE,
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, channel_id)
);

-- "Which channels do I follow" is the hot path; the PK already covers it.
-- This one serves the reverse lookup (how many follow a channel).
CREATE INDEX IF NOT EXISTS youtube_subscriptions_channel_idx
  ON public.youtube_subscriptions (channel_id);

ALTER TABLE public.youtube_subscriptions ENABLE ROW LEVEL SECURITY;

-- A user sees and edits only their own subscriptions.
DROP POLICY IF EXISTS youtube_subscriptions_select_own ON public.youtube_subscriptions;
CREATE POLICY youtube_subscriptions_select_own
  ON public.youtube_subscriptions FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS youtube_subscriptions_insert_own ON public.youtube_subscriptions;
CREATE POLICY youtube_subscriptions_insert_own
  ON public.youtube_subscriptions FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS youtube_subscriptions_delete_own ON public.youtube_subscriptions;
CREATE POLICY youtube_subscriptions_delete_own
  ON public.youtube_subscriptions FOR DELETE
  USING (auth.uid() = user_id);

GRANT SELECT, INSERT, DELETE ON public.youtube_subscriptions TO authenticated;

-- ---------------------------------------------------------------------
--  Newest videos from the channels the caller follows.
--
--  SECURITY INVOKER (the default) so the RLS policy above scopes the
--  subscription lookup to the caller — this cannot leak another user's
--  follow list.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.youtube_subscription_feed(
  p_limit  INTEGER DEFAULT 20,
  p_offset INTEGER DEFAULT 0
)
RETURNS SETOF public.youtube_videos
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT v.*
    FROM public.youtube_videos v
    JOIN public.youtube_subscriptions s
      ON s.channel_id = v.channel_id
   WHERE s.user_id = auth.uid()
     AND v.live_status <> 'upcoming'
   ORDER BY v.published_at DESC NULLS LAST
   LIMIT  GREATEST(p_limit, 0)
  OFFSET GREATEST(p_offset, 0);
$$;

GRANT EXECUTE ON FUNCTION public.youtube_subscription_feed(INTEGER, INTEGER)
  TO authenticated;
