-- patch_183: Quiz Arena — quiz profiles, live head-to-head matches, and a
-- weekly leaderboard that RESETS instead of rolling.
--
-- Founder decisions this implements (3 Aug 2026):
--   1. Pure LIVE head-to-head. The existing async `quiz_challenges` system
--      stays exactly as it is — this is a layer beside it, not a
--      replacement.
--   2. A quiz profile is optional for solo play and REQUIRED to appear on
--      the leaderboard or to play a head-to-head.
--   3. The leaderboard ranks weekly points that RESET on a fixed boundary,
--      not a rolling window and not Elo.
--   4. Challenge notifications stay suppressed during Sabbath quiet hours —
--      which is the default for any non-essential type, so `quiz_challenge`
--      is deliberately NOT added to `is_essential_notification`.
--
-- The three rules that shape the schema:
--
--   * **The server owns the questions.** A live match's questions are
--     drawn here, from `quiz_questions`, NOT supplied by the client the way
--     an async challenge's are. If the player who opened the match had
--     generated the set, they would know every answer before it started.
--     This is the one place the KJV runtime generator cannot be used.
--   * **The answer key never leaves the database.** It lives in its own
--     table with RLS on and NO policies and NO grants, so `authenticated`
--     cannot read it by any route; only the SECURITY DEFINER functions
--     below touch it. A column on `quiz_matches` would NOT have been safe:
--     a column-level REVOKE is silently ignored when the grant is
--     table-level, and clients need SELECT on that table for Realtime.
--   * **The clock is server-authoritative.** Every client counts down from
--     `question_started_at`, which is stamped here. Nothing is timed from
--     packet arrival, or a player on a slower connection loses every race.

-- ---- Quiz profiles ---------------------------------------------------------
-- The competitive identity. Separate from `profiles` on purpose: a member
-- can play the whole quiz anonymously, and only opts in to a public name
-- when they want to be ranked or challenged.

CREATE TABLE IF NOT EXISTS public.quiz_profiles (
  user_id      uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name text NOT NULL
                 CHECK (btrim(display_name) <> ''
                        AND char_length(display_name) BETWEEN 2 AND 24),
  photo_url    text,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

-- Case-insensitive uniqueness: two "Tanatswa"s on a leaderboard is a bug
-- report waiting to happen.
CREATE UNIQUE INDEX IF NOT EXISTS quiz_profiles_name_key
  ON public.quiz_profiles (lower(btrim(display_name)));

ALTER TABLE public.quiz_profiles ENABLE ROW LEVEL SECURITY;

-- Public read: a leaderboard and an opponent card are both public by nature.
DROP POLICY IF EXISTS quiz_profiles_read ON public.quiz_profiles;
CREATE POLICY quiz_profiles_read ON public.quiz_profiles
  FOR SELECT TO authenticated USING (true);

-- Same reasoning as quiz_matches below: strip the inherited write grants
-- so only the RPC can change a name.
REVOKE ALL ON public.quiz_profiles FROM authenticated, anon;
GRANT SELECT ON public.quiz_profiles TO authenticated;
-- No INSERT/UPDATE policy: writes go through the RPC so the name can be
-- trimmed, length-checked and collision-checked in one place.

CREATE OR REPLACE FUNCTION public.quiz_profile_upsert(
  p_display_name text,
  p_photo_url    text DEFAULT NULL
)
RETURNS public.quiz_profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_name text := btrim(COALESCE(p_display_name, ''));
  v_row  public.quiz_profiles;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not signed in';
  END IF;
  IF char_length(v_name) < 2 OR char_length(v_name) > 24 THEN
    RAISE EXCEPTION 'Name must be 2 to 24 characters';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.quiz_profiles q
     WHERE lower(btrim(q.display_name)) = lower(v_name)
       AND q.user_id <> auth.uid()
  ) THEN
    RAISE EXCEPTION 'That name is taken';
  END IF;

  INSERT INTO public.quiz_profiles (user_id, display_name, photo_url)
  VALUES (auth.uid(), v_name, p_photo_url)
  ON CONFLICT (user_id) DO UPDATE
    SET display_name = EXCLUDED.display_name,
        photo_url    = COALESCE(EXCLUDED.photo_url, quiz_profiles.photo_url),
        updated_at   = now()
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.quiz_profile_upsert(text, text) FROM public;
GRANT EXECUTE ON FUNCTION public.quiz_profile_upsert(text, text) TO authenticated;

-- ---- The weekly boundary ---------------------------------------------------
-- Sunday 00:00 in Harare. Deliberately NOT `date_trunc('week')`, which is
-- Monday and UTC — a Zimbabwean member's week would have reset at 02:00 on
-- Monday morning, mid-week by their reckoning, and the Sabbath would have
-- been split across two leaderboards.

