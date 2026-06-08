-- =====================================================================
--  PATCH 043 — pending_friend_requests() RPC (tester bug #19)
--
--  BUG: the Requests tab showed "Member" instead of the requester's
--       name. fetchPendingFriendRequests() reads profiles directly,
--       but profiles RLS (profiles_select_discoverable_or_self) only
--       exposes profiles where is_discoverable = true. A requester who
--       turned discoverability off — or simply isn't visible to the
--       addressee — read back as null → "Member".
--
--  FIX: a SECURITY DEFINER RPC that returns the requester's name,
--       photo, and church for the CALLER's own incoming pending
--       requests. Safe: it only ever reveals people who explicitly
--       sent a request TO the caller (addressee_id = auth.uid()), and
--       only the minimal display fields.
--
--  IDEMPOTENT: CREATE OR REPLACE.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.pending_friend_requests()
RETURNS TABLE (
  friendship_id          TEXT,
  requester_id           TEXT,
  requester_name         TEXT,
  requester_photo_url    TEXT,
  requester_church_name  TEXT,
  created_at             TIMESTAMPTZ
) AS $$
  SELECT
    f.id::text,
    f.requester_id::text,
    COALESCE(NULLIF(btrim(p.full_name), ''), 'Member'),
    p.profile_photo_url,
    c.name,
    f.created_at
  FROM public.friendships f
  LEFT JOIN public.profiles p ON p.id = f.requester_id
  LEFT JOIN public.churches  c ON c.id = p.church_id
  WHERE f.addressee_id = auth.uid()
    AND f.status = 'pending'
  ORDER BY f.created_at DESC;
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth;

REVOKE ALL ON FUNCTION public.pending_friend_requests() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pending_friend_requests() TO authenticated;
