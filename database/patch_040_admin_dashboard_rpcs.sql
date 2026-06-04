-- =====================================================================
--  PATCH 040 — Admin dashboard RPC layer
--
--  Backs the separate web admin dashboard (admin-web/). EVERY function
--  is SECURITY DEFINER and re-checks is_super_admin server-side via
--  assert_super_admin() — the web client only holds the public anon
--  key, so the server is the sole gate. A normal signed-in user (or
--  anon) calling any of these gets "Not authorized".
--
--  Sellers are intentionally NOT re-implemented here — the existing
--  admin_pending_sellers / admin_approve_seller / admin_reject_seller
--  (patch_031/037) already serve both the in-app super-admin screen
--  AND the web dashboard.
--
--  Sections covered:
--    1. assert_super_admin()           — shared guard
--    2. admin_overview_stats()         — landing counts
--    3. admin_list_reports()           — moderation queue
--    4. admin_resolve_report()         — act on a report (+optional ban)
--    5. admin_list_feedback()          — feedback inbox
--    6. admin_reply_feedback()         — reply (notifies user) + resolve
--    7. admin_search_users()           — user lookup (joins auth email)
--    8. admin_set_banned()             — ban / unban a user
--    9. admin_broadcast()              — notice to all / segment
--
--  IDEMPOTENT: CREATE OR REPLACE throughout.
-- =====================================================================


-- ----- 1. Shared guard ----------------------------------------------
CREATE OR REPLACE FUNCTION public.assert_super_admin()
RETURNS void AS $$
DECLARE
  v_caller UUID := auth.uid();
  v_ok BOOLEAN;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Not authorized.' USING ERRCODE = '42501';
  END IF;
  SELECT COALESCE(is_super_admin, FALSE) INTO v_ok
    FROM public.profiles WHERE id = v_caller;
  IF NOT v_ok THEN
    RAISE EXCEPTION 'Not authorized.' USING ERRCODE = '42501';
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

REVOKE ALL ON FUNCTION public.assert_super_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.assert_super_admin() TO authenticated;


-- ----- 2. Overview stats --------------------------------------------
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

REVOKE ALL ON FUNCTION public.admin_overview_stats() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_overview_stats() TO authenticated;


-- ----- 3. Reports queue ---------------------------------------------
-- Returns reports plus the reporter's name. The reported content
-- itself stays addressable via content_type + content_id so the
-- dashboard can deep-describe it; we don't try to resolve every
-- content table here (too many shapes) — the admin reviews the
-- reason/details and acts.
CREATE OR REPLACE FUNCTION public.admin_list_reports(
  p_status TEXT DEFAULT 'open',
  p_limit  INT  DEFAULT 100
)
RETURNS TABLE (
  id BIGINT,
  reported_by UUID,
  reporter_name TEXT,
  content_type TEXT,
  content_id TEXT,
  reason TEXT,
  details TEXT,
  status TEXT,
  action_taken TEXT,
  created_at TIMESTAMPTZ
) AS $$
BEGIN
  PERFORM public.assert_super_admin();
  RETURN QUERY
    SELECT r.id, r.reported_by,
           COALESCE(NULLIF(btrim(p.full_name), ''), 'Member') AS reporter_name,
           r.content_type, r.content_id, r.reason, r.details,
           COALESCE(r.status,'open') AS status, r.action_taken, r.created_at
      FROM public.reports r
      LEFT JOIN public.profiles p ON p.id = r.reported_by
     WHERE (p_status = 'all' OR COALESCE(r.status,'open') = p_status)
     ORDER BY r.created_at DESC
     LIMIT GREATEST(p_limit, 1);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

