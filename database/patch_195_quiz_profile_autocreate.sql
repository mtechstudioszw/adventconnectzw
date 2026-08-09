-- =====================================================================
--  patch_195 — stop gating live quiz behind a form nobody filled in
--
--  Measured 2026-08-09: 164 members, and **4 quiz profiles**.
--
--  ## Why that number matters
--
--  `quiz_match_find`, `quiz_match_invite` and `quiz_match_accept` all
--  raise QUIZ_PROFILE_REQUIRED without one, and
--  `quiz_leaderboard_weekly` INNER JOINs `quiz_profiles`. So a member who
--  has not made one cannot be matched, cannot be challenged, cannot
--  accept a challenge, and does not exist on any board.
--
--  That makes the empty lobby a self-inflicted problem. Live head-to-head
--  needs two people present at the same moment; requiring both of them to
--  have separately filled in a naming form first means the realistic
--  number of people you can be matched against is three.
--
--  ## The change
--
--  A quiz profile is created on demand, from the member's real name, the
--  first time they do something that needs one. Choosing a play name stays
--  possible and stays theirs — `quiz_profile_upsert` is untouched, and the
--  arena now has an "Edit quiz profile" button — it is simply no longer a
--  toll gate in front of the feature.
--
--  `quiz_profile_ensure()` is the single place that does it, so the four
--  call sites cannot drift.
-- =====================================================================

-- ---- The auto-creator ------------------------------------------------

CREATE OR REPLACE FUNCTION public.quiz_profile_ensure()
RETURNS public.quiz_profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row  public.quiz_profiles;
  v_base text;
  v_name text;
  v_try  int := 0;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not signed in';
  END IF;

  SELECT * INTO v_row FROM public.quiz_profiles WHERE user_id = auth.uid();
  IF FOUND THEN
    RETURN v_row;
  END IF;

  -- First name only. A leaderboard row is narrow, and a full name is both
  -- too long for it and more identifying than a game board needs.
  SELECT COALESCE(NULLIF(btrim(split_part(btrim(p.full_name), ' ', 1)), ''), 'Player')
    INTO v_base
    FROM public.profiles p
   WHERE p.id = auth.uid();

  v_base := COALESCE(v_base, 'Player');
  -- The column is 2..24 by the same rule quiz_profile_upsert enforces.
  IF char_length(v_base) < 2 THEN
    v_base := 'Player';
  END IF;
  v_base := left(v_base, 20);

  -- Display names are unique. Zimbabwean first names repeat a great deal,
  -- so collisions are the normal case, not the edge one — walk until free
  -- rather than failing and leaving the member unable to play.
  v_name := v_base;
  WHILE EXISTS (
    SELECT 1 FROM public.quiz_profiles q
     WHERE lower(btrim(q.display_name)) = lower(v_name)
  ) LOOP
    v_try := v_try + 1;
    EXIT WHEN v_try > 500;
    v_name := v_base || ' ' || v_try::text;
  END LOOP;

  INSERT INTO public.quiz_profiles (user_id, display_name, photo_url)
  SELECT auth.uid(), v_name, p.profile_photo_url
    FROM public.profiles p WHERE p.id = auth.uid()
  -- Two devices, one member, same instant. Whoever lost the race is happy
  -- with whatever the winner made.
  ON CONFLICT (user_id) DO UPDATE SET updated_at = now()
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.quiz_profile_ensure() FROM public;
GRANT EXECUTE ON FUNCTION public.quiz_profile_ensure() TO authenticated;

-- ---- Replace the four gates ------------------------------------------
-- Each of these used to RAISE 'QUIZ_PROFILE_REQUIRED'. The client still
-- understands that error (QuizProfileRequired) and still shows the naming
-- sheet, so nothing breaks on an older build — it simply stops firing.

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
  PERFORM public.quiz_profile_ensure();

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
  PERFORM public.quiz_profile_ensure();

  -- The OPPONENT still needs one, and this one is not auto-created: making
  -- a row for somebody who has never opened the quiz would put a stranger
  -- on the leaderboard with 0 points and no idea why. The player list only
  -- offers people who have a profile, so this is a race guard, not a wall.
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
  PERFORM public.quiz_profile_ensure();

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


-- ---- Backfill everyone who has already played ------------------------
-- 58 banked scores exist from people with no quiz profile, so they have
-- been invisible on every leaderboard they earned a place on.

INSERT INTO public.quiz_profiles (user_id, display_name, photo_url)
SELECT s.user_id,
       -- Same first-name rule as above, made unique with a short suffix
       -- from the id rather than a counter, because this runs as one
       -- statement and cannot loop per row.
       left(
         COALESCE(
           NULLIF(btrim(split_part(btrim(p.full_name), ' ', 1)), ''),
           'Player'
         ), 16
       ) || ' ' || left(replace(s.user_id::text, '-', ''), 4),
       p.profile_photo_url
  FROM (SELECT DISTINCT user_id FROM public.quiz_scores) s
  JOIN public.profiles p ON p.id = s.user_id
 WHERE NOT EXISTS (
   SELECT 1 FROM public.quiz_profiles q WHERE q.user_id = s.user_id
 )
   AND COALESCE(p.is_banned, false) = false
ON CONFLICT (user_id) DO NOTHING;
