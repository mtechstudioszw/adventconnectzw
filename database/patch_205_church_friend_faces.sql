-- =====================================================================
--  PATCH 205 — name the friends you have at a church, not just count them
--
--  `church_friend_counts()` returns a bare number per church, and that was
--  deliberate: patch_176 chose "2 friends here" over naming anyone, so a
--  member browsing 2,600 churches could not use the directory to work out
--  where a specific person worships.
--
--  **The founder has reversed that** (17 Aug 2026). "1 friend here" is a
--  weaker prompt than seeing who, and the people involved are already your
--  accepted friends — you can see their profile, their church and their
--  posts anywhere else in the app. This discloses nothing new; it saves a
--  tap.
--
--  WHAT IT DISCLOSES, PRECISELY
--
--  Only rows where an ACCEPTED friendship exists between the caller and the
--  member, in either direction — the same predicate church_friend_counts
--  already uses, unchanged. Never a stranger, never a pending request. The
--  caller is excluded from their own list.
--
--  `total` is the real count, so the UI can say "+4" honestly while showing
--  three faces. Returning only the capped rows and letting the client count
--  them would understate every church with more than three.
--
--  Ordering is deliberate: photographed friends first, then by name. The
--  cap means three of the five get shown, and three faces communicate more
--  than three initials — so the ones with a photo earn the slots.
--
--  IDEMPOTENT: yes.
-- =====================================================================


DROP FUNCTION IF EXISTS public.church_friend_faces(BIGINT[], INTEGER);

CREATE FUNCTION public.church_friend_faces(
  p_church_ids BIGINT[],
  p_limit      INTEGER DEFAULT 3
)
RETURNS TABLE (
  church_id     BIGINT,
  friend_id     UUID,
  full_name     TEXT,
  photo_url     TEXT,
  total         INTEGER
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH mine AS (
    SELECT p.church_id,
           p.id           AS friend_id,
           p.full_name,
           p.profile_photo_url,
           -- Photographed friends take the visible slots; see the header.
           row_number() OVER (
             PARTITION BY p.church_id
             ORDER BY (p.profile_photo_url IS NULL), p.full_name
           ) AS rn,
           count(*) OVER (PARTITION BY p.church_id) AS total
      FROM public.profiles p
     WHERE p.church_id = ANY(p_church_ids)
       AND auth.uid() IS NOT NULL
       AND p.id <> auth.uid()
       AND p.is_banned = FALSE
       -- Identical to church_friend_counts. Accepted friendships only, in
       -- either direction. Nothing else is ever named.
       AND EXISTS (
         SELECT 1 FROM public.friendships f
          WHERE f.status = 'accepted'
            AND ((f.requester_id = auth.uid() AND f.addressee_id = p.id)
              OR (f.addressee_id = auth.uid() AND f.requester_id = p.id))
       )
  )
  SELECT m.church_id,
         m.friend_id,
         m.full_name,
         m.profile_photo_url,
         m.total::INTEGER
    FROM mine m
   WHERE m.rn <= GREATEST(COALESCE(p_limit, 3), 1)
   ORDER BY m.church_id, m.rn;
$$;

-- Supabase grants EXECUTE to anon AND authenticated on new functions, so
-- REVOKE FROM PUBLIC alone leaves anon holding it. Revoked by name.
-- auth.uid() is NULL for anon and the WHERE would return nothing anyway,
-- but an anonymous caller has no business asking the question at all.
REVOKE ALL ON FUNCTION public.church_friend_faces(BIGINT[], INTEGER)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.church_friend_faces(BIGINT[], INTEGER)
  TO authenticated;
