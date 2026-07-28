-- =====================================================================
--  PATCH 175 — Multiple admins per church
--
--  CHECKED FIRST, AND THE SCHEMA WAS ALREADY THERE. `church_admins` is
--  keyed UNIQUE (church_id, user_id) — many users per church has always
--  been legal. `role` already CHECKs IN ('primary','standard'), and
--  idx_church_admins_one_primary_per_church caps only the PRIMARY at one
--  per church. Standard admins were never limited.
--
--  So this patch adds NO table, NO column, and — importantly — DROPS NO
--  RLS POLICY. The four church_admins policies from patch_002 stay
--  exactly as they are. (The founder rule about reading pg_policies
--  before dropping one is therefore not engaged here; nothing is
--  dropped. It would have been, had this needed the RLS rework it looked
--  like it needed.)
--
--  What was actually missing is the ability to ADD one. The insert
--  policy is `auth.uid() = user_id` — apply-for-yourself only — so a
--  primary admin has no way to nominate anyone. Rather than widen that
--  policy (which would let any member insert rows naming others), this
--  patch adds two SECURITY DEFINER RPCs with a narrow, explicit guard.
--
--    church_admin_nominate(church_id, user_id)
--      → primary admin (or super admin) proposes a member as a STANDARD
--        admin. Lands as status='pending': the super-admin approval
--        queue stays the only route to real power, unchanged.
--    church_admin_revoke(id)
--      → primary admin (or super admin) removes a standard admin.
--        Refuses to remove a primary, and refuses to remove the caller,
--        so a church cannot be left with no way back in.
--    church_admin_list(church_id)
--      → the roster, for the dashboard. Admins of that church only.
--
--  IDEMPOTENT: yes.
-- =====================================================================


-- Is the caller the approved PRIMARY admin of this church (or super)?
CREATE OR REPLACE FUNCTION public.is_primary_church_admin(p_church_id BIGINT)
RETURNS BOOLEAN
LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE AS $$
  SELECT public.is_super_admin() OR EXISTS (
    SELECT 1 FROM public.church_admins ca
     WHERE ca.church_id = p_church_id
       AND ca.user_id  = auth.uid()
       AND ca.status   = 'approved'
       AND ca.role     = 'primary'
  );
$$;
REVOKE ALL ON FUNCTION public.is_primary_church_admin(BIGINT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_primary_church_admin(BIGINT) TO authenticated;


CREATE OR REPLACE FUNCTION public.church_admin_nominate(
  p_church_id BIGINT, p_user_id UUID
)
RETURNS BIGINT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id BIGINT;
BEGIN
  IF NOT public.is_primary_church_admin(p_church_id) THEN
    RAISE EXCEPTION 'Only the primary admin can nominate.' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'No such member.';
  END IF;

  -- Re-nominating someone who was rejected reopens their application;
  -- re-nominating a pending or approved admin is a no-op, not an error,
  -- so a double tap in the UI can't produce a scary message.
  INSERT INTO public.church_admins (church_id, user_id, role, status)
  VALUES (p_church_id, p_user_id, 'standard', 'pending')
  ON CONFLICT (church_id, user_id) DO UPDATE
    SET status = CASE WHEN church_admins.status = 'rejected'
                      THEN 'pending' ELSE church_admins.status END,
        updated_at = NOW()
  RETURNING id INTO v_id;

  INSERT INTO public.notifications (
    user_id, title, body, type, reference_id, reference_type
  ) VALUES (
    p_user_id,
    'Church admin nomination',
    'You have been nominated as an admin for your church. It is awaiting approval.',
    'church_admin_status', v_id::text, 'church_admin'
  );

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.church_admin_nominate(BIGINT, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.church_admin_nominate(BIGINT, UUID) TO authenticated;


CREATE OR REPLACE FUNCTION public.church_admin_revoke(p_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r public.church_admins%ROWTYPE;
BEGIN
  SELECT * INTO r FROM public.church_admins WHERE id = p_id;
  IF r.id IS NULL THEN RETURN; END IF;

  IF NOT public.is_primary_church_admin(r.church_id) THEN
    RAISE EXCEPTION 'Only the primary admin can remove an admin.' USING ERRCODE = '42501';
  END IF;
  IF r.role = 'primary' THEN
    RAISE EXCEPTION 'The primary admin cannot be removed here.';
  END IF;
  IF r.user_id = auth.uid() THEN
    RAISE EXCEPTION 'You cannot remove yourself.';
  END IF;

  DELETE FROM public.church_admins WHERE id = p_id;
END;
$$;
REVOKE ALL ON FUNCTION public.church_admin_revoke(BIGINT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.church_admin_revoke(BIGINT) TO authenticated;


CREATE OR REPLACE FUNCTION public.church_admin_list(p_church_id BIGINT)
RETURNS TABLE (
  id          BIGINT,
  user_id     UUID,
  full_name   TEXT,
  photo_url   TEXT,
  role        TEXT,
  status      TEXT,
  created_at  TIMESTAMPTZ
)
LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE AS $$
  SELECT ca.id, ca.user_id,
         COALESCE(NULLIF(btrim(p.full_name), ''), 'Member'),
         p.profile_photo_url, ca.role, ca.status, ca.created_at
    FROM public.church_admins ca
    LEFT JOIN public.profiles p ON p.id = ca.user_id
   WHERE ca.church_id = p_church_id
     AND (
       public.is_super_admin()
       OR EXISTS (SELECT 1 FROM public.church_admins me
                   WHERE me.church_id = p_church_id
                     AND me.user_id = auth.uid()
                     AND me.status  = 'approved')
     )
   ORDER BY (ca.role = 'primary') DESC, ca.status, ca.created_at;
$$;
REVOKE ALL ON FUNCTION public.church_admin_list(BIGINT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.church_admin_list(BIGINT) TO authenticated;


-- =====================================================================
--  VERIFY
--    SELECT church_id, count(*) FILTER (WHERE status='approved') AS admins
--      FROM church_admins GROUP BY church_id ORDER BY admins DESC LIMIT 10;
--    SELECT * FROM church_admin_list(<church_id>);
-- =====================================================================
