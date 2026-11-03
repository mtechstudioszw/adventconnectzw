-- patch_307 — Answering a call always failed with "already on a call". APPLIED 3 Nov 2026 (verified: accept now joins).
-- (3 Nov 2026).
--
-- Owner's test: the friend's phone rang; he tapped Answer; his phone said
-- "connection failed" while the caller's kept saying "ringing".
--
-- The server log showed call_accept called four times, every reply
-- 200, and no 'accepted' event ever recorded. call_accept checks
--
--     IF public.call_live_count(v_me) >= max_concurrent_calls (1) THEN
--       RETURN call_error('ALREADY_IN_CALL', ...)
--
-- and call_live_count counts participant rows that are invited, ringing
-- or joined on a call that has not ended. The callee's row in THIS call
-- is 'ringing' — so the check counts the very call being answered, and
-- it is true for every callee, every time. Exactly the bug patch 265
-- fixed in call_start; call_accept was missed.
--
-- Fix: exclude the call being accepted (the optional p_exclude argument
-- patch 265 added for this). Everything else in call_accept is
-- unchanged. call_join routes through call_accept, so group calls are
-- fixed by the same line.

CREATE OR REPLACE FUNCTION public.call_accept(p_call uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_me     UUID := auth.uid();
  v_call   public.calls%ROWTYPE;
  v_mine   TEXT;
  v_joined INTEGER;
BEGIN
  IF v_me IS NULL THEN
    RETURN public.call_error('NOT_AUTHENTICATED', 'Please sign in.');
  END IF;

  SELECT * INTO v_call FROM public.calls WHERE id = p_call FOR UPDATE;
  IF NOT FOUND OR v_call.status = 'ended' THEN
    RETURN public.call_error('CALL_OVER', 'That call has ended.');
  END IF;

  SELECT status INTO v_mine FROM public.call_participants
   WHERE call_id = p_call AND user_id = v_me FOR UPDATE;
  IF v_mine IS NULL THEN
    RETURN public.call_error('NOT_A_PARTICIPANT', 'You are not in this call.');
  END IF;

  -- Accepting twice must be a no-op, not an error. It happens for real:
  -- the in-app incoming screen and the CallKit / CallStyle sheet can
  -- both be showing, and a fast tap hits both.
  IF v_mine = 'joined' THEN
    RETURN public.call_snapshot(p_call, v_me);
  END IF;
  IF v_mine NOT IN ('invited', 'ringing') THEN
    RETURN public.call_error('INVALID_STATE', 'That call is no longer available.');
  END IF;

  -- patch_307: exclude THIS call. My own 'ringing' row in it is not
  -- "another call".
  IF public.call_live_count(v_me, p_call)
       >= public.call_cfg_int('call.max_concurrent_calls', 1) THEN
    RETURN public.call_error('ALREADY_IN_CALL', 'You are already on a call.');
  END IF;

  SELECT COUNT(*)::INTEGER INTO v_joined FROM public.call_participants
   WHERE call_id = p_call AND status = 'joined';
  IF v_joined >= v_call.max_participants THEN
    RETURN public.call_error('CALL_FULL', 'This call is full.');
  END IF;

  UPDATE public.call_participants
     SET status = 'joined', joined_at = now(), last_seen_at = now()
   WHERE call_id = p_call AND user_id = v_me;

  UPDATE public.calls
     SET status = 'active',
         -- §16: the billing clock starts HERE, the first time two people
         -- are actually in the room together. Never on invite, never on
         -- ring. COALESCE keeps a later joiner from resetting it.
         connected_at = COALESCE(connected_at,
                          CASE WHEN v_joined + 1 >= 2 THEN now() ELSE NULL END),
         peak_participants = GREATEST(peak_participants, (v_joined + 1)::SMALLINT),
         last_seen_at = now()
   WHERE id = p_call;

  PERFORM public.call_log_event(p_call, v_me, 'accepted',
    jsonb_build_object('peer_count', v_joined + 1));

  RETURN public.call_snapshot(p_call, v_me);
END;
$function$;
