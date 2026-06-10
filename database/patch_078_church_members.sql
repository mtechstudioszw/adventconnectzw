-- =====================================================================
--  PATCH 078 — list a church group's members (implicit membership)
--
--  Church groups (announcements channel + members group) have NO
--  conversation_members rows — membership is implicit via
--  profiles.church_id = conversations.church_id. The group-info screen
--  needs the member list (members group) and the count (channel), so
--  this returns the profiles that belong to the conversation's church.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.church_conversation_members(p_conv BIGINT)
RETURNS TABLE (user_id UUID, full_name TEXT, photo_url TEXT) AS $$
  SELECT p.id,
         COALESCE(NULLIF(btrim(p.full_name), ''), 'Member') AS full_name,
         p.profile_photo_url
    FROM public.conversations c
    JOIN public.profiles p ON p.church_id = c.church_id
   WHERE c.id = p_conv
     AND c.church_id IS NOT NULL
   ORDER BY p.full_name;
$$ LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public;
REVOKE ALL ON FUNCTION public.church_conversation_members(BIGINT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.church_conversation_members(BIGINT) TO authenticated;
