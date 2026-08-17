-- =====================================================================
--  PATCH 204 — put the ready check behind a switch until the app ships
--
--  WHY THIS EXISTS
--
--  patch_203 made `quiz_match_find` pair players into a new `ready`
--  status instead of straight into `active`. That is the right shape —
--  but the build in production (12) has never heard of `ready`. It polls
--  for `active`, so a live match under patch_203 alone would sit in the
--  ready state, nobody would confirm (the old app has no button to), and
--  12 seconds later it would expire. **Live match would be broken for
--  every current user until a new build reached them.**
--
--  A schema change that needs a client change must not go live before
--  the client does. So the pairing behaviour now reads a flag:
--
--    app_config.quiz_ready_check = 'on'   -> ready check (patch_203)
--    anything else / absent               -> pair straight to active
--
--  Default is OFF. Everything else from patch_203 stays deployed and is
--  harmless to old clients: the extra columns are ignored, and
--  `quiz_match_ready` simply has no caller yet.
--
--  ## TURN THIS ON when the build containing the ready-check UI is live
--
--      UPDATE public.app_config SET value = 'on'
--       WHERE key = 'quiz_ready_check';
--
--  Same discipline as `latest_build_android` — see the force-update note.
--  There is no rush: with the flag off, behaviour is exactly what
--  production has today.
--
--  NOTE ON SCORES: the `scores_hidden` half of patch_203 is deliberately
--  NOT gated. An old client parses the withheld opponent score as 0 via
--  `?? 0`, so it shows a zero rather than a live total — which is the
--  founder's requirement (don't disclose points mid-match) rendered
--  slightly less prettily. A new client shows a dash instead.
--
--  IDEMPOTENT: yes.
-- =====================================================================


INSERT INTO public.app_config (key, value)
VALUES ('quiz_ready_check', 'off')
ON CONFLICT (key) DO NOTHING;


CREATE OR REPLACE FUNCTION public.quiz_match_find(p_online UUID[] DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  m        public.quiz_matches;
  v_id     uuid;
  v_q      jsonb;
  v_key    jsonb;
  v_ready  boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not signed in';
  END IF;
  PERFORM public.quiz_profile_ensure();

  SELECT COALESCE(
           (SELECT value = 'on' FROM public.app_config
             WHERE key = 'quiz_ready_check'),
           FALSE)
    INTO v_ready;

  -- Abandon anything I left lying in the queue, including a ready check
  -- I walked away from.
  UPDATE public.quiz_matches
     SET status = 'cancelled', completed_at = now()
   WHERE status IN ('open','ready')
     AND (player_a = auth.uid() OR player_b = auth.uid())
     AND (status = 'open' OR ready_deadline < now());

  -- Everyone else's expired ready checks, so they don't clog the queue.
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
    IF v_ready THEN
      -- Provisional pairing. No clock until both confirm.
      UPDATE public.quiz_matches
         SET player_b       = auth.uid(),
             status         = 'ready',
             a_ready        = FALSE,
             b_ready        = FALSE,
             ready_deadline = now() + interval '12 seconds',
             a_last_seen    = now(),
             b_last_seen    = now()
       WHERE id = v_id
       RETURNING * INTO m;
    ELSE
      -- Legacy path, byte-for-byte what production does today.
      UPDATE public.quiz_matches
         SET player_b            = auth.uid(),
             status              = 'active',
             started_at          = now(),
             question_started_at = now(),
             a_last_seen         = now(),
             b_last_seen         = now()
       WHERE id = v_id
       RETURNING * INTO m;
    END IF;
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
