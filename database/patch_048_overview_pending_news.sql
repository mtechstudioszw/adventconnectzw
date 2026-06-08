-- =====================================================================
--  PATCH 048 — admin_overview_stats includes pending_news count
--  (supports the dashboard News badge + in-app news approvals)
--  IDEMPOTENT: CREATE OR REPLACE.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.admin_overview_stats()
RETURNS JSON AS $$
DECLARE
  v JSON;
BEGIN
  PERFORM public.assert_super_admin();
  SELECT json_build_object(
    'pending_sellers', (
      SELECT COUNT(*) FROM public.sellers
       WHERE status IN ('pending','final_review_pending')),
    'pending_news', (
      SELECT COUNT(*) FROM public.advent_news WHERE status = 'pending'),
    'open_reports', (
      SELECT COUNT(*) FROM public.reports
       WHERE COALESCE(status,'open') = 'open'),
    'untriaged_feedback', (
      SELECT COUNT(*) FROM public.feedback
       WHERE COALESCE(status,'new') IN ('new','open')),
    'total_users', (SELECT COUNT(*) FROM public.profiles),
    'banned_users', (
      SELECT COUNT(*) FROM public.profiles WHERE is_banned = TRUE),
    'new_users_7d', (
      SELECT COUNT(*) FROM public.profiles
       WHERE created_at > NOW() - INTERVAL '7 days')
  ) INTO v;
  RETURN v;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;
