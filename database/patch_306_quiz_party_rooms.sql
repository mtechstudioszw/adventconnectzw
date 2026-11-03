-- patch_306 — Live quiz rooms for 2 to 5 players (3 Nov 2026). APPLIED 3 Nov 2026 (owner ran it in the SQL editor; verified).
--
-- Owner: "live match what happens when 5 people live match".
--
-- The 1-v-1 match (quiz_matches) has one column per player (a_points,
-- b_points…), so it cannot grow to five. Rooms sit beside it instead of
-- replacing it: the 1-v-1 arena keeps working untouched.
--
-- How a room works
--   * The host creates it and gets a 6-letter code. Friends join with the
--     code or from an invite notification. Up to 5 players.
--   * The host starts it (2+ players). Questions come from the same bank
--     and the same draw as 1-v-1; the answer key lives in quiz_room_keys,
--     which no client can read.
--   * Every answer is timed and marked by the SERVER (quiz_room_answer).
--     A question closes when everyone still in the room has answered or
--     the clock runs out, shows the answer for 2 s, then moves on.
--   * There is no server loop: every player's phone calls quiz_room_tick
--     about once a second, and whichever call arrives first moves the
--     room on. Same model as quiz_match_tick.
--   * A player silent for 25 s is marked as gone and the room carries on
--     without them, so one dropped phone never freezes four others.
--   * Scores are shown live, but only as of the last REVEALED question:
--     a score that jumps the moment someone taps would tell the others
--     they got it right.
--   * On the final whistle each player's score goes into quiz_scores
--     (mode 'party'), so it counts on the weekly leaderboard.
--
-- Access: RLS on, no policies. Everything goes through SECURITY DEFINER
-- functions granted to `authenticated` only.

BEGIN;

-- ---------------------------------------------------------------- tables

CREATE TABLE IF NOT EXISTS public.quiz_rooms (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code                 text NOT NULL UNIQUE,
  host_id              uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status               text NOT NULL DEFAULT 'lobby'
                       CHECK (status IN ('lobby', 'active', 'complete', 'cancelled')),
  questions            jsonb,
  question_count       integer NOT NULL DEFAULT 10,
  seconds_per_question integer NOT NULL DEFAULT 15,
  current_index        integer NOT NULL DEFAULT 0,
  question_started_at  timestamptz,
  resolved_at          timestamptz,
  created_at           timestamptz NOT NULL DEFAULT now(),
  started_at           timestamptz,
  completed_at         timestamptz
);
CREATE INDEX IF NOT EXISTS quiz_rooms_status_created
  ON public.quiz_rooms (status, created_at);

CREATE TABLE IF NOT EXISTS public.quiz_room_keys (
  room_id    uuid PRIMARY KEY REFERENCES public.quiz_rooms(id) ON DELETE CASCADE,
  answer_key jsonb NOT NULL
);

CREATE TABLE IF NOT EXISTS public.quiz_room_players (
  room_id        uuid NOT NULL REFERENCES public.quiz_rooms(id) ON DELETE CASCADE,
  user_id        uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  joined_at      timestamptz NOT NULL DEFAULT now(),
  last_seen      timestamptz NOT NULL DEFAULT now(),
  left_at        timestamptz,
  points         integer NOT NULL DEFAULT 0,
  correct        integer NOT NULL DEFAULT 0,
  combo          integer NOT NULL DEFAULT 0,
  answered_index integer NOT NULL DEFAULT -1,
  PRIMARY KEY (room_id, user_id)
);
CREATE INDEX IF NOT EXISTS quiz_room_players_user
  ON public.quiz_room_players (user_id);

CREATE TABLE IF NOT EXISTS public.quiz_room_answers (
  room_id        uuid NOT NULL REFERENCES public.quiz_rooms(id) ON DELETE CASCADE,
  user_id        uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  question_index integer NOT NULL,
  chosen_index   integer NOT NULL,
  correct        boolean NOT NULL,
  points         integer NOT NULL,
  elapsed_ms     integer NOT NULL,
  PRIMARY KEY (room_id, user_id, question_index)
);

ALTER TABLE public.quiz_rooms        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quiz_room_keys    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quiz_room_players ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quiz_room_answers ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.quiz_rooms, public.quiz_room_keys,
              public.quiz_room_players, public.quiz_room_answers
  FROM anon, authenticated;

