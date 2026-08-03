-- ---------------------------------------------------------------------
--  USAGE ANALYTICS — the data source the admin console needs to exist
--  before any of its charts can mean anything.
--
--  WHY THIS EXISTS (audited 3 Aug 2026):
--  The app's AnalyticsService writes to FIREBASE, not to Supabase, and
--  it fires only eight coarse events (church_followed, message_sent,
--  prayer_posted, marketplace_contact, event_rsvp, church_claimed,
--  job_posted, seller_applied). There is no events table, no sessions
--  table, no device/version/screen data anywhere in this database.
--
--  So the honest position: "which features are used and which are
--  ignored" — the founder's central question — CANNOT be answered from
--  Supabase today. Not partially: at all. This migration builds the
--  source of truth so it can be.
--
--  DESIGN NOTES
--  * Deliberately NO new cron job. Three already exist that nobody knew
--    about (see memory brief03-open-bugs), and at 170 users the
--    aggregates are cheap enough to compute on read. Revisit if the
--    events table passes a few million rows.
--  * The client may only WRITE events, through one SECURITY DEFINER
--    RPC that stamps the user id itself. It can never read anyone's
--    events, including its own — this is a measurement table, not a
--    social feature, and it should never become an information leak.
--  * Feature names are a fixed vocabulary. Free-text feature names rot
--    into 'chat', 'Chat', 'chat_screen' within a month and the ranking
--    the founder actually wants becomes meaningless.
-- ---------------------------------------------------------------------

-- =====================================================================
--  1. The vocabulary
--
--  One row per thing a user can be "in". Adding a feature is a one-line
--  insert here, which also keeps the admin console's feature list
--  data-driven rather than hardcoded in TypeScript.
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.app_features (
  key         TEXT PRIMARY KEY,
  label       TEXT NOT NULL,
  -- Groups the ranking in the console: 'core', 'library', 'community'.
  category    TEXT NOT NULL DEFAULT 'core',
  sort_order  INT  NOT NULL DEFAULT 100,
  is_active   BOOLEAN NOT NULL DEFAULT TRUE
);

INSERT INTO public.app_features (key, label, category, sort_order) VALUES
  ('home',              'Home feed',        'core',      10),
  ('chat',              'Chat',             'core',      20),
  ('watch',             'Watch',            'core',      30),
  ('marketplace',       'Marketplace',      'core',      40),
  ('events',            'Events',           'community', 50),
  ('churches',          'Churches',         'community', 60),
  ('prayer',            'Prayer',           'community', 70),
  ('quiz',              'Bible Quiz',       'community', 80),
  ('jobs',              'Jobs',             'community', 85),
  ('news',              'Advent News',      'community', 88),
  ('library_bible',     'Bible',            'library',   90),
  ('library_sabbath',   'Sabbath School',   'library',   100),
  ('library_hymnal',    'Hymnal',           'library',   110),
  ('library_egw',       'EGW Books',        'library',   120),
  ('library_music',     'Music',            'library',   130),
  ('search',            'Search',           'core',      140),
  ('profile',           'Profile',          'core',      150),
  ('premium',           'Premium',          'core',      160)
ON CONFLICT (key) DO NOTHING;

ALTER TABLE public.app_features ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS app_features_read ON public.app_features;
CREATE POLICY app_features_read ON public.app_features
  FOR SELECT TO authenticated USING (TRUE);
GRANT SELECT ON public.app_features TO authenticated;

-- =====================================================================
--  2. Sessions — how often people come back, and for how long
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.app_sessions (
  id           UUID PRIMARY KEY,
  user_id      UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  started_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- Bumped on every flush, so an abandoned session still has a sane
  -- length instead of running forever.
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  platform     TEXT,
  app_version  TEXT,
  os_version   TEXT
);

CREATE INDEX IF NOT EXISTS app_sessions_user_idx
  ON public.app_sessions (user_id, started_at DESC);
CREATE INDEX IF NOT EXISTS app_sessions_started_idx
  ON public.app_sessions (started_at DESC);

ALTER TABLE public.app_sessions ENABLE ROW LEVEL SECURITY;
-- No client policy at all: written by RPC, read by admin RPCs.

