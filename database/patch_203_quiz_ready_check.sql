-- =====================================================================
--  PATCH 203 — live match: a ready check, and no peeking at the score
--
--  BUG 1: you were dragged into a match you never agreed to, and you
--         lost time on question 1 for it.
--
--  `quiz_match_find` paired players like this:
--
--    A taps Find  -> INSERT a row with status 'open', then sit.
--    B taps Find  -> finds A's row and immediately sets
--                    status='active', started_at=now(),
--                    question_started_at=now().
--
--  So the instant B arrived the match was live AND THE CLOCK WAS
--  RUNNING — while A was still looking at a "searching" spinner with no
--  idea a question had started. A lost however long it took their client
--  to poll, every single time. The founder reported it as "it connects
--  automatically without the other user's approval"; the stolen seconds
--  were the half nobody had noticed.
--
--  THE FIX: a `ready` state between `open` and `active`.
--
--    A taps Find      -> status 'open'
--    B joins          -> status 'ready', ready_deadline = now() + 12s.
--                        THE CLOCK DOES NOT START.
--    both tap Ready   -> status 'active', and question_started_at is
--                        stamped THEN, so both players get the full
--                        fifteen seconds on question 1.
--    either declines
--    or 12s passes    -> cancelled, and the player who did say yes is
--                        free to search again immediately.
--
--  This also answers "what happens if many users are in live match":
--  the queue is unchanged and still FIFO with SKIP LOCKED, but a pair is
--  now provisional until both confirm, so a player who queued and walked
--  away no longer burns a real opponent's match.
--
--  BUG 2: the opponent's running score was visible mid-match.
--
--  `quiz_match_view` published a_points/b_points to both players on every
--  poll. Founder: don't disclose points until the game is over. The view
--  now returns the CALLER's own score during play and NULL for the
--  opponent, plus an explicit `scores_hidden` flag so the UI can render a
--  dash rather than a very convincing "0".
--
--  Own score stays visible — it is not a disclosure, and a player with no
--  feedback at all cannot tell a good run from a bad one. Say so if you
--  want both hidden; it is one line.
--
--  IDEMPOTENT: yes.
-- =====================================================================


-- ----- 1. Ready-check columns ---------------------------------------
ALTER TABLE public.quiz_matches
  ADD COLUMN IF NOT EXISTS a_ready BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE public.quiz_matches
  ADD COLUMN IF NOT EXISTS b_ready BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE public.quiz_matches
  ADD COLUMN IF NOT EXISTS ready_deadline TIMESTAMPTZ;


-- ----- 2. Allow the new status --------------------------------------
ALTER TABLE public.quiz_matches
  DROP CONSTRAINT IF EXISTS quiz_matches_status_check;
ALTER TABLE public.quiz_matches
  ADD CONSTRAINT quiz_matches_status_check
  CHECK (status = ANY (ARRAY[
    'open'::text, 'invited'::text, 'ready'::text,
    'active'::text, 'complete'::text, 'cancelled'::text
  ]));


-- ----- 3. Pair into `ready`, never straight into `active` ------------
CREATE OR REPLACE FUNCTION public.quiz_match_find(p_online UUID[] DEFAULT NULL)
RETURNS JSONB
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
  PERFORM public.quiz_profile_ensure();

  -- Abandon anything I left lying in the queue, including a ready check
  -- I walked away from — otherwise my own stale row is the first thing
  -- the next search finds.
  UPDATE public.quiz_matches
     SET status = 'cancelled', completed_at = now()
   WHERE status IN ('open','ready')
     AND (player_a = auth.uid() OR player_b = auth.uid())
     AND (status = 'open' OR ready_deadline < now());

  -- Clear out everyone else's expired ready checks so they don't sit in
  -- the queue looking joinable.
  UPDATE public.quiz_matches
     SET status = 'cancelled', completed_at = now()
   WHERE status = 'ready' AND ready_deadline < now();

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
    -- Provisional pairing ONLY. No started_at, no question_started_at:
    -- the clock must not run while either player is still deciding.
    UPDATE public.quiz_matches
       SET player_b        = auth.uid(),
           status          = 'ready',
           a_ready         = FALSE,
           b_ready         = FALSE,
           ready_deadline  = now() + interval '12 seconds',
           a_last_seen     = now(),
           b_last_seen     = now()
     WHERE id = v_id
     RETURNING * INTO m;
    RETURN public.quiz_match_view(m);
  END IF;

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


-- ----- 4. The ready check itself ------------------------------------
CREATE OR REPLACE FUNCTION public.quiz_match_ready(
  p_match_id UUID,
  p_ready    BOOLEAN DEFAULT TRUE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  m public.quiz_matches;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not signed in';
  END IF;

  SELECT * INTO m FROM public.quiz_matches
   WHERE id = p_match_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No such match';
  END IF;
  IF auth.uid() NOT IN (m.player_a, COALESCE(m.player_b, m.player_a)) THEN
    RAISE EXCEPTION 'Not your match';
  END IF;

  -- Already running (or over) — nothing to confirm. Returning the state
  -- rather than raising keeps a double-tap harmless.
  IF m.status <> 'ready' THEN
    RETURN public.quiz_match_view(m);
  END IF;

  -- Declined, or nobody confirmed in time.
  IF p_ready IS NOT TRUE OR m.ready_deadline < now() THEN
    UPDATE public.quiz_matches
       SET status = 'cancelled', completed_at = now()
     WHERE id = p_match_id
     RETURNING * INTO m;
    RETURN public.quiz_match_view(m);
  END IF;

  UPDATE public.quiz_matches
     SET a_ready = CASE WHEN player_a = auth.uid() THEN TRUE ELSE a_ready END,
         b_ready = CASE WHEN player_b = auth.uid() THEN TRUE ELSE b_ready END
   WHERE id = p_match_id
   RETURNING * INTO m;

  -- Both in. Start the clock NOW so question 1 is the full length for
  -- both players — this is the whole point of the patch.
  IF m.a_ready AND m.b_ready THEN
    UPDATE public.quiz_matches
       SET status              = 'active',
           started_at          = now(),
           question_started_at = now(),
           a_last_seen         = now(),
           b_last_seen         = now()
     WHERE id = p_match_id
     RETURNING * INTO m;
  END IF;

  RETURN public.quiz_match_view(m);
END;
$$;

REVOKE ALL ON FUNCTION public.quiz_match_ready(UUID, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.quiz_match_ready(UUID, BOOLEAN) TO authenticated;


-- ----- 5. Hide the opponent's score until it is over -----------------
CREATE OR REPLACE FUNCTION public.quiz_match_view(p_match public.quiz_matches)
RETURNS JSONB
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
               'photo',   COALESCE(q.photo_url, p.profile_photo_url),
               'verified', COALESCE(p.is_verified, false))
        FROM public.quiz_profiles q
        JOIN public.profiles p ON p.id = q.user_id
       WHERE q.user_id = CASE WHEN p_match.player_a = auth.uid()
                              THEN p_match.player_b ELSE p_match.player_a END
    )
  );
$$;
