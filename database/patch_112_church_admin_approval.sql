-- =====================================================================
--  PATCH 112 — Church-admin claim: contact-based verification + super-admin
--  approve/reject queue.
--
--  The claim no longer needs an appointment-letter photo. The applicant
--  supplies a WhatsApp number + (optional) email + a short note; the super
--  admin talks to them off-app, then approves/rejects from the dashboard.
--  (appointment_letter_url stays as a nullable, now-unused column.)
--
--  Self-approval is already blocked by existing triggers
--  (church_admins_pin_pending_on_insert + church_admins_block_status_self_update);
--  these RPCs are SECURITY DEFINER + assert_super_admin so only the founder
--  can flip status. notify_church_admin_status already pings the applicant
--  when their status changes.
-- =====================================================================

ALTER TABLE public.church_admins ADD COLUMN IF NOT EXISTS applicant_email text;
ALTER TABLE public.church_admins ADD COLUMN IF NOT EXISTS applicant_note text;

CREATE OR REPLACE FUNCTION public.admin_list_pending_church_admins()
RETURNS TABLE (
  id BIGINT,
  church_id BIGINT,
  user_id UUID,
  role TEXT,
  applicant_name TEXT,
  applicant_phone TEXT,
  applicant_email TEXT,
  note TEXT,
  status TEXT,
  created_at TIMESTAMPTZ,
  church_name TEXT,
  church_city TEXT
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.assert_super_admin();
  RETURN QUERY
    SELECT ca.id, ca.church_id, ca.user_id, ca.role,
           ca.applicant_name, ca.applicant_phone, ca.applicant_email,
           ca.applicant_note AS note,
           ca.status, ca.created_at, c.name, c.city
      FROM public.church_admins ca
      JOIN public.churches c ON c.id = ca.church_id
     WHERE ca.status = 'pending'
     ORDER BY ca.created_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_approve_church_admin(p_id BIGINT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.assert_super_admin();
  UPDATE public.church_admins
     SET status = 'approved', approved_at = now(), rejection_reason = NULL
   WHERE id = p_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_reject_church_admin(p_id BIGINT, p_reason TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.assert_super_admin();
  UPDATE public.church_admins
     SET status = 'rejected', rejection_reason = p_reason
   WHERE id = p_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_pending_church_admins(),
  public.admin_approve_church_admin(BIGINT),
  public.admin_reject_church_admin(BIGINT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_pending_church_admins(),
  public.admin_approve_church_admin(BIGINT),
  public.admin_reject_church_admin(BIGINT, TEXT) TO authenticated;
