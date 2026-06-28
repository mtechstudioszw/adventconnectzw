-- patch_139: church-admin dashboard data — member list (with names) + richer
-- stats. Both gated to the church's approved admin / super admin (scoped to
-- that one church; no other powers).

-- Followers of a church, with their name + photo, A→Z.
CREATE OR REPLACE FUNCTION public.church_member_list(p_church_id bigint)
RETURNS TABLE(
  user_id uuid,
  full_name text,
  profile_photo_url text,
  joined_at timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT cf.user_id, p.full_name, p.profile_photo_url, cf.created_at
    FROM public.church_followers cf
    JOIN public.profiles p ON p.id = cf.user_id
   WHERE cf.church_id = p_church_id
     AND (
       public.is_super_admin()
       OR EXISTS (
         SELECT 1 FROM public.church_admins ca
          WHERE ca.church_id = p_church_id
            AND ca.user_id = auth.uid()
            AND ca.status = 'approved'
       )
     )
   ORDER BY p.full_name ASC NULLS LAST;
$$;

REVOKE ALL ON FUNCTION public.church_member_list(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.church_member_list(bigint) TO authenticated;

-- Aggregate stats for the dashboard. Returns no row to non-admins.
CREATE OR REPLACE FUNCTION public.church_admin_stats(p_church_id bigint)
RETURNS TABLE(members int, announcements int, events int)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT
    (SELECT count(*)::int FROM public.church_followers cf WHERE cf.church_id = p_church_id),
    (SELECT count(*)::int FROM public.announcements a WHERE a.church_id = p_church_id),
    (SELECT count(*)::int FROM public.events e WHERE e.church_id = p_church_id)
  WHERE (
    public.is_super_admin()
    OR EXISTS (
      SELECT 1 FROM public.church_admins ca
       WHERE ca.church_id = p_church_id
         AND ca.user_id = auth.uid()
         AND ca.status = 'approved'
    )
  );
$$;

REVOKE ALL ON FUNCTION public.church_admin_stats(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.church_admin_stats(bigint) TO authenticated;
