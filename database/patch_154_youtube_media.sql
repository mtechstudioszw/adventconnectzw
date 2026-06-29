-- =====================================================================
--  PATCH 154 — YouTube media platform (Watch) — backend foundation
--
--  Metadata-ONLY storage. No video/audio/image bytes ever live in
--  Supabase — only IDs + short text. Video streams YouTube -> device via
--  the official IFrame player; thumbnails hotlink from i.ytimg.com.
--
--  Tables
--    youtube_channels            monitored channels (admin-seeded + approved submissions)
--    youtube_videos              synced video metadata (the library)
--    youtube_playlists           playlists -> double as Watch-tab category chips
--    youtube_playlist_items      video <-> playlist mapping
--    youtube_channel_submissions user "add my channel" requests (super-admin approves)
--    youtube_bookmarks           per-user Saved / My List
--    youtube_watch_history       per-user resume position + completed
--    youtube_video_notes         per-user timestamped sermon notes
--
--  Security model mirrors the rest of the app:
--    - GLOBAL content (channels/videos/playlists) is world-readable but
--      ONLY rows that are visible (active channel, not hidden). All writes
--      are service-role only (the youtube-sync edge function) — no app RLS
--      write policy exists, so authenticated users cannot mutate content.
--    - PER-USER tables are RLS-scoped to auth.uid().
--    - Admin RPCs are SECURITY DEFINER + assert_super_admin() (patch_040).
--
--  The youtube-sync edge function (cron-driven) does all YouTube Data API
--  work with the server-only YOUTUBE_API_KEY: resolve approved submissions,
--  backfill catalogs (throttled, resumable), poll live status, refresh
--  WebSub leases. See supabase/functions/youtube-sync/.
--
--  Apply:  POST /v1/projects/<ref>/database/query (mgmt API) or SQL editor.
--  IDEMPOTENT: CREATE ... IF NOT EXISTS / CREATE OR REPLACE throughout.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Tables
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.youtube_channels (
  channel_id          text PRIMARY KEY,                 -- UC...
  title               text NOT NULL DEFAULT '',
  handle              text,                              -- @handle
  description         text,
  thumbnail_url       text,
  uploads_playlist_id text,                             -- UU... (for backfill)
  subscriber_count    bigint,
  status              text NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending','active','rejected','disabled')),
  -- submission provenance (NULL for admin-seeded)
  submitted_by        uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  -- denormalised live state for the instant LIVE banner read
  is_live             boolean NOT NULL DEFAULT false,
  live_video_id       text,
  -- sync bookkeeping
  backfill_page_token text,                             -- resume cursor
  backfill_done       boolean NOT NULL DEFAULT false,
  websub_expires_at   timestamptz,
  last_synced_at      timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now(),
  approved_at         timestamptz
);
CREATE INDEX IF NOT EXISTS idx_yt_channels_status ON public.youtube_channels(status);
CREATE INDEX IF NOT EXISTS idx_yt_channels_live   ON public.youtube_channels(is_live) WHERE is_live;

CREATE TABLE IF NOT EXISTS public.youtube_videos (
  video_id           text PRIMARY KEY,                  -- 11-char id
  channel_id         text NOT NULL REFERENCES public.youtube_channels(channel_id) ON DELETE CASCADE,
  channel_title      text NOT NULL DEFAULT '',          -- denormalised for zero-join cards + search
  channel_thumb_url  text,
  title              text NOT NULL DEFAULT '',
  description        text,                               -- capped on insert (~2k chars)
  thumbnail_url      text,
  published_at       timestamptz,
  duration_seconds   integer NOT NULL DEFAULT 0,
  kind               text NOT NULL DEFAULT 'video'
                       CHECK (kind IN ('video','live','upcoming')),
  live_status        text NOT NULL DEFAULT 'none'
                       CHECK (live_status IN ('none','live','upcoming','ended')),
  scheduled_start_at timestamptz,
  actual_start_at    timestamptz,
  view_count         bigint,
  is_hidden          boolean NOT NULL DEFAULT false,     -- admin per-video hide
  fetched_at         timestamptz NOT NULL DEFAULT now(), -- for the ~30-day refresh rule
  created_at         timestamptz NOT NULL DEFAULT now(),
  search_tsv tsvector GENERATED ALWAYS AS (
    setweight(to_tsvector('english', coalesce(title,'')), 'A') ||
    setweight(to_tsvector('english', coalesce(description,'')), 'B') ||
    setweight(to_tsvector('english', coalesce(channel_title,'')), 'C')
  ) STORED
);
CREATE INDEX IF NOT EXISTS idx_yt_videos_channel    ON public.youtube_videos(channel_id);
CREATE INDEX IF NOT EXISTS idx_yt_videos_published  ON public.youtube_videos(published_at DESC);
CREATE INDEX IF NOT EXISTS idx_yt_videos_live       ON public.youtube_videos(live_status)
  WHERE live_status IN ('live','upcoming');