CREATE OR REPLACE FUNCTION public.quiz_week_start()
RETURNS timestamptz
LANGUAGE sql
STABLE
AS $$
  SELECT ((date_trunc('week', (now() AT TIME ZONE 'Africa/Harare') + interval '1 day')
           - interval '1 day') AT TIME ZONE 'Africa/Harare');
$$;

GRANT EXECUTE ON FUNCTION public.quiz_week_start() TO authenticated;

-- ---- Weekly leaderboard (resetting) ----------------------------------------
-- `quiz_leaderboard(p_days, p_limit)` is left in place — it still backs
-- anything asking for a rolling window — but the arena now calls these.
--
-- Ranked under the QUIZ identity, and only for players who have one. That is
-- the founder's "required for leaderboard" call: the board is a public,
-- named thing, so appearing on it is opt-in.

CREATE OR REPLACE FUNCTION public.quiz_leaderboard_weekly(
  p_limit integer DEFAULT 50
)
RETURNS TABLE (
  user_id     uuid,
  full_name   text,
  photo_url   text,
  is_verified boolean,
  points      bigint,
  rounds      bigint,
  rank        bigint,
  is_me       boolean
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
     WHERE s.played_at >= public.quiz_week_start()
     GROUP BY s.user_id
  )
  SELECT t.user_id,
         q.display_name,
         COALESCE(q.photo_url, p.profile_photo_url),
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
$$;

