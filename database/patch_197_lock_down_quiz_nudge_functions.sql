-- =====================================================================
--  patch_197 — the nudge functions were callable by anyone
--
--  Found by auditing patch_196 immediately after applying it.
--
--  ## The hole
--
--  `quiz_notify_play_time()` inserts a notification for EVERY eligible
--  member. patch_196 ended it with:
--
--      REVOKE ALL ON FUNCTION public.quiz_notify_play_time() FROM public;
--
--  which is what the rest of this schema does, and which is not enough.
--  Supabase ships `ALTER DEFAULT PRIVILEGES ... GRANT EXECUTE ON FUNCTIONS
--  TO anon, authenticated` — an **explicit** grant to those two roles, not
--  an inherited one through PUBLIC. Revoking from PUBLIC leaves the
--  explicit grants standing, and `has_function_privilege('anon', …)`
--  confirmed all three new functions were executable by anon.
--
--  So anyone holding the anon key — which is committed in the client and
--  public by design — could POST to
--  `/rest/v1/rpc/quiz_notify_play_time` and push a notification to every
--  member who has ever played the quiz, as often as the 20-hour cap
--  allowed. `quiz_nudge_eligible(text)` additionally returned the user ids
--  of everyone who plays.
--
--  These three are cron-only. They are called by pg_cron, which runs as
--  the table owner, so nothing legitimate loses access.
--
--  Note `quiz_profile_ensure()` KEEPS its grant: it is called by the
--  client's own match RPCs, and it can only ever create a row for
--  `auth.uid()`.
-- =====================================================================

REVOKE ALL ON FUNCTION public.quiz_notify_play_time()
  FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.quiz_notify_rank_drop()
  FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.quiz_nudge_eligible(text)
  FROM public, anon, authenticated;

-- Trigger functions cannot be invoked over PostgREST (they return the
-- pseudo-type `trigger`), so this is hygiene rather than a fix — but it
-- matches how `churches_protect_columns` is already locked, and leaving
-- one of a pair open invites somebody to copy the wrong one later.
REVOKE ALL ON FUNCTION public.friendships_promote_conversation()
  FROM public, anon, authenticated;

DO $$
DECLARE
  v_open text;
BEGIN
  SELECT string_agg(p.proname, ', ')
    INTO v_open
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname IN ('quiz_notify_play_time', 'quiz_notify_rank_drop',
                       'quiz_nudge_eligible', 'friendships_promote_conversation')
     AND (has_function_privilege('anon', p.oid, 'EXECUTE')
       OR has_function_privilege('authenticated', p.oid, 'EXECUTE'));
  IF v_open IS NOT NULL THEN
    RAISE EXCEPTION 'patch_197: still reachable from the client: %', v_open;
  END IF;
  RAISE NOTICE 'patch_197: nudge functions are cron-only';
END;
$$;