-- =====================================================================
--  3. Events — the raw signal
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.app_events (
  id          BIGSERIAL PRIMARY KEY,
  user_id     UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  session_id  UUID,
  feature     TEXT NOT NULL REFERENCES public.app_features(key),
  -- 'open'     — the user entered the feature
  -- 'engage'   — they did the thing the feature is for (sent a message,
  --              read a chapter, played a hymn). This is the one that
  --              separates "opened it once" from "actually uses it".
  -- 'complete' — finished a multi-step flow (a quiz round, a checkout).
  action      TEXT NOT NULL DEFAULT 'open'
                CHECK (action IN ('open', 'engage', 'complete')),
  screen      TEXT,
  platform    TEXT,
  app_version TEXT,
  meta        JSONB,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS app_events_created_idx
  ON public.app_events (created_at DESC);
CREATE INDEX IF NOT EXISTS app_events_feature_idx
  ON public.app_events (feature, created_at DESC);
CREATE INDEX IF NOT EXISTS app_events_user_day_idx
  ON public.app_events (user_id, created_at DESC);

ALTER TABLE public.app_events ENABLE ROW LEVEL SECURITY;
-- Again, no client policy. Write-only, via the RPC below.

-- =====================================================================
--  4. The ONLY client write path
--
--  Batched: the app queues events and flushes a handful at a time, so a
--  scroll through the feed is one round trip, not forty.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.track_app_events(
  p_session_id  UUID,
  p_platform    TEXT,
  p_app_version TEXT,
  p_os_version  TEXT,
  p_events      JSONB
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_user UUID := auth.uid();
  v_inserted INT := 0;
BEGIN
  IF v_user IS NULL THEN
    RETURN 0;
  END IF;
  IF p_events IS NULL OR jsonb_typeof(p_events) <> 'array' THEN
    RETURN 0;
  END IF;
  -- A client that sends 10,000 events in one call is either broken or
  -- hostile. Either way, take the first 100 and move on.
  IF jsonb_array_length(p_events) > 100 THEN
    p_events := (
      SELECT jsonb_agg(e) FROM (
        SELECT e FROM jsonb_array_elements(p_events) e LIMIT 100
      ) s
    );
  END IF;

  INSERT INTO public.app_sessions AS s
    (id, user_id, platform, app_version, os_version)
  VALUES
    (p_session_id, v_user, p_platform, p_app_version, p_os_version)
  ON CONFLICT (id) DO UPDATE
    SET last_seen_at = NOW(),
        -- An upgrade mid-session is real; keep the latest.
        app_version  = COALESCE(EXCLUDED.app_version, s.app_version)
  -- Someone else's session id is not yours to extend.
  WHERE s.user_id = v_user;

  INSERT INTO public.app_events
    (user_id, session_id, feature, action, screen, platform, app_version,
     meta, created_at)
  SELECT
    v_user,
    p_session_id,
    e ->> 'feature',
    COALESCE(e ->> 'action', 'open'),
    LEFT(e ->> 'screen', 120),
    p_platform,
    p_app_version,
    e -> 'meta',
    -- Trust the client's timestamp only if it is sane: offline events
    -- flush late and must keep their real time, but nobody gets to
    -- write into next week.
    COALESCE(
      LEAST((e ->> 'at')::TIMESTAMPTZ, NOW()),
      NOW()
    )
  FROM jsonb_array_elements(p_events) e
  -- Silently drop unknown feature keys rather than failing the batch:
  -- an older app build must never start erroring because a feature was
  -- renamed on the server.
  WHERE e ->> 'feature' IN (SELECT key FROM public.app_features);

  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  RETURN v_inserted;
END;
$function$;

REVOKE ALL ON FUNCTION
  public.track_app_events(UUID, TEXT, TEXT, TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION
  public.track_app_events(UUID, TEXT, TEXT, TEXT, JSONB) TO authenticated;

-- =====================================================================
--  5. Read side — one RPC per question the console asks
--
--  Every one is super-admin-only and returns plain numbers with plain
--  names, because the people reading them do not know what a join is.
-- =====================================================================

-- "Are people using the app?" — one row per day, ready to plot.
CREATE OR REPLACE FUNCTION public.admin_active_users_series(p_days INT DEFAULT 30)
RETURNS TABLE (
  day          DATE,
  active_users BIGINT,
  new_users    BIGINT,
  sessions     BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
BEGIN
  PERFORM public.assert_super_admin();
  p_days := LEAST(GREATEST(COALESCE(p_days, 30), 1), 365);
  RETURN QUERY
  WITH days AS (
    SELECT generate_series(
             (CURRENT_DATE - (p_days - 1))::DATE, CURRENT_DATE, '1 day'
           )::DATE AS day
  )
  SELECT
    d.day,
    (SELECT COUNT(DISTINCT e.user_id) FROM public.app_events e
      WHERE e.created_at::DATE = d.day),
    (SELECT COUNT(*) FROM public.profiles p
      WHERE p.created_at::DATE = d.day),
    (SELECT COUNT(*) FROM public.app_sessions s
      WHERE s.started_at::DATE = d.day)
  FROM days d
  ORDER BY d.day;
END;
$function$;

-- "Which features are actually used, and which are ignored?"
-- The founder's literal question, answered as a ranking.
CREATE OR REPLACE FUNCTION public.admin_feature_usage(p_days INT DEFAULT 30)
RETURNS TABLE (
  feature      TEXT,
  label        TEXT,
  category     TEXT,
  users        BIGINT,
  opens        BIGINT,
  engagements  BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
BEGIN
  PERFORM public.assert_super_admin();
  p_days := LEAST(GREATEST(COALESCE(p_days, 30), 1), 365);
  RETURN QUERY
  SELECT
    f.key,
    f.label,
    f.category,
    COUNT(DISTINCT e.user_id),
    COUNT(*) FILTER (WHERE e.action = 'open'),
    COUNT(*) FILTER (WHERE e.action = 'engage')
  FROM public.app_features f
  -- LEFT JOIN on purpose: a feature nobody touched must appear with a
  -- zero, because "which are ignored" is half the question and an
  -- absent row would silently answer only the other half.
  LEFT JOIN public.app_events e
    ON e.feature = f.key
   AND e.created_at > NOW() - MAKE_INTERVAL(days => p_days)
  WHERE f.is_active
  GROUP BY f.key, f.label, f.category, f.sort_order
  ORDER BY COUNT(DISTINCT e.user_id) DESC, f.sort_order;
END;
$function$;

-- "What are people running the app on?" — device + version spread,
-- which is what makes a crash report actionable later.
CREATE OR REPLACE FUNCTION public.admin_platform_breakdown(p_days INT DEFAULT 30)
RETURNS TABLE (
  platform    TEXT,
  app_version TEXT,
  users       BIGINT,
  sessions    BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
BEGIN
  PERFORM public.assert_super_admin();
  p_days := LEAST(GREATEST(COALESCE(p_days, 30), 1), 365);
  RETURN QUERY
  SELECT
    COALESCE(s.platform, 'unknown'),
    COALESCE(s.app_version, 'unknown'),
    COUNT(DISTINCT s.user_id),
    COUNT(*)
  FROM public.app_sessions s
  WHERE s.started_at > NOW() - MAKE_INTERVAL(days => p_days)
  GROUP BY 1, 2
  ORDER BY 3 DESC;
END;
$function$;

-- "Is the subscription working?" — real revenue-shaped numbers, now
-- that subscriptions actually exist.
CREATE OR REPLACE FUNCTION public.admin_premium_stats()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
DECLARE result JSONB;
BEGIN
  PERFORM public.assert_super_admin();
  SELECT jsonb_build_object(
    'premium_users',
      (SELECT COUNT(*) FROM public.profiles
        WHERE premium_until > NOW()),
    'active_subscriptions',
      (SELECT COUNT(*) FROM public.subscriptions
        WHERE status IN ('active', 'in_grace')),
    'cancelling',
      (SELECT COUNT(*) FROM public.subscriptions
        WHERE status = 'cancelled' AND current_period_end > NOW()),
    'expired',
      (SELECT COUNT(*) FROM public.subscriptions WHERE status = 'expired'),
    'refunded',
      (SELECT COUNT(*) FROM public.subscriptions
        WHERE status IN ('refunded', 'revoked')),
    'new_7d',
      (SELECT COUNT(*) FROM public.subscription_events
        WHERE event_type = 'purchased' AND created_at > NOW() - INTERVAL '7 days'),
    'lost_7d',
      (SELECT COUNT(*) FROM public.subscription_events
        WHERE event_type IN ('expired', 'refunded', 'revoked')
          AND created_at > NOW() - INTERVAL '7 days'),
    -- Conversion against people who actually still use the app, not
    -- against every account ever created. The second number flatters
    -- and misleads.
    'active_users_30d',
      (SELECT COUNT(*) FROM public.profiles
        WHERE last_active_at > NOW() - INTERVAL '30 days')
  ) INTO result;
  RETURN result;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_active_users_series(INT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_feature_usage(INT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_platform_breakdown(INT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_premium_stats() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_active_users_series(INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_feature_usage(INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_platform_breakdown(INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_premium_stats() TO authenticated;
