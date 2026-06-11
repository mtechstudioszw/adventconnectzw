-- =====================================================================
--  PATCH 093 — admin can reply to a report's reporter
--
--  Sends the super-admin's reply to the person who filed the report as
--  an in-app notification (mirrors admin_reply_feedback).
-- =====================================================================

CREATE OR REPLACE FUNCTION public.admin_reply_report(p_report_id BIGINT, p_reply TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'auth'
AS $$
DECLARE v_reporter UUID;
BEGIN
  PERFORM public.assert_super_admin();
  SELECT reported_by INTO v_reporter FROM public.reports WHERE id = p_report_id;
  IF v_reporter IS NOT NULL AND btrim(COALESCE(p_reply, '')) <> '' THEN
    INSERT INTO public.notifications (
      user_id, title, body, type, reference_id, reference_type)
    VALUES (v_reporter, 'Update on your report', p_reply,
            'announcement', p_report_id::text, 'report');
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_reply_report(BIGINT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_reply_report(BIGINT, TEXT) TO authenticated;
