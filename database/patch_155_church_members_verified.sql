-- =====================================================================
--  PATCH 155 — church_conversation_members returns verified flags
--
--  So the group-info member list can show the gold verified tick beside
--  church admins / the founder in CHURCH groups too (regular groups
--  already get it from the conversation_members profiles embed).
--  Return-type change → DROP then recreate.
-- =====================================================================
DROP FUNCTION IF EXISTS public.church_conversation_members(BIGINT);

CREATE OR REPLACE FUNCTION public.church_conversation_members(p_conv BIGINT)
RETURNS TABLE (
  user_id UUID,
  full_name TEXT,
  photo_url TEXT,
  is_verified BOOLEAN,
  is_verified_admin BOOLEAN
) AS $$
  SELECT p.id,
         COALESCE(NULLIF(btrim(p.full_name), ''), 'Member') AS full_name,
         p.profile_photo_url,
         COALESCE(p.is_verified, false),
         COALESCE(p.is_verified_admin, false)
    FROM public.conversations c
    JOIN public.profiles p ON p.church_id = c.church_id
   WHERE c.id = p_conv
     AND c.church_id IS NOT NULL
   ORDER BY p.full_name;
$$ LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public;

REVOKE ALL ON FUNCTION public.church_conversation_members(BIGINT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.church_conversation_members(BIGINT) TO authenticated;