REVOKE ALL ON FUNCTION public.admin_list_reports(TEXT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_reports(TEXT, INT) TO authenticated;


-- ----- 4. Resolve a report ------------------------------------------
-- Sets status + action_taken + reviewer stamp. Optionally bans a
-- user in the same call (p_ban_user_id) so "dismiss + ban the
-- offender" is one action.
CREATE OR REPLACE FUNCTION public.admin_resolve_report(
  p_report_id   BIGINT,
  p_status      TEXT,            -- 'resolved' | 'dismissed' | 'open'
  p_action      TEXT DEFAULT NULL,
  p_ban_user_id UUID DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
  v_caller UUID := auth.uid();
BEGIN
  PERFORM public.assert_super_admin();

  UPDATE public.reports
     SET status       = p_status,
         action_taken = p_action,
         reviewed_by  = v_caller,
         reviewed_at  = NOW()
   WHERE id = p_report_id;

  IF p_ban_user_id IS NOT NULL THEN
    UPDATE public.profiles SET is_banned = TRUE WHERE id = p_ban_user_id;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

REVOKE ALL ON FUNCTION public.admin_resolve_report(BIGINT, TEXT, TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_resolve_report(BIGINT, TEXT, TEXT, UUID) TO authenticated;


-- ----- 5. Feedback inbox --------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_list_feedback(
  p_status TEXT DEFAULT 'new',
  p_limit  INT  DEFAULT 100
)
RETURNS TABLE (
  id BIGINT,
  user_id UUID,
  user_name TEXT,
  category TEXT,
  subject TEXT,
  body TEXT,
  app_version TEXT,
  platform TEXT,
  status TEXT,
  resolution_note TEXT,
  created_at TIMESTAMPTZ
) AS $$
BEGIN
  PERFORM public.assert_super_admin();
  RETURN QUERY
    SELECT f.id, f.user_id,
           COALESCE(NULLIF(btrim(p.full_name), ''), 'Member') AS user_name,
           f.category, f.subject, f.body, f.app_version, f.platform,
           COALESCE(f.status,'new') AS status, f.resolution_note, f.created_at
      FROM public.feedback f
      LEFT JOIN public.profiles p ON p.id = f.user_id
     WHERE (p_status = 'all' OR COALESCE(f.status,'new') = p_status)
     ORDER BY f.created_at DESC
     LIMIT GREATEST(p_limit, 1);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

REVOKE ALL ON FUNCTION public.admin_list_feedback(TEXT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_feedback(TEXT, INT) TO authenticated;


-- ----- 6. Reply to feedback -----------------------------------------
-- Drops the reply into the user's notification feed (so they see it
-- in-app) and marks the feedback resolved with the note for the
-- audit trail.
CREATE OR REPLACE FUNCTION public.admin_reply_feedback(
  p_feedback_id BIGINT,
  p_reply       TEXT
)
RETURNS VOID AS $$
DECLARE
  v_caller UUID := auth.uid();
  v_user   UUID;
  v_clean  TEXT := NULLIF(btrim(COALESCE(p_reply,'')), '');
BEGIN
  PERFORM public.assert_super_admin();
  IF v_clean IS NULL THEN
    RAISE EXCEPTION 'Reply cannot be empty.';
  END IF;

  SELECT user_id INTO v_user FROM public.feedback WHERE id = p_feedback_id;
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Feedback % not found.', p_feedback_id;
  END IF;

  INSERT INTO public.notifications (
    user_id, title, body, type, reference_id, reference_type
  ) VALUES (
    v_user,
    'Reply from the Advent Connect team',
    v_clean,
    'feedback_reply',
    p_feedback_id::text,
    'feedback'
  );

  UPDATE public.feedback
     SET status          = 'resolved',
         resolution_note = v_clean,
         triaged_by      = v_caller,
         triaged_at      = NOW()
   WHERE id = p_feedback_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

REVOKE ALL ON FUNCTION public.admin_reply_feedback(BIGINT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_reply_feedback(BIGINT, TEXT) TO authenticated;


-- ----- 7. User search -----------------------------------------------
-- Joins auth.users for the email (profiles has no email column).
-- SECURITY DEFINER is what lets us read auth.users here.
CREATE OR REPLACE FUNCTION public.admin_search_users(
  p_query TEXT DEFAULT '',
  p_limit INT  DEFAULT 50
)
RETURNS TABLE (
  id UUID,
  full_name TEXT,
  email TEXT,
  is_banned BOOLEAN,
  is_super_admin BOOLEAN,
  created_at TIMESTAMPTZ
) AS $$
DECLARE
  v_q TEXT := '%' || btrim(COALESCE(p_query,'')) || '%';
BEGIN
  PERFORM public.assert_super_admin();
  RETURN QUERY
    SELECT p.id,
           COALESCE(NULLIF(btrim(p.full_name), ''), 'Member') AS full_name,
           u.email::text,
           COALESCE(p.is_banned, FALSE) AS is_banned,
           COALESCE(p.is_super_admin, FALSE) AS is_super_admin,
           p.created_at
      FROM public.profiles p
      LEFT JOIN auth.users u ON u.id = p.id
     WHERE btrim(COALESCE(p_query,'')) = ''
        OR p.full_name ILIKE v_q
        OR u.email ILIKE v_q
     ORDER BY p.created_at DESC
     LIMIT GREATEST(p_limit, 1);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

REVOKE ALL ON FUNCTION public.admin_search_users(TEXT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_search_users(TEXT, INT) TO authenticated;


-- ----- 8. Ban / unban -----------------------------------------------
-- Flips profiles.is_banned. A super admin can never ban themselves
-- or another super admin (guards against lock-out + admin wars).
CREATE OR REPLACE FUNCTION public.admin_set_banned(
  p_user_id UUID,
  p_banned  BOOLEAN
)
RETURNS VOID AS $$
DECLARE
  v_caller UUID := auth.uid();
  v_target_is_admin BOOLEAN;
BEGIN
  PERFORM public.assert_super_admin();

  IF p_user_id = v_caller THEN
    RAISE EXCEPTION 'You cannot ban yourself.';
  END IF;

  SELECT COALESCE(is_super_admin, FALSE) INTO v_target_is_admin
    FROM public.profiles WHERE id = p_user_id;
  IF v_target_is_admin THEN
    RAISE EXCEPTION 'Cannot ban another super admin.';
  END IF;

  UPDATE public.profiles SET is_banned = p_banned WHERE id = p_user_id;

  IF p_banned THEN
    INSERT INTO public.notifications (
      user_id, title, body, type, reference_type
    ) VALUES (
      p_user_id,
      'Account suspended',
      'Your account has been suspended for violating the community '
        || 'guidelines. Contact support if you believe this is a mistake.',
      'account_suspended',
      'account'
    );
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

REVOKE ALL ON FUNCTION public.admin_set_banned(UUID, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_banned(UUID, BOOLEAN) TO authenticated;


-- ----- 9. Broadcast a notice ----------------------------------------
-- Fans a notification out to every non-banned user (segment 'all')
-- or a province segment. Each inserted row triggers the existing
-- notify-fcm webhook, so this also pushes. Returns how many users
-- it reached.
CREATE OR REPLACE FUNCTION public.admin_broadcast(
  p_title    TEXT,
  p_body     TEXT,
  p_segment  TEXT DEFAULT 'all'   -- 'all' | province name
)
RETURNS INTEGER AS $$
DECLARE
  v_count INTEGER := 0;
  v_title TEXT := NULLIF(btrim(COALESCE(p_title,'')), '');
  v_body  TEXT := NULLIF(btrim(COALESCE(p_body,'')), '');
BEGIN
  PERFORM public.assert_super_admin();
  IF v_title IS NULL OR v_body IS NULL THEN
    RAISE EXCEPTION 'Title and message are both required.';
  END IF;

  INSERT INTO public.notifications (
    user_id, title, body, type, reference_type
  )
  SELECT p.id, v_title, v_body, 'admin_broadcast', 'announcement'
    FROM public.profiles p
   WHERE COALESCE(p.is_banned, FALSE) = FALSE
     AND (p_segment = 'all'
          OR LOWER(COALESCE(p.province,'')) = LOWER(p_segment));

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

REVOKE ALL ON FUNCTION public.admin_broadcast(TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_broadcast(TEXT, TEXT, TEXT) TO authenticated;
