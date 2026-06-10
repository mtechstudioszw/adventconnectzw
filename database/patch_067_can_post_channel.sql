-- =====================================================================
--  PATCH 067 — can_post_church_channel(): composer gate for channels
--  True if the caller may post to the church ANNOUNCEMENT channel that
--  owns p_conv (verified church admin OR super admin). The app uses it to
--  lock the composer for ordinary members. (Members chat is unrestricted.)
-- =====================================================================

CREATE OR REPLACE FUNCTION public.can_post_church_channel(p_conv BIGINT)
RETURNS BOOLEAN AS $$
  SELECT public.is_my_church_admin_conv(p_conv)
    OR EXISTS (SELECT 1 FROM public.profiles p
                WHERE p.id = auth.uid() AND COALESCE(p.is_super_admin, FALSE));
$$ LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public;
GRANT EXECUTE ON FUNCTION public.can_post_church_channel(BIGINT) TO authenticated;
