-- ============================================================================
--  patch_281 — church admins no longer show the gold tick
--  STATUS: APPLIED to the live database 29 Oct 2026.
-- ============================================================================
--
--  Owner, 28 Oct 2026: "remove golden tick from church admins". The gold
--  tick is becoming a paid badge that also needs an ID check (decided the
--  same day; built with Premium later). Until then it shows only for
--  profiles.is_verified.
--
--  is_verified_admin is NOT touched: it still records an approved church
--  admin and still grants their church-admin powers. Only these five
--  functions, which reported it AS the tick, change — each is the live
--  definition with "is_verified OR is_verified_admin" reduced to
--  is_verified, nothing else. The app stopped combining the two in the
--  same commit.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.list_follows(target uuid, direction text)
 RETURNS TABLE(user_id uuid, full_name text, username text, profile_photo_url text, is_verified boolean, followed_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT p.id, p.full_name, p.username, p.profile_photo_url,
         COALESCE(p.is_verified, false), f.created_at
  FROM public.follows f
  JOIN public.profiles p
    ON p.id = CASE WHEN direction = 'followers' THEN f.follower_id ELSE f.followee_id END
  WHERE public.can_see_profile_content(target)
    AND f.status = 'active'
    AND CASE WHEN direction = 'followers' THEN f.followee_id ELSE f.follower_id END = target
    AND NOT public.is_blocked_by(p.id)
  ORDER BY f.created_at DESC
  LIMIT 500;
$function$;

CREATE OR REPLACE FUNCTION public.my_friends_detailed()
 RETURNS TABLE(friendship_id text, user_id text, full_name text, photo_url text, church_name text, is_verified boolean, friends_since timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
  SELECT
    f.id::text,
    other.id::text,
    COALESCE(NULLIF(btrim(other.full_name), ''), 'Member'),
    other.profile_photo_url,
    c.name,
    COALESCE(other.is_verified, FALSE),
    f.created_at
  FROM public.friendships f
  -- The friend is whichever end of the pair isn't the caller.
  JOIN public.profiles other
    ON other.id = CASE
                    WHEN f.requester_id = auth.uid() THEN f.addressee_id
                    ELSE f.requester_id
                  END
  LEFT JOIN public.churches c ON c.id = other.church_id
  WHERE f.status = 'accepted'
    AND (f.requester_id = auth.uid() OR f.addressee_id = auth.uid())
    AND COALESCE(other.is_banned, FALSE) = FALSE
  ORDER BY COALESCE(NULLIF(btrim(other.full_name), ''), 'Member');
$function$;

CREATE OR REPLACE FUNCTION public.quiz_leaderboard_weekly(p_limit integer DEFAULT 50)
 RETURNS TABLE(user_id uuid, full_name text, photo_url text, is_verified boolean, points bigint, rounds bigint, rank bigint, is_me boolean)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH totals AS (
    SELECT s.user_id,
           SUM(s.points)::bigint AS points,
           COUNT(*)::bigint      AS rounds
      FROM public.quiz_scores s
     WHERE s.played_at >= public.quiz_week_start()
     GROUP BY s.user_id
  )
  SELECT t.user_id,
         q.display_name,
         COALESCE(p.profile_photo_url, q.photo_url),
         COALESCE(p.is_verified, false),
         t.points,
         t.rounds,
         RANK() OVER (ORDER BY t.points DESC)::bigint,
         (t.user_id = auth.uid())
    FROM totals t
    JOIN public.quiz_profiles q ON q.user_id = t.user_id
    JOIN public.profiles p      ON p.id      = t.user_id
   WHERE COALESCE(p.is_banned, false) = false
   ORDER BY t.points DESC
   LIMIT GREATEST(LEAST(p_limit, 200), 1);
$function$;

CREATE OR REPLACE FUNCTION public.quiz_match_view(p_match quiz_matches)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT jsonb_build_object(
    'id',                   p_match.id,
    'status',               p_match.status,
    'questions',            p_match.questions,
    'question_count',       p_match.question_count,
    'seconds_per_question', p_match.seconds_per_question,
    'current_index',        p_match.current_index,
    'question_started_at',  p_match.question_started_at,
    'resolved_at',          p_match.resolved_at,
    'server_now',           now(),
    'player_a',             p_match.player_a,
    'player_b',             p_match.player_b,
    -- Ready check.
    'a_ready',              p_match.a_ready,
    'b_ready',              p_match.b_ready,
    'ready_deadline',       p_match.ready_deadline,
    'i_am_ready', CASE WHEN p_match.player_a = auth.uid()
                       THEN p_match.a_ready ELSE p_match.b_ready END,
    -- Scores. The caller's own number is always real; the opponent's is
    -- withheld until the match is over. `scores_hidden` exists so the UI
    -- can show a dash — a NULL parsed as 0 reads as a genuine score of
    -- zero, which is worse than showing nothing.
    'scores_hidden',        (p_match.status <> 'complete'),
    'a_points', CASE WHEN p_match.status = 'complete'
                       OR p_match.player_a = auth.uid()
                     THEN p_match.a_points END,
    'b_points', CASE WHEN p_match.status = 'complete'
                       OR p_match.player_b = auth.uid()
                     THEN p_match.b_points END,
    'a_correct', CASE WHEN p_match.status = 'complete'
                        OR p_match.player_a = auth.uid()
                      THEN p_match.a_correct END,
    'b_correct', CASE WHEN p_match.status = 'complete'
                        OR p_match.player_b = auth.uid()
                      THEN p_match.b_correct END,
    'a_answered_index',     p_match.a_answered_index,
    'b_answered_index',     p_match.b_answered_index,
    'winner_id',            p_match.winner_id,
    'forfeited_by',         p_match.forfeited_by,
    'revealed_index', (
      SELECT CASE WHEN p_match.resolved_at IS NULL THEN NULL
                  ELSE (k.answer_key -> p_match.current_index)::text::int END
        FROM public.quiz_match_keys k WHERE k.match_id = p_match.id
    ),
    'my_choice', (
      SELECT a.chosen_index FROM public.quiz_match_answers a
       WHERE a.match_id = p_match.id
         AND a.player_id = auth.uid()
         AND a.question_index = p_match.current_index
    ),
    'opponent', (
      SELECT jsonb_build_object(
               'user_id', q.user_id,
               'name',    q.display_name,
               'photo',   COALESCE(p.profile_photo_url, q.photo_url),
               'verified', COALESCE(p.is_verified, false))
        FROM public.quiz_profiles q
        JOIN public.profiles p ON p.id = q.user_id
       WHERE q.user_id = CASE WHEN p_match.player_a = auth.uid()
                              THEN p_match.player_b ELSE p_match.player_a END
    )
  );
$function$;

CREATE OR REPLACE FUNCTION public.quiz_players(p_query text DEFAULT NULL::text, p_online uuid[] DEFAULT NULL::uuid[], p_limit integer DEFAULT 40)
 RETURNS TABLE(user_id uuid, full_name text, photo_url text, is_verified boolean, is_online boolean, week_points bigint)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT q.user_id,
         q.display_name,
         COALESCE(p.profile_photo_url, q.photo_url),
         COALESCE(p.is_verified, false),
         (p_online IS NOT NULL AND q.user_id = ANY (p_online)),
         COALESCE((
           SELECT SUM(s.points)::bigint FROM public.quiz_scores s
            WHERE s.user_id = q.user_id
              AND s.played_at >= public.quiz_week_start()
         ), 0)
    FROM public.quiz_profiles q
    JOIN public.profiles p ON p.id = q.user_id
   WHERE q.user_id <> auth.uid()
     AND COALESCE(p.is_banned, false) = false
     AND (p_query IS NULL OR btrim(p_query) = ''
          OR q.display_name ILIKE '%' || btrim(p_query) || '%')
   -- Online first: a live match with someone who isn't there is the whole
   -- failure mode this feature has to avoid.
   ORDER BY (p_online IS NOT NULL AND q.user_id = ANY (p_online)) DESC,
            6 DESC, 2
   LIMIT GREATEST(LEAST(p_limit, 100), 1);
$function$;

COMMIT;
