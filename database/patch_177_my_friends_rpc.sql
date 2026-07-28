-- =====================================================================
--  PATCH 177 — my_friends_detailed() RPC, for the new Friends screen
--
--  WHY: Profile shows a "Friends" count that has never been tappable —
--  the code comment said so outright: "the app has no friends-list
--  screen". Building one needs each friend's name and photo, and reading
--  `profiles` directly hits exactly the wall patch_043 documented:
--  profiles_select_discoverable_or_self hides any friend who has turned
--  discoverability off, so half your friends would render as "Member".
--
--  Same shape of fix as patch_043, same safety argument: SECURITY
--  DEFINER, scoped to the CALLER's own accepted friendships, returning
--  only display fields. It cannot reveal anybody the caller is not
--  already friends with.
--
--  WHY A NEW NAME, not a wider my_friends(): patch_119's my_friends()
--  already exists and returns (friend_id, full_name, profile_photo_url,
--  church_name). DirectoryService reads it for the new-chat picker, and
--  Postgres will not change a function's return type in place — the
--  only way to widen it is DROP + CREATE, which would break that caller
--  between deploy and app update. A second function costs nothing.
--
--  The extras this one adds are friendship_id (so the screen can
--  unfriend without a second lookup) and is_verified (the gold tick).
--
--  RLS: creates no policy and drops none.
--  IDEMPOTENT: CREATE OR REPLACE.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.my_friends_detailed()
RETURNS TABLE (
  friendship_id   TEXT,
  user_id         TEXT,
  full_name       TEXT,
  photo_url       TEXT,
  church_name     TEXT,
  is_verified     BOOLEAN,
  friends_since   TIMESTAMPTZ
) AS $$
  SELECT
    f.id::text,
    other.id::text,
    COALESCE(NULLIF(btrim(other.full_name), ''), 'Member'),
    other.profile_photo_url,
    c.name,
    COALESCE(other.is_verified, FALSE)
      OR COALESCE(other.is_verified_admin, FALSE),
    f.created_at
  FROM public.friendships f
  -- The friend is whichever end of the pair isn't the caller.
  JOIN public.profiles other
    ON other.id = CASE
                    WHEN f.requester_id = auth.uid() THEN f.addressee_id
                    ELSE f.requester_id
                  END
  LEFT JOIN public.churches c ON c.id = other.church_id
  WHERE f.status = 'accepted'
    AND (f.requester_id = auth.uid() OR f.addressee_id = auth.uid())
    AND COALESCE(other.is_banned, FALSE) = FALSE
  ORDER BY COALESCE(NULLIF(btrim(other.full_name), ''), 'Member');
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth;

REVOKE ALL ON FUNCTION public.my_friends_detailed() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_friends_detailed() TO authenticated;


-- =====================================================================
--  VERIFY
--    SELECT count(*) FROM my_friends_detailed();
--  Should equal the "Friends" number on your own profile, and match
--  SELECT count(*) FROM my_friends();  -- patch_119, still in use
-- =====================================================================
