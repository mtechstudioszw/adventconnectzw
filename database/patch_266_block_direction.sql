-- =====================================================================
--  PATCH 266 — blocking: the two questions are not the same question
--
--  ## THE BUG
--
--  Founder, 25 Aug 2026: "when l block user B it hides his profile
--  picture — it should not."
--
--  `is_blocked_by(p_author)` became SYMMETRIC in patch_200, and that
--  was right for what patch_200 was fixing: you block someone to stop
--  seeing them, so their posts, stories and prayers must leave your
--  feed. Symmetry is the correct answer for CONTENT.
--
--  But `UserProfileScreen` asks the same helper a different question —
--  "should this profile read as unavailable to me?" — and gets the
--  symmetric answer. So blocking somebody hides THEM from the person
--  who did the blocking: no photo, no name, "This account is
--  unavailable". Which is backwards, and worse, it hides the one screen
--  with the Unblock button on it.
--
--  ## THE FIX
--
--  A second helper that asks the one-directional question, and nothing
--  else. `is_blocked_by` is NOT touched — every RLS policy on posts,
--  stories and prayers reads it, and those want the symmetric answer.
--
--      is_blocked_by(x)    -- "is there a block between us, either way?"
--                          -- CONTENT visibility. Unchanged.
--      has_blocked_me(x)   -- "has x blocked ME?"
--                          -- PROFILE visibility. New.
--
--  With that split, WhatsApp's behaviour falls out:
--
--    A blocks B.
--      A opens B's profile  -> has_blocked_me(B) is FALSE -> A sees B
--                              normally, including the Unblock button.
--      B opens A's profile  -> has_blocked_me(A) is TRUE  -> B sees
--                              "This account is unavailable": no photo,
--                              no cover, no about, no last seen.
--      A's feed             -> is_blocked_by(B) is TRUE   -> B's posts
--                              are gone. Unchanged from patch_200.
--
--  ## WHY NOT JUST FIX THE SCREEN
--
--  Because the screen cannot ask the question. `blocked_users` has RLS
--  that hides the other person's rows, so a client-side query for "did
--  they block me" returns nothing whether they did or not. That is
--  exactly why patch_071 introduced a SECURITY DEFINER helper in the
--  first place.
--
--  RLS: no policy created, altered or dropped.
--  IDEMPOTENT: yes.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.has_blocked_me(p_user UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.blocked_users b
     WHERE b.blocker_id = p_user
       AND b.blocked_id = auth.uid()
  );
$$;

-- Same posture as is_blocked_by: authenticated only. `anon` must never
-- be able to probe block relationships, and PUBLIC would hand it to
-- every role including anon.
REVOKE ALL ON FUNCTION public.has_blocked_me(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_blocked_me(UUID) TO authenticated;


-- =====================================================================
--  VERIFY
--
--    -- Both helpers exist, and anon holds neither:
--    SELECT p.proname,
--           has_function_privilege('anon', p.oid, 'EXECUTE')          AS anon,
--           has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth
--      FROM pg_proc p
--     WHERE p.pronamespace = 'public'::regnamespace
--       AND p.proname IN ('is_blocked_by', 'has_blocked_me')
--     ORDER BY 1;
--    -- expect 2 rows, anon FALSE on both, auth TRUE on both
--
--    -- is_blocked_by must still be the SYMMETRIC one. If this ever
--    -- returns a body with only one OR-arm, the feed regressed to the
--    -- patch_071 bug.
--    SELECT prosrc LIKE '%OR%' AS is_symmetric
--      FROM pg_proc
--     WHERE proname = 'is_blocked_by'
--       AND pronamespace = 'public'::regnamespace;
--    -- expect TRUE
-- =====================================================================
