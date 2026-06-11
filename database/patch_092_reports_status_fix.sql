-- =====================================================================
--  PATCH 092 — reports never reached the dashboard (status mismatch)
--
--  reports.status defaults to 'pending' (and the CHECK only allows
--  pending/actioned/dismissed), but admin_list_reports defaulted to
--  listing 'open' — so every submitted report was invisible. Fix the
--  function: default to 'pending' and treat 'open' as 'pending' so any
--  caller (in-app or admin-web) sees unresolved reports.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.admin_list_reports(
  p_status TEXT DEFAULT 'pending', p_limit INTEGER DEFAULT 100)
RETURNS TABLE(
  id BIGINT, reported_by UUID, reporter_name TEXT, content_type TEXT,
  content_id TEXT, reason TEXT, details TEXT, status TEXT,
  action_taken TEXT, created_at TIMESTAMP WITH TIME ZONE)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_status TEXT := CASE WHEN p_status = 'open' THEN 'pending' ELSE p_status END;
BEGIN
  PERFORM public.assert_super_admin();
  RETURN QUERY
    SELECT r.id, r.reported_by,
           COALESCE(NULLIF(btrim(p.full_name), ''), 'Member') AS reporter_name,
           r.content_type, r.content_id, r.reason, r.details,
           COALESCE(r.status, 'pending') AS status, r.action_taken, r.created_at
      FROM public.reports r
      LEFT JOIN public.profiles p ON p.id = r.reported_by
     WHERE (v_status = 'all' OR COALESCE(r.status, 'pending') = v_status)
     ORDER BY r.created_at DESC
     LIMIT GREATEST(p_limit, 1);
END;
$function$;
