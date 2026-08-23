-- =====================================================================
--  PATCH 228 — Quiz shows a stale profile photo, and never a gold tick
--
--  Reported 23 Aug 2026: "that profile picture still appears in quiz game
--  even after you changed it, especially in leaderboard".
--
--  ## Bug 1 — the photo is a snapshot, and it wins
--
--  Four quiz RPCs resolve a player's avatar as:
--
--      COALESCE(q.photo_url, p.profile_photo_url)
--
--  `quiz_profiles.photo_url` is written once, when the quiz profile is
--  created (quiz_profile_ensure), and never refreshed afterwards. Putting
--  it FIRST means the snapshot always wins over the live profile — so the
--  quiz is the one place in the app that is guaranteed to show the photo
--  you had when you first opened the arena, permanently.
--
--  It bites hardest on Google sign-up, which is how the report surfaced:
--  Google supplies a default avatar, that avatar is what gets snapshotted,
--  and changing your picture afterwards updates every screen in the app
--  except this one.
--
--  The arguments are simply the wrong way round. `profiles` is the live
--  record; the quiz snapshot is a fallback for a profile row that has no
--  photo at all. Swapped, not deleted — the snapshot still covers that case.
--
--  ## Bug 2 — the gold tick was reading a column nobody uses
--
--  The same RPCs report verification as `COALESCE(p.is_verified, false)`.
--  In this database `is_verified` is true for ZERO members, and every one
--  of the 7 verified accounts carries `is_verified_admin` instead. So the
--  quiz has never rendered a gold tick for anyone, on any screen.
--
--  The rest of the app already reads BOTH — see Post.fromJson,
--  MemberDirectoryEntry.fromJson, PublicUserProfile.showsVerifiedTick.
--  These four were the stragglers. (CLAUDE.md's standing warning applies:
--  is_verified_admin is the column patch_134 added and patch_188 had to
--  re-secure; anything reading "is this member verified" has to read both.)
--
--  Both fixes are pure SELECT-list changes. No schema change, no data
--  change, no signature change.
-- =====================================================================

-- ---- quiz_leaderboard_weekly -------------------------------------
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
         (COALESCE(p.is_verified, false) OR COALESCE(p.is_verified_admin, false)),
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

-- ---- quiz_match_invites ------------------------------------------
CREATE OR REPLACE FUNCTION public.quiz_match_invites()
 RETURNS TABLE(match_id uuid, from_id uuid, from_name text, from_photo text, created_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT m.id, m.player_a, q.display_name,
         COALESCE(p.profile_photo_url, q.photo_url), m.created_at
    FROM public.quiz_matches m
    JOIN public.quiz_profiles q ON q.user_id = m.player_a
    JOIN public.profiles p      ON p.id      = m.player_a
   WHERE m.player_b = auth.uid()
     AND m.status = 'invited'
     AND m.created_at > now() - interval '5 minutes'
   ORDER BY m.created_at DESC;
$function$;

-- ---- quiz_match_view ---------------------------------------------
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
               'verified', (COALESCE(p.is_verified, false) OR COALESCE(p.is_verified_admin, false)))
        FROM public.quiz_profiles q
        JOIN public.profiles p ON p.id = q.user_id
       WHERE q.user_id = CASE WHEN p_match.player_a = auth.uid()
                              THEN p_match.player_b ELSE p_match.player_a END
    )
  );
$function$;

-- ---- quiz_players ------------------------------------------------
CREATE OR REPLACE FUNCTION public.quiz_players(p_query text DEFAULT NULL::text, p_online uuid[] DEFAULT NULL::uuid[], p_limit integer DEFAULT 40)
 RETURNS TABLE(user_id uuid, full_name text, photo_url text, is_verified boolean, is_online boolean, week_points bigint)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT q.user_id,
         q.display_name,
         COALESCE(p.profile_photo_url, q.photo_url),
         (COALESCE(p.is_verified, false) OR COALESCE(p.is_verified_admin, false)),
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