CREATE INDEX IF NOT EXISTS idx_yt_videos_fts        ON public.youtube_videos USING gin(search_tsv);

CREATE TABLE IF NOT EXISTS public.youtube_playlists (
  playlist_id   text PRIMARY KEY,
  channel_id    text NOT NULL REFERENCES public.youtube_channels(channel_id) ON DELETE CASCADE,
  title         text NOT NULL DEFAULT '',
  description   text,
  thumbnail_url text,
  item_count    integer NOT NULL DEFAULT 0,
  is_category   boolean NOT NULL DEFAULT true,           -- show as a category chip
  sort_order    integer NOT NULL DEFAULT 0,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_yt_playlists_channel ON public.youtube_playlists(channel_id);

CREATE TABLE IF NOT EXISTS public.youtube_playlist_items (
  playlist_id text NOT NULL REFERENCES public.youtube_playlists(playlist_id) ON DELETE CASCADE,
  video_id    text NOT NULL,            -- NOT FK: item may reference a not-yet-synced video
  position    integer NOT NULL DEFAULT 0,
  PRIMARY KEY (playlist_id, video_id)
);
CREATE INDEX IF NOT EXISTS idx_yt_pli_video ON public.youtube_playlist_items(video_id);

CREATE TABLE IF NOT EXISTS public.youtube_channel_submissions (
  id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  submitted_by      uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  link              text NOT NULL,                       -- raw URL / @handle as entered
  submitter_name    text,
  submitter_contact text,                                -- WhatsApp / email (off-app verify)
  note              text,
  status            text NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending','approved','rejected')),
  resolved_channel_id text,                              -- set by edge fn once resolved
  rejection_reason  text,
  created_at        timestamptz NOT NULL DEFAULT now(),
  reviewed_at       timestamptz
);
CREATE INDEX IF NOT EXISTS idx_yt_subs_status ON public.youtube_channel_submissions(status);

CREATE TABLE IF NOT EXISTS public.youtube_bookmarks (
  user_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  video_id   text NOT NULL REFERENCES public.youtube_videos(video_id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, video_id)
);
CREATE INDEX IF NOT EXISTS idx_yt_bookmarks_user ON public.youtube_bookmarks(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.youtube_watch_history (
  user_id          uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  video_id         text NOT NULL REFERENCES public.youtube_videos(video_id) ON DELETE CASCADE,
  position_seconds integer NOT NULL DEFAULT 0,
  duration_seconds integer NOT NULL DEFAULT 0,
  completed        boolean NOT NULL DEFAULT false,
  watched_at       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, video_id)
);
CREATE INDEX IF NOT EXISTS idx_yt_history_user ON public.youtube_watch_history(user_id, watched_at DESC);

CREATE TABLE IF NOT EXISTS public.youtube_video_notes (
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id          uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  video_id         text NOT NULL REFERENCES public.youtube_videos(video_id) ON DELETE CASCADE,
  position_seconds integer NOT NULL DEFAULT 0,
  note             text NOT NULL,
  created_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_yt_notes_user_video ON public.youtube_video_notes(user_id, video_id, position_seconds);


-- ---------------------------------------------------------------------
-- 1. RLS
-- ---------------------------------------------------------------------
ALTER TABLE public.youtube_channels            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.youtube_videos              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.youtube_playlists           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.youtube_playlist_items      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.youtube_channel_submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.youtube_bookmarks           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.youtube_watch_history       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.youtube_video_notes         ENABLE ROW LEVEL SECURITY;

-- Global content: read-only to everyone, but only VISIBLE rows. No write
-- policy => only the service role (edge fn) can mutate.
DROP POLICY IF EXISTS yt_channels_read ON public.youtube_channels;
CREATE POLICY yt_channels_read ON public.youtube_channels
  FOR SELECT TO authenticated, anon
  USING (status = 'active' OR submitted_by = auth.uid());

DROP POLICY IF EXISTS yt_videos_read ON public.youtube_videos;
CREATE POLICY yt_videos_read ON public.youtube_videos
  FOR SELECT TO authenticated, anon
  USING (
    NOT is_hidden
    AND EXISTS (SELECT 1 FROM public.youtube_channels c
                 WHERE c.channel_id = youtube_videos.channel_id AND c.status = 'active')
  );

DROP POLICY IF EXISTS yt_playlists_read ON public.youtube_playlists;
CREATE POLICY yt_playlists_read ON public.youtube_playlists
  FOR SELECT TO authenticated, anon
  USING (
    EXISTS (SELECT 1 FROM public.youtube_channels c
             WHERE c.channel_id = youtube_playlists.channel_id AND c.status = 'active')
  );

DROP POLICY IF EXISTS yt_playlist_items_read ON public.youtube_playlist_items;
CREATE POLICY yt_playlist_items_read ON public.youtube_playlist_items
  FOR SELECT TO authenticated, anon
  USING (
    EXISTS (SELECT 1 FROM public.youtube_playlists p
              JOIN public.youtube_channels c ON c.channel_id = p.channel_id
             WHERE p.playlist_id = youtube_playlist_items.playlist_id
               AND c.status = 'active')
  );

-- Submissions: a user may create + see their own; admins use RPCs.
DROP POLICY IF EXISTS yt_subs_insert_own ON public.youtube_channel_submissions;
CREATE POLICY yt_subs_insert_own ON public.youtube_channel_submissions
  FOR INSERT TO authenticated
  WITH CHECK (submitted_by = auth.uid());
DROP POLICY IF EXISTS yt_subs_read_own ON public.youtube_channel_submissions;
CREATE POLICY yt_subs_read_own ON public.youtube_channel_submissions
  FOR SELECT TO authenticated
  USING (submitted_by = auth.uid());

-- Per-user tables: full CRUD on own rows.
DROP POLICY IF EXISTS yt_bookmarks_own ON public.youtube_bookmarks;
CREATE POLICY yt_bookmarks_own ON public.youtube_bookmarks
  FOR ALL TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS yt_history_own ON public.youtube_watch_history;
CREATE POLICY yt_history_own ON public.youtube_watch_history
  FOR ALL TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS yt_notes_own ON public.youtube_video_notes;
CREATE POLICY yt_notes_own ON public.youtube_video_notes
  FOR ALL TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());


-- ---------------------------------------------------------------------
-- 2. Read RPCs (the app reads most things via RLS table queries; these
--    cover the cases that need server logic).
-- ---------------------------------------------------------------------

-- Full-text search across the visible library (title/description/channel).
CREATE OR REPLACE FUNCTION public.youtube_search(
  p_query TEXT,
  p_limit INT DEFAULT 30,
  p_offset INT DEFAULT 0
)
RETURNS SETOF public.youtube_videos
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT v.*
    FROM public.youtube_videos v
    JOIN public.youtube_channels c ON c.channel_id = v.channel_id
   WHERE c.status = 'active'
     AND v.is_hidden = false
     AND (
       btrim(coalesce(p_query,'')) = ''
       OR v.search_tsv @@ websearch_to_tsquery('english', p_query)
     )
   ORDER BY
     CASE WHEN btrim(coalesce(p_query,'')) = '' THEN 0
          ELSE ts_rank(v.search_tsv, websearch_to_tsquery('english', p_query)) END DESC,
     v.published_at DESC
   LIMIT GREATEST(p_limit, 1) OFFSET GREATEST(p_offset, 0);
$$;

-- Endless "Up next" from OUR library (faith-safe; no YouTube algo). Priority:
-- same playlist (0) -> same channel (1) -> everything else (2), newest first.
-- Excludes the current video and anything the caller has already completed.
CREATE OR REPLACE FUNCTION public.youtube_up_next(
  p_video_id TEXT,
  p_limit INT DEFAULT 20,
  p_offset INT DEFAULT 0
)
RETURNS SETOF public.youtube_videos
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth AS $$
  WITH cur AS (
    SELECT channel_id FROM public.youtube_videos WHERE video_id = p_video_id
  )
  SELECT v.*
    FROM public.youtube_videos v
    JOIN public.youtube_channels c ON c.channel_id = v.channel_id
   WHERE c.status = 'active'
     AND v.is_hidden = false
     AND v.video_id <> p_video_id
     AND NOT EXISTS (
       SELECT 1 FROM public.youtube_watch_history h
        WHERE h.user_id = auth.uid() AND h.video_id = v.video_id AND h.completed
     )
   ORDER BY
     (CASE
        WHEN EXISTS (
          SELECT 1 FROM public.youtube_playlist_items a
            JOIN public.youtube_playlist_items b ON a.playlist_id = b.playlist_id
           WHERE a.video_id = v.video_id AND b.video_id = p_video_id
        ) THEN 0
        WHEN v.channel_id = (SELECT channel_id FROM cur) THEN 1
        ELSE 2
      END),
     v.published_at DESC
   LIMIT GREATEST(p_limit, 1) OFFSET GREATEST(p_offset, 0);
$$;

-- The single currently-live video for the Home LIVE banner (or none).
CREATE OR REPLACE FUNCTION public.youtube_current_live()
RETURNS SETOF public.youtube_videos
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT v.*
    FROM public.youtube_videos v
    JOIN public.youtube_channels c ON c.channel_id = v.channel_id
   WHERE c.status = 'active' AND v.is_hidden = false AND v.live_status = 'live'
   ORDER BY coalesce(v.actual_start_at, v.published_at) DESC
   LIMIT 1;
$$;


-- ---------------------------------------------------------------------
-- 3. User submission RPC ("Submit your channel" from the Watch tab)
--    One pending submission per user at a time (anti-spam).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.submit_youtube_channel(
  p_link    TEXT,
  p_name    TEXT DEFAULT NULL,
  p_contact TEXT DEFAULT NULL,
  p_note    TEXT DEFAULT NULL
)
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_uid  uuid := auth.uid();
  v_link text := btrim(coalesce(p_link,''));
  v_id   bigint;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Sign in required.' USING ERRCODE = '42501';
  END IF;
  IF v_link = '' OR v_link !~* 'youtube\.com|youtu\.be|^@|^UC[A-Za-z0-9_-]{20,}$' THEN
    RAISE EXCEPTION 'Enter a valid YouTube channel link or @handle.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.youtube_channel_submissions
              WHERE submitted_by = v_uid AND status = 'pending') THEN
    RAISE EXCEPTION 'You already have a channel under review.';
  END IF;

  INSERT INTO public.youtube_channel_submissions
    (submitted_by, link, submitter_name, submitter_contact, note)
  VALUES (v_uid, v_link, NULLIF(btrim(coalesce(p_name,'')),''),
          NULLIF(btrim(coalesce(p_contact,'')),''),
          NULLIF(btrim(coalesce(p_note,'')),''))
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;


