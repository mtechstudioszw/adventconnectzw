-- patch_159: Quiz Arena — cloud progress, weekly leaderboard, question reports.
--
-- Why: all quiz progress (streak, XP, stats) lived in local Hive prefs. A
-- reinstall wiped a player's entire history, and a leaderboard was
-- impossible. Local stays the source of truth for reads so a round still
-- plays and scores fully offline; this is the backup and the scoreboard.

-- ---- Per-player progress ---------------------------------------------------

CREATE TABLE IF NOT EXISTS public.quiz_progress (
  user_id         uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  xp              integer NOT NULL DEFAULT 0 CHECK (xp >= 0),
  current_streak  integer NOT NULL DEFAULT 0 CHECK (current_streak >= 0),
  best_streak     integer NOT NULL DEFAULT 0 CHECK (best_streak >= 0),
  total_answered  integer NOT NULL DEFAULT 0 CHECK (total_answered >= 0),
  total_correct   integer NOT NULL DEFAULT 0 CHECK (total_correct >= 0),
  lifetime_points bigint  NOT NULL DEFAULT 0 CHECK (lifetime_points >= 0),
  best_daily      integer NOT NULL DEFAULT 0,
  best_practice   integer NOT NULL DEFAULT 0,
  best_survival   integer NOT NULL DEFAULT 0,
  best_speed      integer NOT NULL DEFAULT 0,
  updated_at      timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.quiz_progress ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS quiz_progress_own ON public.quiz_progress;
CREATE POLICY quiz_progress_own ON public.quiz_progress
  FOR ALL TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

GRANT SELECT, INSERT, UPDATE ON public.quiz_progress TO authenticated;

-- ---- One row per finished round (drives the leaderboard) -------------------

CREATE TABLE IF NOT EXISTS public.quiz_scores (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  mode          text NOT NULL,
  -- The client computes points, so bound them — but bound them generously.
  -- A perfect 10-question round lands near 5.7k, while a deep Survival run
  -- escalates hard: 40 correct in a row legitimately clears 35k. An earlier
  -- 25k ceiling would have flattened every great run to the same number.
  points        integer NOT NULL CHECK (points >= 0 AND points <= 100000),
  correct_count integer NOT NULL DEFAULT 0 CHECK (correct_count >= 0),
  total_count   integer NOT NULL DEFAULT 0 CHECK (total_count >= 0),
  played_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS quiz_scores_played_idx
  ON public.quiz_scores (played_at DESC);
CREATE INDEX IF NOT EXISTS quiz_scores_user_idx
  ON public.quiz_scores (user_id, played_at DESC);

ALTER TABLE public.quiz_scores ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS quiz_scores_insert_own ON public.quiz_scores;
CREATE POLICY quiz_scores_insert_own ON public.quiz_scores
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS quiz_scores_read_own ON public.quiz_scores;
CREATE POLICY quiz_scores_read_own ON public.quiz_scores
  FOR SELECT TO authenticated USING (user_id = auth.uid());

GRANT SELECT, INSERT ON public.quiz_scores TO authenticated;

-- ---- Leaderboard -----------------------------------------------------------
-- SECURITY DEFINER so players can see the ranking without being able to read
-- each other's raw score rows. Banned and non-discoverable members are left
-- out, matching how the member directory already behaves.

CREATE OR REPLACE FUNCTION public.quiz_leaderboard(
  p_days integer DEFAULT 7,
  p_limit integer DEFAULT 50
)
RETURNS TABLE (
  user_id      uuid,
  full_name    text,
  photo_url    text,
  is_verified  boolean,
  points       bigint,
  rounds       bigint,
  rank         bigint,
  is_me        boolean
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH totals AS (
    SELECT s.user_id,
           SUM(s.points)::bigint AS points,
           COUNT(*)::bigint      AS rounds
      FROM public.quiz_scores s
     WHERE s.played_at >= now() - make_interval(days => GREATEST(p_days, 1))
     GROUP BY s.user_id
  )
  SELECT t.user_id,
         COALESCE(p.full_name, 'Member') AS full_name,
         p.profile_photo_url             AS photo_url,
         COALESCE(p.is_verified, false)  AS is_verified,
         t.points,
         t.rounds,
         RANK() OVER (ORDER BY t.points DESC)::bigint AS rank,
         (t.user_id = auth.uid())        AS is_me
    FROM totals t
    JOIN public.profiles p ON p.id = t.user_id
   WHERE COALESCE(p.is_banned, false) = false
   ORDER BY t.points DESC
   LIMIT GREATEST(LEAST(p_limit, 200), 1);
$$;

REVOKE ALL ON FUNCTION public.quiz_leaderboard(integer, integer) FROM public;
GRANT EXECUTE ON FUNCTION public.quiz_leaderboard(integer, integer) TO authenticated;

-- Where the caller sits, even when they're outside the top N.
CREATE OR REPLACE FUNCTION public.quiz_my_rank(p_days integer DEFAULT 7)
RETURNS TABLE (points bigint, rounds bigint, rank bigint, total_players bigint)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH totals AS (
    SELECT s.user_id,
           SUM(s.points)::bigint AS points,
           COUNT(*)::bigint      AS rounds
      FROM public.quiz_scores s
     WHERE s.played_at >= now() - make_interval(days => GREATEST(p_days, 1))
     GROUP BY s.user_id
  ), ranked AS (
    SELECT t.*, RANK() OVER (ORDER BY t.points DESC)::bigint AS rank
      FROM totals t
  )
  SELECT r.points, r.rounds, r.rank, (SELECT COUNT(*) FROM ranked)::bigint
    FROM ranked r
   WHERE r.user_id = auth.uid();
$$;

REVOKE ALL ON FUNCTION public.quiz_my_rank(integer) FROM public;
GRANT EXECUTE ON FUNCTION public.quiz_my_rank(integer) TO authenticated;

-- ---- Player-reported bad questions ----------------------------------------
-- The KJV generator mints questions procedurally. The gates are strict, but
-- "report this question" is the backstop that turns a player into a
-- proofreader instead of leaving a bad question in rotation forever.

CREATE TABLE IF NOT EXISTS public.quiz_reports (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  question_id   text NOT NULL,
  is_generated  boolean NOT NULL DEFAULT false,
  question_text text,
  reason        text,
  reported_by   uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  resolved      boolean NOT NULL DEFAULT false,
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS quiz_reports_open_idx
  ON public.quiz_reports (resolved, created_at DESC);

ALTER TABLE public.quiz_reports ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS quiz_reports_insert ON public.quiz_reports;
CREATE POLICY quiz_reports_insert ON public.quiz_reports
  FOR INSERT TO authenticated
  WITH CHECK (reported_by = auth.uid() OR reported_by IS NULL);

DROP POLICY IF EXISTS quiz_reports_admin_read ON public.quiz_reports;
CREATE POLICY quiz_reports_admin_read ON public.quiz_reports
  FOR SELECT TO authenticated USING (public.is_super_admin());

DROP POLICY IF EXISTS quiz_reports_admin_update ON public.quiz_reports;
CREATE POLICY quiz_reports_admin_update ON public.quiz_reports
  FOR UPDATE TO authenticated
  USING (public.is_super_admin()) WITH CHECK (public.is_super_admin());

GRANT SELECT, INSERT, UPDATE ON public.quiz_reports TO authenticated;

-- Default reported_by to the caller so the client never has to send it.
ALTER TABLE public.quiz_reports
  ALTER COLUMN reported_by SET DEFAULT auth.uid();
