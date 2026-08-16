-- =====================================================================
--  PATCH 202 — "Continue series" in one round trip instead of three
--
--  WHY
--
--  The Watch tab's bootstrap fires nine shelf queries in parallel and
--  then paints. `Future.wait` finishes when the SLOWEST finishes, so the
--  tab is only as fast as its worst shelf — and one shelf was not a
--  query at all but a chain of three:
--
--    YoutubeService.fetchContinueSeries()
--      1. youtube_watch_history   -> the user's last 40 video ids
--      2. youtube_playlist_items  -> which series those belong to
--      3. youtube_playlists       -> the series rows themselves
--
--  Each step needs the previous step's ids, so they cannot overlap.
--  On a Zimbabwean mobile connection at 200-400ms RTT that is roughly
--  0.6-1.2s during which every other shelf has already returned and the
--  tab is waiting on this one alone.
--
--  The database was never the problem — measured on production, the
--  individual queries run in 3-5ms and every column involved is indexed
--  (idx_yt_history_user, idx_yt_pli_video, the playlists pkey). This is
--  purely about collapsing three sequential network hops into one.
--
--  SECURITY
--
--  SECURITY INVOKER (the default) on purpose, NOT definer. Every table
--  it touches already has RLS that says exactly the right thing —
--  `yt_history_own` restricts history to its owner, and the playlist
--  tables are read-only to members — so running as the caller needs no
--  extra trust and cannot leak another member's viewing history. A
--  DEFINER function here would have to re-implement that guard by hand,
--  which is how those guards drift.
--
--  Note the `auth.uid()` filter is still explicit rather than left to
--  RLS. It costs nothing, and it means the function is still correct if
--  the history policy is ever loosened.
--
--  GRANTS
--
--  Supabase grants EXECUTE on new functions to `anon` AND
--  `authenticated` explicitly, so REVOKE FROM PUBLIC alone does NOT
--  remove anon's access. anon is revoked by name below. Verify with
--  has_function_privilege, not by reading this file.
--
--  IDEMPOTENT: yes — CREATE OR REPLACE + explicit grants.
-- =====================================================================


DROP FUNCTION IF EXISTS public.youtube_continue_series(INTEGER);

CREATE FUNCTION public.youtube_continue_series(p_limit INTEGER DEFAULT 6)
RETURNS TABLE (
  playlist_id      TEXT,
  channel_id       TEXT,
  title            TEXT,
  description      TEXT,
  thumbnail_url    TEXT,
  item_count       INTEGER,
  is_category      BOOLEAN,
  sort_order       INTEGER,
  reached_position INTEGER
)
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  WITH hist AS (
    -- Same 40-row window the Dart used. More than that and "continue"
    -- starts resurrecting series the member moved on from weeks ago.
    SELECT h.video_id
      FROM public.youtube_watch_history h
     WHERE h.user_id = auth.uid()
     ORDER BY h.watched_at DESC
     LIMIT 40
  ),
  best AS (
    -- The FURTHEST point reached in each series, not the most recent —
    -- rewatching episode two must not lose someone's place at episode ten.
    SELECT i.playlist_id, MAX(i.position) AS reached
      FROM public.youtube_playlist_items i
      JOIN hist h ON h.video_id = i.video_id
     GROUP BY i.playlist_id
  )
  SELECT p.playlist_id,
         p.channel_id,
         p.title,
         p.description,
         p.thumbnail_url,
         p.item_count,
         p.is_category,
         p.sort_order,
         b.reached::INTEGER
    FROM best b
    JOIN public.youtube_playlists p ON p.playlist_id = b.playlist_id
   -- A one-item "series" is not a series, and a finished one shouldn't
   -- nag. Both conditions carried over from the Dart verbatim.
   WHERE p.item_count >= 2
     AND b.reached < p.item_count - 1
   ORDER BY p.item_count DESC
   LIMIT GREATEST(COALESCE(p_limit, 6), 1);
$$;

REVOKE ALL ON FUNCTION public.youtube_continue_series(INTEGER)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.youtube_continue_series(INTEGER)
  TO authenticated;
