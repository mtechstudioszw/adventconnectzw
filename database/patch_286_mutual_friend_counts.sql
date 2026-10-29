-- =====================================================================
--  PATCH 286 — mutual-friend counts for friend suggestions
--  STATUS: APPLIED 29 Oct 2026 (by the owner, verified)
--
--  Owner, 29 Oct 2026: friend suggestions should be smart ("this is
--  probably your friend"). The strongest honest signal the app has is
--  friends in common, and patch_182's mutual_friends() answers it for ONE
--  person per call — far too slow for Home's people groups, which draw
--  from every discoverable member.
--
--  This returns, for the caller, the people who share at least one friend
--  with them, with HOW MANY — and nothing else. No names of anyone's
--  friends, no friend lists: a count per candidate, the same thing
--  Facebook shows under "People you may know" ("4 mutual friends").
--
--  Excluded: the caller; anyone already in a friendship row with the
--  caller (accepted or pending, either direction); banned and
--  non-discoverable profiles; anyone either side has blocked.
--
--  SECURITY DEFINER because friendships is readable only by its two
--  parties (see patch_182). STABLE, read-only, no triggers — the
--  BEFORE-trigger COALESCE rule does not arise; profiles is only read.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.mutual_friend_counts(
  p_limit INTEGER DEFAULT 300
)
RETURNS TABLE (user_id UUID, mutual INTEGER)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me    UUID := auth.uid();
  v_limit INTEGER := LEAST(GREATEST(COALESCE(p_limit, 300), 1), 1000);
BEGIN
  IF v_me IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH mine AS (
    SELECT CASE WHEN f.requester_id = v_me THEN f.addressee_id
                ELSE f.requester_id END AS friend_id
      FROM public.friendships f
     WHERE f.status = 'accepted'
       AND (f.requester_id = v_me OR f.addressee_id = v_me)
  ),
  linked AS (
    -- Anyone the caller already has a row with, in any state.
    SELECT CASE WHEN f.requester_id = v_me THEN f.addressee_id
                ELSE f.requester_id END AS other_id
      FROM public.friendships f
     WHERE f.requester_id = v_me OR f.addressee_id = v_me
  ),
  fof AS (
    -- Friends of my friends, one row per shared friend.
    SELECT CASE WHEN f.requester_id = m.friend_id THEN f.addressee_id
                ELSE f.requester_id END AS candidate
      FROM mine m
      JOIN public.friendships f
        ON f.status = 'accepted'
       AND (f.requester_id = m.friend_id OR f.addressee_id = m.friend_id)
  )
  SELECT c.candidate, count(*)::INTEGER AS mutual
    FROM fof c
    JOIN public.profiles p ON p.id = c.candidate
   WHERE c.candidate <> v_me
     AND c.candidate NOT IN (SELECT other_id FROM linked)
     AND p.is_banned = FALSE
     AND p.is_discoverable = TRUE
     AND NOT EXISTS (
       SELECT 1 FROM public.blocked_users b
        WHERE (b.blocker_id = v_me AND b.blocked_id = c.candidate)
           OR (b.blocker_id = c.candidate AND b.blocked_id = v_me)
     )
   GROUP BY c.candidate
   ORDER BY mutual DESC
   LIMIT v_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.mutual_friend_counts(INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mutual_friend_counts(INTEGER) TO authenticated;

COMMENT ON FUNCTION public.mutual_friend_counts(INTEGER) IS
  'For the caller: people who share friends with them, with the count. '
  'Counts only — never anyone''s friend list. For friend suggestions.';
