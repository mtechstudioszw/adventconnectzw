-- =====================================================================
--  PATCH 182 — mutual friends
--
--  "You and Tendai have 7 friends in common" is the single strongest
--  signal that a stranger's profile is worth a friend request, and the
--  app had no way to compute it: `friendships` is only readable by the
--  two parties to each row, so a client can see ITS OWN friends and
--  nothing about anybody else's. Any mutual-friends calculation done in
--  Dart would therefore always return zero.
--
--  SECURITY DEFINER is required for exactly that reason, and the shape
--  of the answer is what keeps it safe: this NEVER discloses the target's
--  friend list. It returns only the intersection — people the CALLER is
--  already friends with — so every row returned is someone the caller can
--  see anyway. That is the same boundary Facebook draws.
--
--  Returns the intersection ordered by name, plus the total, so the UI
--  can show a few faces and "and N others".
-- =====================================================================

CREATE OR REPLACE FUNCTION public.mutual_friends(
  p_user  UUID,
  p_limit INTEGER DEFAULT 12
)
RETURNS TABLE (
  id                UUID,
  full_name         TEXT,
  profile_photo_url TEXT,
  is_verified       BOOLEAN,
  is_verified_admin BOOLEAN,
  total             INTEGER
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me    UUID := auth.uid();
  v_limit INTEGER := LEAST(GREATEST(COALESCE(p_limit, 12), 1), 50);
BEGIN
  IF v_me IS NULL OR p_user IS NULL OR p_user = v_me THEN
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
  theirs AS (
    SELECT CASE WHEN f.requester_id = p_user THEN f.addressee_id
                ELSE f.requester_id END AS friend_id
      FROM public.friendships f
     WHERE f.status = 'accepted'
       AND (f.requester_id = p_user OR f.addressee_id = p_user)
  ),
  shared AS (
    -- INTERSECT, so nothing about the target's other friends escapes.
    SELECT friend_id FROM mine
    INTERSECT
    SELECT friend_id FROM theirs
  ),
  visible AS (
    SELECT p.id, p.full_name, p.profile_photo_url,
           p.is_verified, p.is_verified_admin
      FROM public.profiles p
      JOIN shared b ON b.friend_id = p.id
     WHERE p.is_banned = FALSE
       AND p.id <> v_me
       AND p.id <> p_user
  )
  SELECT v.id, v.full_name, v.profile_photo_url,
         v.is_verified, v.is_verified_admin,
         (SELECT count(*)::INTEGER FROM visible) AS total
    FROM visible v
   ORDER BY v.full_name ASC NULLS LAST
   LIMIT v_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.mutual_friends(UUID, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mutual_friends(UUID, INTEGER) TO authenticated;

COMMENT ON FUNCTION public.mutual_friends(UUID, INTEGER) IS
  'Friends the caller and p_user have in common. SECURITY DEFINER because '
  'friendships is readable only by its two parties; safe because it '
  'returns only the intersection — never the target''s friend list.';