REVOKE ALL ON FUNCTION public.quiz_leaderboard_weekly(integer) FROM public;
GRANT EXECUTE ON FUNCTION public.quiz_leaderboard_weekly(integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.quiz_my_rank_weekly()
RETURNS TABLE (
  points        bigint,
  rounds        bigint,
  rank          bigint,
  total_players bigint,
  week_start    timestamptz,
  week_end      timestamptz,
  has_profile   boolean
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
     WHERE s.played_at >= public.quiz_week_start()
     GROUP BY s.user_id
  ), ranked AS (
    SELECT t.*, RANK() OVER (ORDER BY t.points DESC)::bigint AS rank
      FROM totals t
      JOIN public.quiz_profiles q ON q.user_id = t.user_id
  )
  SELECT COALESCE(r.points, 0),
         COALESCE(r.rounds, 0),
         COALESCE(r.rank, 0),
         (SELECT COUNT(*) FROM ranked)::bigint,
         public.quiz_week_start(),
         public.quiz_week_start() + interval '7 days',
         EXISTS (SELECT 1 FROM public.quiz_profiles q2 WHERE q2.user_id = auth.uid())
    FROM (SELECT 1) one
    LEFT JOIN ranked r ON r.user_id = auth.uid();
$$;

REVOKE ALL ON FUNCTION public.quiz_my_rank_weekly() FROM public;
GRANT EXECUTE ON FUNCTION public.quiz_my_rank_weekly() TO authenticated;

-- ---- Live matches ----------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.quiz_matches (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  player_a             uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  player_b             uuid REFERENCES auth.users(id) ON DELETE CASCADE,

  -- open   : sitting in the matchmaking queue, anyone may join
  -- invited: aimed at one specific person, only they may accept
  -- active : both present, questions running
  -- complete / cancelled
  status               text NOT NULL DEFAULT 'open'
                         CHECK (status IN ('open','invited','active','complete','cancelled')),

  -- The question payload as the CLIENTS see it: `correct_index` is stripped
  -- to -1 on the way in. The real key is in quiz_match_keys.
  questions            jsonb NOT NULL,
  question_count       integer NOT NULL,
  seconds_per_question integer NOT NULL DEFAULT 15,

  current_index        integer NOT NULL DEFAULT 0,
  -- The clock every client counts down from. Never a client timestamp.
  question_started_at  timestamptz,
  -- Set the moment a question closes (both answered, or the clock ran out),
  -- so both screens reveal together and the next question starts on the
  -- server's schedule rather than whichever client asks first.
  resolved_at          timestamptz,

  a_points             integer NOT NULL DEFAULT 0,
  b_points             integer NOT NULL DEFAULT 0,
  a_correct            integer NOT NULL DEFAULT 0,
  b_correct            integer NOT NULL DEFAULT 0,
  a_combo              integer NOT NULL DEFAULT 0,
  b_combo              integer NOT NULL DEFAULT 0,
  -- Highest question index each player has locked an answer for, minus one
  -- when they have not answered the current one. Safe to expose: it says
  -- THAT they answered, never WHAT.
  a_answered_index     integer NOT NULL DEFAULT -1,
  b_answered_index     integer NOT NULL DEFAULT -1,

  a_last_seen          timestamptz NOT NULL DEFAULT now(),
  b_last_seen          timestamptz,

  winner_id            uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  forfeited_by         uuid REFERENCES auth.users(id) ON DELETE SET NULL,

  created_at           timestamptz NOT NULL DEFAULT now(),
  started_at           timestamptz,
  completed_at         timestamptz,

  CONSTRAINT quiz_matches_not_self CHECK (player_b IS NULL OR player_a <> player_b)
);

CREATE INDEX IF NOT EXISTS quiz_matches_queue_idx
  ON public.quiz_matches (status, created_at)
  WHERE status = 'open';
CREATE INDEX IF NOT EXISTS quiz_matches_player_a_idx
  ON public.quiz_matches (player_a, status, created_at DESC);
CREATE INDEX IF NOT EXISTS quiz_matches_player_b_idx
  ON public.quiz_matches (player_b, status, created_at DESC);

ALTER TABLE public.quiz_matches ENABLE ROW LEVEL SECURITY;

-- Participants read their own match. This is also what Realtime evaluates
-- when a client subscribes to postgres_changes on this table.
DROP POLICY IF EXISTS quiz_matches_read ON public.quiz_matches;
CREATE POLICY quiz_matches_read ON public.quiz_matches
  FOR SELECT TO authenticated
  USING (player_a = auth.uid() OR player_b = auth.uid());

-- No INSERT and no UPDATE policy, deliberately. Every mutation is an RPC:
-- RLS cannot restrict which columns an UPDATE touches, and with update
-- rights either player could simply write their own score.
--
-- The REVOKE is not redundant. This database hands `authenticated` a
-- table-level GRANT ALL on new public tables, so the role arrives holding
-- INSERT/UPDATE/DELETE and only the absence of a policy stops it — one
-- carelessly-added policy later would open scores to self-editing. Taking
-- the privilege away means there is nothing for a future policy to unlock.
REVOKE ALL ON public.quiz_matches FROM authenticated, anon;
GRANT SELECT ON public.quiz_matches TO authenticated;

-- The answer key. RLS on, zero policies, zero grants — unreachable from a
-- client session by design. Only the SECURITY DEFINER functions below read it.
CREATE TABLE IF NOT EXISTS public.quiz_match_keys (
  match_id   uuid PRIMARY KEY REFERENCES public.quiz_matches(id) ON DELETE CASCADE,
  answer_key jsonb NOT NULL
);
ALTER TABLE public.quiz_match_keys ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.quiz_match_keys FROM authenticated, anon;

-- One row per answer. Also server-only: an opponent who could read this
-- would learn whether their own answer was right by watching the other
-- player's `correct` flag land before the reveal.
CREATE TABLE IF NOT EXISTS public.quiz_match_answers (
  match_id       uuid NOT NULL REFERENCES public.quiz_matches(id) ON DELETE CASCADE,
  player_id      uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  question_index integer NOT NULL,
  chosen_index   integer NOT NULL,      -- -1 = the clock took it
  correct        boolean NOT NULL,
  points         integer NOT NULL DEFAULT 0,
  elapsed_ms     integer NOT NULL DEFAULT 0,
  answered_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (match_id, player_id, question_index)
);
ALTER TABLE public.quiz_match_answers ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.quiz_match_answers FROM authenticated, anon;

-- Realtime: participants get pushed every state change on their match.
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.quiz_matches;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN undefined_object THEN NULL;
END;
$$;

-- ---- Scoring, mirrored from QuizScoring in lib/models/quiz_round.dart -----
-- Kept identical so a live round scores the way solo does. If one moves,
-- move the other.

CREATE OR REPLACE FUNCTION public.quiz_multiplier_for(p_combo integer)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
           WHEN p_combo >= 8 THEN 4
           WHEN p_combo >= 5 THEN 3
           WHEN p_combo >= 3 THEN 2
           ELSE 1
         END;
$$;

CREATE OR REPLACE FUNCTION public.quiz_points_for(
  p_correct   boolean,
  p_remaining numeric,   -- fraction of the question clock still left, 0..1
  p_combo     integer    -- streak length INCLUDING this answer
)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
           WHEN NOT p_correct THEN 0
           ELSE ((100 + round(100 * GREATEST(LEAST(p_remaining, 1), 0)))
                 * public.quiz_multiplier_for(p_combo))::integer
         END;
$$;

-- ---- Building a match ------------------------------------------------------

-- Draws the questions AND the key. Returns both; the caller stores them
-- apart. Server-side selection is what stops the player who opened the
-- match from knowing the answers.
CREATE OR REPLACE FUNCTION public.quiz_match_draw(p_count integer DEFAULT 7)
RETURNS TABLE (public_questions jsonb, answer_key jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rows jsonb;
BEGIN
  SELECT COALESCE(jsonb_agg(to_jsonb(q) ORDER BY q.ord), '[]'::jsonb)
    INTO v_rows
    FROM (
      SELECT row_number() OVER () AS ord,
             x.id, x.question, x.options, x.correct_index,
             x.category, x.difficulty, x.explanation, x.reference
        FROM (
          SELECT * FROM public.quiz_questions
           WHERE COALESCE(is_published, true)
             AND jsonb_array_length(options) >= 2
           ORDER BY random()
           LIMIT GREATEST(LEAST(p_count, 20), 3)
        ) x
    ) q;

  RETURN QUERY
  SELECT
    -- Client copy: the key is blanked, not omitted, so the shape still
    -- matches QuizQuestion.fromJson on the Dart side.
    (SELECT COALESCE(jsonb_agg(e - 'ord' || jsonb_build_object('correct_index', -1)), '[]'::jsonb)
       FROM jsonb_array_elements(v_rows) e),
    (SELECT COALESCE(jsonb_agg((e->>'correct_index')::int), '[]'::jsonb)
       FROM jsonb_array_elements(v_rows) e);
END;
$$;

REVOKE ALL ON FUNCTION public.quiz_match_draw(integer) FROM public;

-- The curated view of a match. Everything a client is allowed to know.
--
-- `revealed_index` is the one place the key reaches a client without going
-- through an answer, and it is gated on `resolved_at`: the question is
-- closed for BOTH players by then, so there is nothing left to cheat at.
-- Without it the player who let the clock run out never saw what the right
-- answer was — a timeout makes no `quiz_match_answer` call, so nothing
-- would ever have told them.
--
-- `my_choice` exists for the neighbouring reason: it is what lets a
-- reconnecting client redraw the tile it had picked, instead of coming
-- back mid-reveal with nothing selected.
CREATE OR REPLACE FUNCTION public.quiz_match_view(p_match public.quiz_matches)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
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
    'a_points',             p_match.a_points,
    'b_points',             p_match.b_points,
    'a_correct',            p_match.a_correct,
    'b_correct',            p_match.b_correct,
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
               'photo',   COALESCE(q.photo_url, p.profile_photo_url),
               'verified', COALESCE(p.is_verified, false))
        FROM public.quiz_profiles q
        JOIN public.profiles p ON p.id = q.user_id
       WHERE q.user_id = CASE WHEN p_match.player_a = auth.uid()
                              THEN p_match.player_b ELSE p_match.player_a END
    )
  );