-- ---------------------------------------------------------------------
-- 4. Admin RPCs (web console) — SECURITY DEFINER + assert_super_admin().
--    The youtube-sync edge function (cron) picks up the state changes:
--    'approved' submissions get resolved, new channels get backfilled.
-- ---------------------------------------------------------------------

-- Admin adds a core channel by link (becomes an auto-approved submission
-- the edge fn resolves on its next tick).
CREATE OR REPLACE FUNCTION public.admin_add_youtube_channel(p_link TEXT)
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE v_id bigint; v_link text := btrim(coalesce(p_link,''));
BEGIN
  PERFORM public.assert_super_admin();
  IF v_link = '' THEN RAISE EXCEPTION 'Channel link required.'; END IF;
  INSERT INTO public.youtube_channel_submissions
    (submitted_by, link, status, reviewed_at)
  VALUES (NULL, v_link, 'approved', now())
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- List channels for the console.
CREATE OR REPLACE FUNCTION public.admin_list_youtube_channels(p_status TEXT DEFAULT 'all')
RETURNS SETOF public.youtube_channels
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
BEGIN
  PERFORM public.assert_super_admin();
  RETURN QUERY
    SELECT * FROM public.youtube_channels
     WHERE (p_status = 'all' OR status = p_status)
     ORDER BY (status='active') DESC, created_at DESC;