-- Maintenance mode blocks writes here like everywhere else. The trigger
-- function already returns COALESCE(NEW, OLD) (patch_189).
DROP TRIGGER IF EXISTS maintenance_block ON public.quiz_rooms;
CREATE TRIGGER maintenance_block
  BEFORE INSERT OR UPDATE OR DELETE ON public.quiz_rooms
  FOR EACH ROW EXECUTE FUNCTION public.block_during_maintenance();

-- ---------------------------------------------------------------- view

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

-- -------------------------------------------------------------- helpers

CREATE OR REPLACE FUNCTION public.quiz_room_new_code()
RETURNS text
LANGUAGE plpgsql
VOLATILE
SET search_path TO 'public'
AS $$
DECLARE
  -- No 0/O, 1/I/L: the code is read aloud across a church hall.
  v_alpha constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_code  text;
BEGIN
  LOOP
    SELECT string_agg(substr(v_alpha, 1 + floor(random() * length(v_alpha))::int, 1), '')
      INTO v_code FROM generate_series(1, 6);
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.quiz_rooms WHERE code = v_code);
  END LOOP;
  RETURN v_code;
END;
$$;

CREATE OR REPLACE FUNCTION public.quiz_room_member(p_room uuid)
RETURNS public.quiz_rooms
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  r public.quiz_rooms;
BEGIN
  SELECT * INTO r FROM public.quiz_rooms WHERE id = p_room;
  IF r.id IS NULL THEN RAISE EXCEPTION 'Room not found'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.quiz_room_players
     WHERE room_id = p_room AND user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Not in this room';
  END IF;
  RETURN r;
END;
$$;

-- ------------------------------------------------------------ lifecycle

CREATE OR REPLACE FUNCTION public.quiz_room_create()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  r public.quiz_rooms;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in first'; END IF;
  PERFORM public.quiz_profile_ensure();

  -- Housekeeping, cheap on the (status, created_at) index: lobbies nobody
  -- started within an hour are closed.
  UPDATE public.quiz_rooms SET status = 'cancelled'
   WHERE status = 'lobby' AND created_at < now() - interval '1 hour';
  -- One open lobby per host: making a new room closes your old one.
  UPDATE public.quiz_rooms SET status = 'cancelled'
   WHERE host_id = auth.uid() AND status = 'lobby';

  INSERT INTO public.quiz_rooms (code, host_id)
  VALUES (public.quiz_room_new_code(), auth.uid())
  RETURNING * INTO r;
  INSERT INTO public.quiz_room_players (room_id, user_id)
  VALUES (r.id, auth.uid());
  RETURN public.quiz_room_view(r);
END;
$$;