$$;

REVOKE ALL ON FUNCTION public.quiz_match_view(public.quiz_matches) FROM public;

-- ---- The state machine -----------------------------------------------------
--
-- One function owns every transition, and it decides purely from the clock
-- and the two answer flags. Both `quiz_match_answer` and `quiz_match_tick`
-- run it, so a match advances correctly no matter which call arrives — and
-- it cannot be advanced early by a client that lies about its own clock.

CREATE OR REPLACE FUNCTION public.quiz_match_progress(p_match_id uuid)
RETURNS public.quiz_matches
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  m            public.quiz_matches;
  v_key        jsonb;
  v_deadline   timestamptz;
  v_a_done     boolean;
  v_b_done     boolean;
  v_stale      interval := interval '25 seconds';
  v_reveal     interval := interval '1600 milliseconds';
BEGIN
  SELECT * INTO m FROM public.quiz_matches WHERE id = p_match_id FOR UPDATE;
  IF m.id IS NULL THEN
    RAISE EXCEPTION 'Match not found';
  END IF;
  IF m.status <> 'active' THEN
    RETURN m;
  END IF;

  -- 1. Has someone walked away? A forfeit ends the match immediately; it
  --    must never leave the other player watching a clock that never moves.
  IF m.a_last_seen < now() - v_stale THEN
    UPDATE public.quiz_matches
       SET status = 'complete', forfeited_by = m.player_a,
           winner_id = m.player_b, completed_at = now(), resolved_at = now()
     WHERE id = m.id RETURNING * INTO m;
    RETURN m;
  END IF;
  IF m.b_last_seen IS NOT NULL AND m.b_last_seen < now() - v_stale THEN
    UPDATE public.quiz_matches
       SET status = 'complete', forfeited_by = m.player_b,
           winner_id = m.player_a, completed_at = now(), resolved_at = now()
     WHERE id = m.id RETURNING * INTO m;
    RETURN m;
  END IF;

  v_deadline := m.question_started_at
                + make_interval(secs => m.seconds_per_question);
  v_a_done := m.a_answered_index >= m.current_index;
  v_b_done := m.b_answered_index >= m.current_index;

  -- 2. Close the question — both in, or the clock beat whoever is missing.
  --    Timeout is a wrong answer, exactly as in solo play.
  IF m.resolved_at IS NULL AND (
       (v_a_done AND v_b_done) OR now() >= v_deadline
     ) THEN
    SELECT answer_key INTO v_key FROM public.quiz_match_keys WHERE match_id = m.id;

    IF NOT v_a_done THEN
      INSERT INTO public.quiz_match_answers
        (match_id, player_id, question_index, chosen_index, correct, points, elapsed_ms)
      VALUES (m.id, m.player_a, m.current_index, -1, false, 0,
              m.seconds_per_question * 1000)
      ON CONFLICT DO NOTHING;
      m.a_combo := 0;
      m.a_answered_index := m.current_index;
    END IF;
    IF NOT v_b_done AND m.player_b IS NOT NULL THEN
      INSERT INTO public.quiz_match_answers
        (match_id, player_id, question_index, chosen_index, correct, points, elapsed_ms)
      VALUES (m.id, m.player_b, m.current_index, -1, false, 0,
              m.seconds_per_question * 1000)
      ON CONFLICT DO NOTHING;
      m.b_combo := 0;
      m.b_answered_index := m.current_index;
    END IF;

    UPDATE public.quiz_matches
       SET resolved_at       = now(),
           a_combo           = m.a_combo,
           b_combo           = m.b_combo,
           a_answered_index  = m.a_answered_index,
           b_answered_index  = m.b_answered_index
     WHERE id = m.id RETURNING * INTO m;
  END IF;

  -- 3. Reveal has been up long enough — next question, or the final whistle.
  IF m.resolved_at IS NOT NULL AND now() >= m.resolved_at + v_reveal THEN
    IF m.current_index + 1 >= m.question_count THEN
      UPDATE public.quiz_matches
         SET status       = 'complete',
             completed_at = now(),
             winner_id    = CASE
                              WHEN m.a_points > m.b_points THEN m.player_a
                              WHEN m.b_points > m.a_points THEN m.player_b
                              ELSE NULL          -- a draw
                            END
       WHERE id = m.id RETURNING * INTO m;
    ELSE
      UPDATE public.quiz_matches
         SET current_index       = m.current_index + 1,
             question_started_at = now(),
             resolved_at         = NULL
       WHERE id = m.id RETURNING * INTO m;
    END IF;
  END IF;

  RETURN m;