END;
$$;

-- List submissions (pending queue) with submitter identity.
CREATE OR REPLACE FUNCTION public.admin_list_youtube_submissions(p_status TEXT DEFAULT 'pending')
RETURNS TABLE (
  id BIGINT, link TEXT, submitter_name TEXT, submitter_contact TEXT, note TEXT,
  status TEXT, resolved_channel_id TEXT, rejection_reason TEXT,
  created_at TIMESTAMPTZ, profile_name TEXT, profile_email TEXT
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
BEGIN
  PERFORM public.assert_super_admin();
  RETURN QUERY
    SELECT s.id, s.link, s.submitter_name, s.submitter_contact, s.note,
           s.status, s.resolved_channel_id, s.rejection_reason, s.created_at,
           COALESCE(NULLIF(btrim(p.full_name),''),'Member'), u.email::text
      FROM public.youtube_channel_submissions s
      LEFT JOIN public.profiles p ON p.id = s.submitted_by
      LEFT JOIN auth.users   u ON u.id = s.submitted_by
     WHERE (p_status = 'all' OR s.status = p_status)
     ORDER BY s.created_at DESC;
END;
$$;

-- Approve / reject a submission. Approve -> edge fn resolves + onboards it.
CREATE OR REPLACE FUNCTION public.admin_review_youtube_submission(
  p_id BIGINT, p_approve BOOLEAN, p_reason TEXT DEFAULT NULL
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE v_user uuid; v_clean text := NULLIF(btrim(coalesce(p_reason,'')),'');
BEGIN
  PERFORM public.assert_super_admin();
  SELECT submitted_by INTO v_user FROM public.youtube_channel_submissions WHERE id = p_id;

  UPDATE public.youtube_channel_submissions
     SET status = CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END,
         rejection_reason = CASE WHEN p_approve THEN NULL ELSE v_clean END,
         reviewed_at = now()
   WHERE id = p_id;

  IF v_user IS NOT NULL THEN
    INSERT INTO public.notifications (user_id, title, body, type, reference_id, reference_type)
    VALUES (
      v_user,
      CASE WHEN p_approve THEN 'Your channel was approved' ELSE 'Channel submission update' END,
      CASE WHEN p_approve
           THEN 'Your YouTube channel has been approved and will start appearing in Watch shortly. Thank you!'
           ELSE 'Your channel submission was not approved.'
                || CASE WHEN v_clean IS NOT NULL THEN ' Reason: ' || v_clean ELSE '' END END,
      CASE WHEN p_approve THEN 'youtube_channel_approved' ELSE 'youtube_channel_rejected' END,
      p_id::text, 'youtube_channel'
    );
  END IF;
END;
$$;

-- Enable / disable / remove a channel.
CREATE OR REPLACE FUNCTION public.admin_set_youtube_channel_status(
  p_channel_id TEXT, p_status TEXT
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
BEGIN
  PERFORM public.assert_super_admin();
  IF p_status NOT IN ('active','disabled','rejected') THEN
    RAISE EXCEPTION 'Invalid status %', p_status;
  END IF;
  UPDATE public.youtube_channels
     SET status = p_status,
         is_live = CASE WHEN p_status = 'active' THEN is_live ELSE false END
   WHERE channel_id = p_channel_id;
END;
$$;

-- Hide / unhide a single video.
CREATE OR REPLACE FUNCTION public.admin_set_youtube_video_hidden(
  p_video_id TEXT, p_hidden BOOLEAN
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
BEGIN
  PERFORM public.assert_super_admin();
  UPDATE public.youtube_videos SET is_hidden = p_hidden WHERE video_id = p_video_id;
END;
$$;


-- ---------------------------------------------------------------------
-- 5. Grants
-- ---------------------------------------------------------------------
REVOKE ALL ON FUNCTION
  public.youtube_search(TEXT,INT,INT),
  public.youtube_up_next(TEXT,INT,INT),
  public.youtube_current_live(),
  public.submit_youtube_channel(TEXT,TEXT,TEXT,TEXT),
  public.admin_add_youtube_channel(TEXT),
  public.admin_list_youtube_channels(TEXT),
  public.admin_list_youtube_submissions(TEXT),
  public.admin_review_youtube_submission(BIGINT,BOOLEAN,TEXT),
  public.admin_set_youtube_channel_status(TEXT,TEXT),
  public.admin_set_youtube_video_hidden(TEXT,BOOLEAN)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION
  public.youtube_search(TEXT,INT,INT),
  public.youtube_up_next(TEXT,INT,INT),
  public.youtube_current_live(),
  public.submit_youtube_channel(TEXT,TEXT,TEXT,TEXT),
  public.admin_add_youtube_channel(TEXT),
  public.admin_list_youtube_channels(TEXT),
  public.admin_list_youtube_submissions(TEXT),
  public.admin_review_youtube_submission(BIGINT,BOOLEAN,TEXT),
  public.admin_set_youtube_channel_status(TEXT,TEXT),
  public.admin_set_youtube_video_hidden(TEXT,BOOLEAN)
TO authenticated;
-- Anonymous (logged-out) read of the public library is fine too:
GRANT EXECUTE ON FUNCTION
  public.youtube_search(TEXT,INT,INT),
  public.youtube_current_live()
TO anon;
