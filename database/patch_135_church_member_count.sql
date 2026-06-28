-- patch_135: let a church admin see how many members follow their church.
-- Gated: returns a count only for the super admin or an APPROVED admin of that
-- church (otherwise 0). Scoped per-church — an admin can't read another
-- church's stats. Grants no other powers.

CREATE OR REPLACE FUNCTION public.church_member_count(p_church_id bigint)
RETURNS integer
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT CASE
    WHEN public.is_super_admin()
      OR EXISTS (
        SELECT 1 FROM public.church_admins ca
         WHERE ca.church_id = p_church_id
           AND ca.user_id = auth.uid()
           AND ca.status = 'approved'
      )
    THEN (SELECT count(*)::int FROM public.church_followers cf
           WHERE cf.church_id = p_church_id)
    ELSE 0
  END;
$$;

REVOKE ALL ON FUNCTION public.church_member_count(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.church_member_count(bigint) TO authenticated;