END;
$$;

REVOKE ALL ON FUNCTION public.quiz_match_progress(uuid) FROM public;

-- ---- Matchmaking -----------------------------------------------------------

-- Join the oldest open match, or open one and wait.
--
-- `p_online` is the caller's live presence roster. Matching only against
-- people the presence channel says are actually there is what keeps this
-- from pairing someone with a queue entry whose owner closed the app —
-- the honest "nobody available right now" is far better than a spinner.
CREATE OR REPLACE FUNCTION public.quiz_match_find(p_online uuid[] DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  m       public.quiz_matches;
  v_id    uuid;
  v_q     jsonb;
  v_key   jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not signed in';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.quiz_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'QUIZ_PROFILE_REQUIRED';
  END IF;

  -- Abandon anything I left lying in the queue.
  UPDATE public.quiz_matches
     SET status = 'cancelled', completed_at = now()
   WHERE player_a = auth.uid() AND status = 'open';

  -- Try to join someone. SKIP LOCKED so two players racing for the same
  -- opponent take different rows instead of one of them erroring.
  SELECT id INTO v_id
    FROM public.quiz_matches
   WHERE status = 'open'
     AND player_a <> auth.uid()
     AND created_at > now() - interval '2 minutes'
     AND (p_online IS NULL OR player_a = ANY (p_online))
   ORDER BY created_at
   FOR UPDATE SKIP LOCKED
   LIMIT 1;

  IF v_id IS NOT NULL THEN
    UPDATE public.quiz_matches
       SET player_b            = auth.uid(),
           status              = 'active',
           started_at          = now(),
           question_started_at = now(),
           a_last_seen         = now(),
           b_last_seen         = now()
     WHERE id = v_id
     RETURNING * INTO m;
    RETURN public.quiz_match_view(m);
  END IF;

  -- Nobody waiting — open a table and sit at it.
  SELECT d.public_questions, d.answer_key INTO v_q, v_key
    FROM public.quiz_match_draw(7) d;

  INSERT INTO public.quiz_matches (player_a, status, questions, question_count)
  VALUES (auth.uid(), 'open', v_q, jsonb_array_length(v_q))
  RETURNING * INTO m;

  INSERT INTO public.quiz_match_keys (match_id, answer_key)
  VALUES (m.id, v_key);

  RETURN public.quiz_match_view(m);
END;
$$;

REVOKE ALL ON FUNCTION public.quiz_match_find(uuid[]) FROM public;
GRANT EXECUTE ON FUNCTION public.quiz_match_find(uuid[]) TO authenticated;

-- Challenge one specific person to a live match. Widened beyond friends:
-- anyone with a quiz profile who has not blocked you.
CREATE OR REPLACE FUNCTION public.quiz_match_invite(p_opponent_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  m     public.quiz_matches;
  v_q   jsonb;
  v_key jsonb;
BEGIN
  IF auth.uid() IS NULL OR p_opponent_id = auth.uid() THEN
    RAISE EXCEPTION 'Invalid opponent';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.quiz_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'QUIZ_PROFILE_REQUIRED';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.quiz_profiles WHERE user_id = p_opponent_id) THEN
    RAISE EXCEPTION 'That player has no quiz profile yet';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.profiles
     WHERE id = p_opponent_id AND COALESCE(is_banned, false)
  ) THEN
    RAISE EXCEPTION 'Invalid opponent';
  END IF;

  SELECT d.public_questions, d.answer_key INTO v_q, v_key
    FROM public.quiz_match_draw(7) d;

  INSERT INTO public.quiz_matches
    (player_a, player_b, status, questions, question_count)
  VALUES (auth.uid(), p_opponent_id, 'invited', v_q, jsonb_array_length(v_q))
  RETURNING * INTO m;

  INSERT INTO public.quiz_match_keys (match_id, answer_key) VALUES (m.id, v_key);

  RETURN public.quiz_match_view(m);
