-- patch_308 — Live quiz rooms: show your answers at the end (3 Nov 2026). APPLIED 3 Nov 2026 (verified: hidden mid-game, full list at the end).
--
-- Owner: "at the end of the live game put to show the answers u answered".
-- quiz_room_view gains a 'review' list — for each question, the right
-- answer, what you chose and what it scored — ONLY once the room is
-- complete, so the answer key still never reaches a phone mid-game.
-- Everything else in the view is unchanged from patch_306.

CREATE OR REPLACE FUNCTION public.quiz_room_view(p_room public.quiz_rooms)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT jsonb_build_object(
    'id',                   p_room.id,
    'code',                 p_room.code,
    'status',               p_room.status,
    'host_id',              p_room.host_id,
    'questions',            p_room.questions,
    'question_count',       p_room.question_count,
    'seconds_per_question', p_room.seconds_per_question,
    'current_index',        p_room.current_index,
    'question_started_at',  p_room.question_started_at,
    'resolved_at',          p_room.resolved_at,
    'server_now',           now(),
    'revealed_index', (
      SELECT CASE WHEN p_room.resolved_at IS NULL THEN NULL
                  ELSE (k.answer_key -> p_room.current_index)::text::int END
        FROM public.quiz_room_keys k WHERE k.room_id = p_room.id
    ),
    'my_choice', (
      SELECT a.chosen_index FROM public.quiz_room_answers a
       WHERE a.room_id = p_room.id
         AND a.user_id = auth.uid()
         AND a.question_index = p_room.current_index
    ),
    -- patch_308: once the game is over, what I answered on every
    -- question and what was right. Never before — the key must not
    -- reach a phone while the game can still be played.
    'review', CASE WHEN p_room.status = 'complete' THEN (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'index',         g.i,
               'correct_index', (k.answer_key -> g.i)::text::int,
               'my_choice',     a.chosen_index,
               'correct',       COALESCE(a.correct, false),
               'points',        COALESCE(a.points, 0)
             ) ORDER BY g.i), '[]'::jsonb)
        FROM generate_series(0, p_room.question_count - 1) AS g(i)
        LEFT JOIN public.quiz_room_keys k ON k.room_id = p_room.id
        LEFT JOIN public.quiz_room_answers a
               ON a.room_id = p_room.id
              AND a.user_id = auth.uid()
              AND a.question_index = g.i
    ) END,
    'players', COALESCE((
      SELECT jsonb_agg(x.j ORDER BY x.shown DESC, x.joined_at)
        FROM (
          SELECT rp.joined_at,
                 -- Points as of the last REVEALED question (see header).
                 rp.points - CASE
                   WHEN p_room.status = 'active' AND p_room.resolved_at IS NULL
                   THEN COALESCE(cur.points, 0) ELSE 0 END AS shown,
                 jsonb_build_object(
                   'user_id',  rp.user_id,
                   'name',     COALESCE(NULLIF(btrim(q.display_name), ''),
                                        NULLIF(btrim(p.full_name), ''), 'Player'),
                   'photo',    COALESCE(p.profile_photo_url, q.photo_url),
                   'verified', COALESCE(p.is_verified, false),
                   'points',   rp.points - CASE
                     WHEN p_room.status = 'active' AND p_room.resolved_at IS NULL
                     THEN COALESCE(cur.points, 0) ELSE 0 END,
                   'correct',  rp.correct - CASE
                     WHEN p_room.status = 'active' AND p_room.resolved_at IS NULL
                          AND COALESCE(cur.correct, false) THEN 1 ELSE 0 END,
                   'answered', rp.answered_index >= p_room.current_index,
                   -- Only after the reveal: what this question earned.
                   'last_points', CASE WHEN p_room.resolved_at IS NOT NULL
                                       THEN COALESCE(cur.points, 0) END,
                   'last_correct', CASE WHEN p_room.resolved_at IS NOT NULL
                                        THEN COALESCE(cur.correct, false) END,
                   'left',     rp.left_at IS NOT NULL,
                   'is_me',    rp.user_id = auth.uid()
                 ) AS j
            FROM public.quiz_room_players rp
            JOIN public.profiles p ON p.id = rp.user_id
            LEFT JOIN public.quiz_profiles q ON q.user_id = rp.user_id
            LEFT JOIN public.quiz_room_answers cur
                   ON cur.room_id = rp.room_id
                  AND cur.user_id = rp.user_id
                  AND cur.question_index = p_room.current_index
           WHERE rp.room_id = p_room.id
             -- Someone who walked out of the LOBBY is simply gone; someone
             -- who dropped mid-game stays on the board, marked as left.
             AND NOT (p_room.status = 'lobby' AND rp.left_at IS NOT NULL)
        ) x
    ), '[]'::jsonb)
  );
$$;
