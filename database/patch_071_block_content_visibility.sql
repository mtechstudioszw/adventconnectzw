-- =====================================================================
--  PATCH 071 — Blocked users can't see the blocker's content
--
--  When A blocks B, B must not see A's posts / stories / prayers (and,
--  client-side, A's profile). Implemented as RESTRICTIVE SELECT policies
--  so they AND with the existing permissive policies (no existing policy
--  is touched, nothing else changes). A still sees their own content
--  (you can't block yourself).
-- =====================================================================

-- True when the AUTHOR p_author has blocked the current viewer.
CREATE OR REPLACE FUNCTION public.is_blocked_by(p_author UUID)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.blocked_users b
     WHERE b.blocker_id = p_author
       AND b.blocked_id = auth.uid()
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public;
GRANT EXECUTE ON FUNCTION public.is_blocked_by(UUID) TO authenticated;

-- ----- posts ----------------------------------------------------------
DROP POLICY IF EXISTS posts_hide_from_blocked ON public.posts;
CREATE POLICY posts_hide_from_blocked ON public.posts
  AS RESTRICTIVE FOR SELECT TO authenticated
  USING (NOT public.is_blocked_by(author_id));

-- ----- stories --------------------------------------------------------
DROP POLICY IF EXISTS stories_hide_from_blocked ON public.stories;
CREATE POLICY stories_hide_from_blocked ON public.stories
  AS RESTRICTIVE FOR SELECT TO authenticated
  USING (NOT public.is_blocked_by(author_id));

-- ----- prayers --------------------------------------------------------
DROP POLICY IF EXISTS prayers_hide_from_blocked ON public.prayers;
CREATE POLICY prayers_hide_from_blocked ON public.prayers
  AS RESTRICTIVE FOR SELECT TO authenticated
  USING (NOT public.is_blocked_by(author_id));