END;
$$;

REVOKE ALL ON FUNCTION public.quiz_match_invite(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.quiz_match_invite(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.quiz_match_accept(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  m public.quiz_matches;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.quiz_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'QUIZ_PROFILE_REQUIRED';
  END IF;
  UPDATE public.quiz_matches
     SET status              = 'active',
         started_at          = now(),
         question_started_at = now(),
         a_last_seen         = now(),
         b_last_seen         = now()
   WHERE id = p_match_id
     AND player_b = auth.uid()
     AND status = 'invited'
     -- An invite nobody answered inside five minutes is not a live match.
     AND created_at > now() - interval '5 minutes'
  RETURNING * INTO m;

  IF m.id IS NULL THEN
    RAISE EXCEPTION 'That challenge is no longer open';
  END IF;
  RETURN public.quiz_match_view(m);
END;
$$;

REVOKE ALL ON FUNCTION public.quiz_match_accept(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.quiz_match_accept(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.quiz_match_cancel(p_match_id uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.quiz_matches
     SET status = 'cancelled', completed_at = now()
   WHERE id = p_match_id
     AND status IN ('open','invited')
     AND (player_a = auth.uid() OR player_b = auth.uid());
$$;

REVOKE ALL ON FUNCTION public.quiz_match_cancel(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.quiz_match_cancel(uuid) TO authenticated;

-- ---- Playing ---------------------------------------------------------------

-- Lock in an answer.
--
-- The ONLY place a client learns `correct_index`, and only for a question
-- it has just answered — which is what makes it safe. Solo play can hold
-- the key on the client; competitively that is fatal.
CREATE OR REPLACE FUNCTION public.quiz_match_answer(
  p_match_id uuid,
  p_index    integer,
  p_choice   integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  m           public.quiz_matches;
  v_is_a      boolean;
  v_key       jsonb;
  v_answer    integer;
  v_correct   boolean;
  v_elapsed   numeric;
  v_remaining numeric;
  v_combo     integer;
  v_points    integer;
BEGIN
  SELECT * INTO m FROM public.quiz_matches WHERE id = p_match_id FOR UPDATE;
  IF m.id IS NULL THEN RAISE EXCEPTION 'Match not found'; END IF;

  v_is_a := (m.player_a = auth.uid());
  IF NOT v_is_a AND m.player_b <> auth.uid() THEN
    RAISE EXCEPTION 'Not your match';
  END IF;
  IF m.status <> 'active' THEN RAISE EXCEPTION 'Match is not running'; END IF;
  IF p_index <> m.current_index THEN
    RAISE EXCEPTION 'Question has moved on';
  END IF;
  IF (v_is_a AND m.a_answered_index >= p_index)
     OR (NOT v_is_a AND m.b_answered_index >= p_index) THEN
    RAISE EXCEPTION 'Already answered';
  END IF;

  -- Timing comes from the server's own stamp, never from the client.
  v_elapsed := EXTRACT(EPOCH FROM (now() - m.question_started_at));
  v_remaining := 1 - (v_elapsed / GREATEST(m.seconds_per_question, 1));

  SELECT answer_key INTO v_key FROM public.quiz_match_keys WHERE match_id = m.id;
  v_answer := (v_key -> p_index)::text::integer;

  -- Past the deadline is a miss, whatever they tapped. A small grace covers
  -- the round trip so a genuinely-in-time answer is not punished for the
  -- network.
  IF v_elapsed > m.seconds_per_question + 1.5 THEN
    v_correct := false;
    p_choice  := -1;
  ELSE
    v_correct := (p_choice = v_answer);
  END IF;

  v_combo := CASE WHEN v_correct
                  THEN (CASE WHEN v_is_a THEN m.a_combo ELSE m.b_combo END) + 1
                  ELSE 0 END;
  v_points := public.quiz_points_for(v_correct, v_remaining, v_combo);

  INSERT INTO public.quiz_match_answers
    (match_id, player_id, question_index, chosen_index, correct, points, elapsed_ms)
  VALUES (m.id, auth.uid(), p_index, p_choice, v_correct, v_points,
          GREATEST((v_elapsed * 1000)::integer, 0))
  ON CONFLICT DO NOTHING;

  IF v_is_a THEN
    UPDATE public.quiz_matches
       SET a_points = a_points + v_points,
           a_correct = a_correct + (CASE WHEN v_correct THEN 1 ELSE 0 END),
           a_combo = v_combo,
           a_answered_index = p_index,
           a_last_seen = now()
     WHERE id = m.id;
  ELSE
    UPDATE public.quiz_matches
       SET b_points = b_points + v_points,
           b_correct = b_correct + (CASE WHEN v_correct THEN 1 ELSE 0 END),
           b_combo = v_combo,
           b_answered_index = p_index,
           b_last_seen = now()
     WHERE id = m.id;
  END IF;

  -- May close the question if that was the second answer in.
  m := public.quiz_match_progress(m.id);

  RETURN public.quiz_match_view(m) || jsonb_build_object(
    'locked',        true,
    'correct',       v_correct,
    'correct_index', v_answer,
    'points',        v_points,
    'combo',         v_combo
  );
END;
$$;

REVOKE ALL ON FUNCTION public.quiz_match_answer(uuid, integer, integer) FROM public;
GRANT EXECUTE ON FUNCTION public.quiz_match_answer(uuid, integer, integer) TO authenticated;

-- Heartbeat + clock. Called by both clients on a short timer: it is what
-- advances an expired question, and what lets the server notice a player
-- who has gone away.
CREATE OR REPLACE FUNCTION public.quiz_match_tick(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  m public.quiz_matches;
BEGIN
  UPDATE public.quiz_matches
     SET a_last_seen = CASE WHEN player_a = auth.uid() THEN now() ELSE a_last_seen END,
         b_last_seen = CASE WHEN player_b = auth.uid() THEN now() ELSE b_last_seen END
   WHERE id = p_match_id
     AND (player_a = auth.uid() OR player_b = auth.uid())
  RETURNING * INTO m;

  IF m.id IS NULL THEN RAISE EXCEPTION 'Not your match'; END IF;

  IF m.status = 'active' THEN
    m := public.quiz_match_progress(m.id);
  END IF;
  RETURN public.quiz_match_view(m);
END;
$$;

REVOKE ALL ON FUNCTION public.quiz_match_tick(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.quiz_match_tick(uuid) TO authenticated;

-- Quitting on purpose. Same outcome as vanishing, just immediate.
CREATE OR REPLACE FUNCTION public.quiz_match_forfeit(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  m public.quiz_matches;
BEGIN
  UPDATE public.quiz_matches
     SET status       = CASE WHEN status = 'active' THEN 'complete' ELSE 'cancelled' END,
         forfeited_by = auth.uid(),
         winner_id    = CASE WHEN status = 'active'
                             THEN (CASE WHEN player_a = auth.uid()
                                        THEN player_b ELSE player_a END)
                             ELSE NULL END,
         completed_at = now(),
         resolved_at  = now()
   WHERE id = p_match_id
     AND status IN ('open','invited','active')
     AND (player_a = auth.uid() OR player_b = auth.uid())
  RETURNING * INTO m;

  IF m.id IS NULL THEN
    SELECT * INTO m FROM public.quiz_matches WHERE id = p_match_id;
    IF m.id IS NULL THEN RAISE EXCEPTION 'Match not found'; END IF;
  END IF;
  RETURN public.quiz_match_view(m);
END;
$$;

REVOKE ALL ON FUNCTION public.quiz_match_forfeit(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.quiz_match_forfeit(uuid) TO authenticated;

-- Reconnect: catch up to wherever the match actually is.
CREATE OR REPLACE FUNCTION public.quiz_match_state(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  m public.quiz_matches;
BEGIN
  SELECT * INTO m FROM public.quiz_matches
   WHERE id = p_match_id AND (player_a = auth.uid() OR player_b = auth.uid());
  IF m.id IS NULL THEN RAISE EXCEPTION 'Not your match'; END IF;
  IF m.status = 'active' THEN
    m := public.quiz_match_progress(m.id);
  END IF;
  RETURN public.quiz_match_view(m);
END;
$$;

REVOKE ALL ON FUNCTION public.quiz_match_state(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.quiz_match_state(uuid) TO authenticated;

-- Live invites aimed at me and still worth showing.
CREATE OR REPLACE FUNCTION public.quiz_match_invites()
RETURNS TABLE (
  match_id   uuid,
  from_id    uuid,
  from_name  text,
  from_photo text,
  created_at timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT m.id, m.player_a, q.display_name,
         COALESCE(q.photo_url, p.profile_photo_url), m.created_at
    FROM public.quiz_matches m
    JOIN public.quiz_profiles q ON q.user_id = m.player_a
    JOIN public.profiles p      ON p.id      = m.player_a
   WHERE m.player_b = auth.uid()
     AND m.status = 'invited'
     AND m.created_at > now() - interval '5 minutes'
   ORDER BY m.created_at DESC;
$$;

REVOKE ALL ON FUNCTION public.quiz_match_invites() FROM public;
GRANT EXECUTE ON FUNCTION public.quiz_match_invites() TO authenticated;

-- Who can I challenge? Everyone with a quiz profile — the widening the
-- founder asked for. `quiz_challengeable_friends` is untouched and still
-- backs the async challenge flow.
CREATE OR REPLACE FUNCTION public.quiz_players(
  p_query  text DEFAULT NULL,
  p_online uuid[] DEFAULT NULL,
  p_limit  integer DEFAULT 40
)
RETURNS TABLE (
  user_id     uuid,
  full_name   text,
  photo_url   text,
  is_verified boolean,
  is_online   boolean,
  week_points bigint
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT q.user_id,
         q.display_name,
         COALESCE(q.photo_url, p.profile_photo_url),
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
$$;

REVOKE ALL ON FUNCTION public.quiz_players(text, uuid[], integer) FROM public;
GRANT EXECUTE ON FUNCTION public.quiz_players(text, uuid[], integer) TO authenticated;

-- ---- Banking the result ----------------------------------------------------
-- A finished live match writes both players into `quiz_scores` so it feeds
-- the weekly leaderboard like any other round. In a trigger rather than the
-- client, because the loser's app has no business reporting the winner's
-- score — and a rage-quitter's app will not report anything at all.

CREATE OR REPLACE FUNCTION public.quiz_match_bank_scores()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status <> 'complete' OR OLD.status = 'complete' THEN
    RETURN NEW;
  END IF;
  IF NEW.player_b IS NULL THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.quiz_scores (user_id, mode, points, correct_count, total_count)
  VALUES
    (NEW.player_a, 'live', GREATEST(LEAST(NEW.a_points, 100000), 0),
     NEW.a_correct, NEW.question_count),
    (NEW.player_b, 'live', GREATEST(LEAST(NEW.b_points, 100000), 0),
     NEW.b_correct, NEW.question_count);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS quiz_matches_bank_scores ON public.quiz_matches;
CREATE TRIGGER quiz_matches_bank_scores
  AFTER UPDATE ON public.quiz_matches
  FOR EACH ROW EXECUTE FUNCTION public.quiz_match_bank_scores();

-- ---- Notifying an invite ---------------------------------------------------
-- Type `quiz_challenge`, which is NOT in `is_essential_notification` — so
-- `suppress_sabbath_notifications()` drops it during quiet hours. That is
-- the founder's decision, not an oversight.

CREATE OR REPLACE FUNCTION public.notify_quiz_match_invite()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_name text;
BEGIN
  IF NEW.status <> 'invited' OR NEW.player_b IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(NULLIF(btrim(q.display_name), ''), 'Someone')
    INTO v_name
    FROM public.quiz_profiles q WHERE q.user_id = NEW.player_a;

  INSERT INTO public.notifications (
    user_id, title, body, type, reference_id, reference_type
  ) VALUES (
    NEW.player_b,
    'Live quiz challenge',
    COALESCE(v_name, 'Someone') || ' wants to play you right now. '
      || 'Tap to join — the match is live for five minutes.',
    'quiz_challenge',
    NEW.id::text,
    'quiz_match'
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS quiz_matches_notify_invite ON public.quiz_matches;
CREATE TRIGGER quiz_matches_notify_invite
  AFTER INSERT ON public.quiz_matches
  FOR EACH ROW EXECUTE FUNCTION public.notify_quiz_match_invite();

-- ---- Housekeeping ----------------------------------------------------------
-- Queue entries and invites nobody took, plus matches both players walked
-- out of. Safe to call from anywhere; cheap enough to call on app open.

CREATE OR REPLACE FUNCTION public.quiz_matches_sweep()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.quiz_matches
     SET status = 'cancelled', completed_at = now()
   WHERE status IN ('open','invited')
     AND created_at < now() - interval '5 minutes';

  UPDATE public.quiz_matches
     SET status = 'complete', completed_at = now(),
         winner_id = CASE WHEN a_points > b_points THEN player_a
                          WHEN b_points > a_points THEN player_b END
   WHERE status = 'active'
     AND GREATEST(a_last_seen, COALESCE(b_last_seen, a_last_seen))
         < now() - interval '3 minutes';
$$;

REVOKE ALL ON FUNCTION public.quiz_matches_sweep() FROM public;
GRANT EXECUTE ON FUNCTION public.quiz_matches_sweep() TO authenticated;