CREATE OR REPLACE FUNCTION public.quiz_room_join(p_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  r       public.quiz_rooms;
  v_count integer;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in first'; END IF;
  IF EXISTS (SELECT 1 FROM public.profiles
              WHERE id = auth.uid() AND COALESCE(is_banned, false)) THEN
    RAISE EXCEPTION 'Not allowed';
  END IF;
  SELECT * INTO r FROM public.quiz_rooms
   WHERE code = upper(btrim(p_code)) FOR UPDATE;
  IF r.id IS NULL OR r.status = 'cancelled' THEN
    RAISE EXCEPTION 'ROOM_NOT_FOUND';
  END IF;

  -- Already in it (a re-open, or a second tap on the invite): just show it.
  IF EXISTS (SELECT 1 FROM public.quiz_room_players
              WHERE room_id = r.id AND user_id = auth.uid()
                AND left_at IS NULL) THEN
    RETURN public.quiz_room_view(r);
  END IF;
  IF r.status <> 'lobby' THEN RAISE EXCEPTION 'ROOM_STARTED'; END IF;

  SELECT count(*) INTO v_count FROM public.quiz_room_players
   WHERE room_id = r.id AND left_at IS NULL;
  IF v_count >= 5 THEN RAISE EXCEPTION 'ROOM_FULL'; END IF;

  PERFORM public.quiz_profile_ensure();
  INSERT INTO public.quiz_room_players (room_id, user_id)
  VALUES (r.id, auth.uid())
  ON CONFLICT (room_id, user_id)
  DO UPDATE SET left_at = NULL, last_seen = now(), joined_at = now();
  RETURN public.quiz_room_view(r);
END;
$$;

CREATE OR REPLACE FUNCTION public.quiz_room_invite(p_room uuid, p_user uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  r      public.quiz_rooms;
  v_name text;
BEGIN
  r := public.quiz_room_member(p_room);
  IF r.status <> 'lobby' THEN RAISE EXCEPTION 'ROOM_STARTED'; END IF;
  IF p_user = auth.uid() THEN RETURN; END IF;
  -- Same rule as 1-v-1: only people who have opened the quiz.
  IF NOT EXISTS (SELECT 1 FROM public.quiz_profiles WHERE user_id = p_user) THEN
    RAISE EXCEPTION 'That player has no quiz profile yet';
  END IF;
  -- One invite per person per room — no notification spam.
  IF EXISTS (SELECT 1 FROM public.notifications
              WHERE user_id = p_user AND reference_type = 'quiz_room'
                AND reference_id = r.code) THEN
    RETURN;
  END IF;

  SELECT COALESCE(NULLIF(btrim(q.display_name), ''), 'Someone') INTO v_name
    FROM public.quiz_profiles q WHERE q.user_id = auth.uid();

  INSERT INTO public.notifications
    (user_id, title, body, type, reference_id, reference_type)
  VALUES (
    p_user,
    'Live quiz room',
    COALESCE(v_name, 'Someone') || ' invited you to a live Bible quiz. '
      || 'Tap to join room ' || r.code || '.',
    'quiz_challenge',
    r.code,
    'quiz_room'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.quiz_room_leave(p_room uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  r      public.quiz_rooms;
  v_next uuid;
BEGIN
  SELECT * INTO r FROM public.quiz_rooms WHERE id = p_room FOR UPDATE;
  IF r.id IS NULL THEN RETURN; END IF;
  UPDATE public.quiz_room_players SET left_at = now()
   WHERE room_id = p_room AND user_id = auth.uid() AND left_at IS NULL;

  IF r.status = 'lobby' AND r.host_id = auth.uid() THEN
    -- Hand the room to whoever has waited longest; close it if empty.
    SELECT user_id INTO v_next FROM public.quiz_room_players
     WHERE room_id = p_room AND left_at IS NULL
     ORDER BY joined_at LIMIT 1;
    IF v_next IS NULL THEN
      UPDATE public.quiz_rooms SET status = 'cancelled' WHERE id = p_room;
    ELSE
      UPDATE public.quiz_rooms SET host_id = v_next WHERE id = p_room;
    END IF;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.quiz_room_start(p_room uuid, p_count integer DEFAULT 10)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  r       public.quiz_rooms;
  v_count integer;
  v_q     jsonb;
  v_key   jsonb;
BEGIN
  SELECT * INTO r FROM public.quiz_rooms WHERE id = p_room FOR UPDATE;
  IF r.id IS NULL THEN RAISE EXCEPTION 'Room not found'; END IF;
  IF r.host_id <> auth.uid() THEN RAISE EXCEPTION 'Only the host can start'; END IF;
  IF r.status <> 'lobby' THEN RETURN public.quiz_room_view(r); END IF;

  -- Players who closed the app in the lobby don't hold the game up.
  UPDATE public.quiz_room_players SET left_at = now()
   WHERE room_id = p_room AND left_at IS NULL
     AND last_seen < now() - interval '25 seconds'
     AND user_id <> auth.uid();
  SELECT count(*) INTO v_count FROM public.quiz_room_players
   WHERE room_id = p_room AND left_at IS NULL;
  IF v_count < 2 THEN RAISE EXCEPTION 'NEED_TWO_PLAYERS'; END IF;

  SELECT d.public_questions, d.answer_key INTO v_q, v_key
    FROM public.quiz_match_draw(GREATEST(LEAST(p_count, 20), 5)) d;
  INSERT INTO public.quiz_room_keys (room_id, answer_key) VALUES (r.id, v_key)
  ON CONFLICT (room_id) DO UPDATE SET answer_key = EXCLUDED.answer_key;

  -- The clock starts 3 s from now: everyone sees the same countdown.
  UPDATE public.quiz_rooms
     SET status = 'active', questions = v_q,
         question_count = jsonb_array_length(v_q),
         current_index = 0, started_at = now(),
         question_started_at = now() + interval '3 seconds',
         resolved_at = NULL
   WHERE id = r.id RETURNING * INTO r;
  UPDATE public.quiz_room_players SET last_seen = now()
   WHERE room_id = r.id AND left_at IS NULL;
  RETURN public.quiz_room_view(r);
END;
$$;

-- ------------------------------------------------------------- the clock

CREATE OR REPLACE FUNCTION public.quiz_room_progress(p_room uuid)
RETURNS public.quiz_rooms
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  r          public.quiz_rooms;
  v_deadline timestamptz;
  v_waiting  integer;
  v_present  integer;
  v_reveal   constant interval := interval '2 seconds';
BEGIN
  SELECT * INTO r FROM public.quiz_rooms WHERE id = p_room FOR UPDATE;
  IF r.id IS NULL OR r.status <> 'active' THEN RETURN r; END IF;

  -- 1. Anyone silent for 25 s has gone; the rest play on.
  UPDATE public.quiz_room_players SET left_at = now()
   WHERE room_id = r.id AND left_at IS NULL
     AND last_seen < now() - interval '25 seconds';
  SELECT count(*) INTO v_present FROM public.quiz_room_players
   WHERE room_id = r.id AND left_at IS NULL;
  IF v_present = 0 THEN
    UPDATE public.quiz_rooms
       SET status = 'complete', completed_at = now(), resolved_at = now()
     WHERE id = r.id RETURNING * INTO r;
    RETURN r;
  END IF;

  -- Still in the opening countdown.
  IF now() < r.question_started_at THEN RETURN r; END IF;

  v_deadline := r.question_started_at + make_interval(secs => r.seconds_per_question);
  SELECT count(*) INTO v_waiting FROM public.quiz_room_players
   WHERE room_id = r.id AND left_at IS NULL AND answered_index < r.current_index;

  -- 2. Close the question: everyone in, or the clock ran out. A timeout
  --    is a wrong answer, as in solo play.
  IF r.resolved_at IS NULL AND (v_waiting = 0 OR now() >= v_deadline) THEN
    INSERT INTO public.quiz_room_answers
      (room_id, user_id, question_index, chosen_index, correct, points, elapsed_ms)
    SELECT r.id, rp.user_id, r.current_index, -1, false, 0,
           r.seconds_per_question * 1000
      FROM public.quiz_room_players rp
     WHERE rp.room_id = r.id AND rp.left_at IS NULL
       AND rp.answered_index < r.current_index
    ON CONFLICT DO NOTHING;
    UPDATE public.quiz_room_players
       SET combo = 0, answered_index = r.current_index
     WHERE room_id = r.id AND left_at IS NULL
       AND answered_index < r.current_index;
    UPDATE public.quiz_rooms SET resolved_at = now()
     WHERE id = r.id RETURNING * INTO r;
  END IF;

  -- 3. The answer has been on screen long enough: next, or final whistle.
  IF r.resolved_at IS NOT NULL AND now() >= r.resolved_at + v_reveal THEN
    IF r.current_index + 1 >= r.question_count THEN
      UPDATE public.quiz_rooms
         SET status = 'complete', completed_at = now()
       WHERE id = r.id RETURNING * INTO r;
    ELSE
      UPDATE public.quiz_rooms
         SET current_index = r.current_index + 1,
             question_started_at = now(), resolved_at = NULL
       WHERE id = r.id RETURNING * INTO r;
    END IF;
  END IF;
  RETURN r;
END;
$$;

CREATE OR REPLACE FUNCTION public.quiz_room_tick(p_room uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  r public.quiz_rooms;
BEGIN
  r := public.quiz_room_member(p_room);
  UPDATE public.quiz_room_players SET last_seen = now()
   WHERE room_id = p_room AND user_id = auth.uid() AND left_at IS NULL;
  IF r.status = 'active' THEN
    r := public.quiz_room_progress(p_room);
  END IF;
  RETURN public.quiz_room_view(r);
END;
$$;

CREATE OR REPLACE FUNCTION public.quiz_room_answer(p_room uuid, p_index integer, p_choice integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  r           public.quiz_rooms;
  rp          public.quiz_room_players;
  v_answer    integer;
  v_correct   boolean;
  v_elapsed   numeric;
  v_remaining numeric;
  v_combo     integer;
  v_points    integer;
BEGIN
  SELECT * INTO r FROM public.quiz_rooms WHERE id = p_room FOR UPDATE;
  IF r.id IS NULL THEN RAISE EXCEPTION 'Room not found'; END IF;
  SELECT * INTO rp FROM public.quiz_room_players
   WHERE room_id = p_room AND user_id = auth.uid() FOR UPDATE;
  IF rp.user_id IS NULL OR rp.left_at IS NOT NULL THEN
    RAISE EXCEPTION 'Not in this room';
  END IF;
  IF r.status <> 'active' THEN RAISE EXCEPTION 'Room is not running'; END IF;
  IF p_index <> r.current_index OR r.resolved_at IS NOT NULL THEN
    RAISE EXCEPTION 'Question has moved on';
  END IF;
  IF now() < r.question_started_at THEN RAISE EXCEPTION 'Not started yet'; END IF;
  IF rp.answered_index >= p_index THEN RAISE EXCEPTION 'Already answered'; END IF;

  -- Timing from the server's own stamp, never the client's.
  v_elapsed := EXTRACT(EPOCH FROM (now() - r.question_started_at));
  v_remaining := 1 - (v_elapsed / GREATEST(r.seconds_per_question, 1));
  SELECT (answer_key -> p_index)::text::integer INTO v_answer
    FROM public.quiz_room_keys WHERE room_id = r.id;

  IF v_elapsed > r.seconds_per_question + 1.5 THEN
    v_correct := false;
    p_choice  := -1;
  ELSE
    v_correct := (p_choice = v_answer);
  END IF;
  v_combo  := CASE WHEN v_correct THEN rp.combo + 1 ELSE 0 END;
  v_points := public.quiz_points_for(v_correct, v_remaining, v_combo);

  INSERT INTO public.quiz_room_answers
    (room_id, user_id, question_index, chosen_index, correct, points, elapsed_ms)
  VALUES (r.id, auth.uid(), p_index, p_choice, v_correct, v_points,
          GREATEST((v_elapsed * 1000)::integer, 0))
  ON CONFLICT DO NOTHING;
  UPDATE public.quiz_room_players
     SET points = points + v_points,
         correct = correct + (CASE WHEN v_correct THEN 1 ELSE 0 END),
         combo = v_combo, answered_index = p_index, last_seen = now()
   WHERE room_id = r.id AND user_id = auth.uid();

  -- The last answer in closes the question for everyone.
  r := public.quiz_room_progress(r.id);
  RETURN public.quiz_room_view(r);
END;
$$;

-- ----------------------------------------------- scores to the leaderboard

CREATE OR REPLACE FUNCTION public.quiz_room_bank_scores()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.status <> 'complete' OR OLD.status = 'complete' THEN
    RETURN NEW;
  END IF;
  INSERT INTO public.quiz_scores (user_id, mode, points, correct_count, total_count)
  SELECT rp.user_id, 'party', GREATEST(LEAST(rp.points, 100000), 0),
         rp.correct, NEW.question_count
    FROM public.quiz_room_players rp
   WHERE rp.room_id = NEW.id
     -- Only people who actually played a question.
     AND rp.answered_index >= 0;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS quiz_rooms_bank_scores ON public.quiz_rooms;
CREATE TRIGGER quiz_rooms_bank_scores
  AFTER UPDATE OF status ON public.quiz_rooms
  FOR EACH ROW EXECUTE FUNCTION public.quiz_room_bank_scores();

-- --------------------------------------------------------------- grants

DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'public.quiz_room_view(public.quiz_rooms)',
    'public.quiz_room_new_code()',
    'public.quiz_room_member(uuid)',
    'public.quiz_room_progress(uuid)',
    'public.quiz_room_bank_scores()',
    'public.quiz_room_create()',
    'public.quiz_room_join(text)',
    'public.quiz_room_invite(uuid, uuid)',
    'public.quiz_room_leave(uuid)',
    'public.quiz_room_start(uuid, integer)',
    'public.quiz_room_tick(uuid)',
    'public.quiz_room_answer(uuid, integer, integer)'
  ] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', f);
  END LOOP;
  -- Internal helpers stay off the API; only the actions below are callable.
  FOREACH f IN ARRAY ARRAY[
    'public.quiz_room_create()',
    'public.quiz_room_join(text)',
    'public.quiz_room_invite(uuid, uuid)',
    'public.quiz_room_leave(uuid)',
    'public.quiz_room_start(uuid, integer)',
    'public.quiz_room_tick(uuid)',
    'public.quiz_room_answer(uuid, integer, integer)'
  ] LOOP
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', f);
  END LOOP;
  FOREACH f IN ARRAY ARRAY[
    'public.quiz_room_view(public.quiz_rooms)',
    'public.quiz_room_new_code()',
    'public.quiz_room_member(uuid)',
    'public.quiz_room_progress(uuid)',
    'public.quiz_room_bank_scores()'
  ] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM authenticated', f);
  END LOOP;
END $$;

COMMIT;
