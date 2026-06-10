-- =====================================================================
--  PATCH 076 — defence-in-depth: lock admin RPCs to authenticated
--
--  Audit finding: the admin_* RPCs are SECURITY DEFINER and were callable
--  by the anon role (via the default PUBLIC grant). They are already
--  functionally safe — each calls assert_super_admin() and rejects a
--  null auth.uid() — but as defence-in-depth we revoke anon/PUBLIC and
--  keep only authenticated (the role the super-admin uses). Non-breaking:
--  the super admin is an authenticated user.
-- =====================================================================

DO $$
DECLARE
  fn TEXT;
  fns TEXT[] := ARRAY[
    'admin_approve_news','admin_approve_seller','admin_broadcast',
    'admin_list_feedback','admin_list_pending_news','admin_list_reports',
    'admin_overview_stats','admin_pending_sellers','admin_reject_news',
    'admin_reject_seller','admin_reply_feedback','admin_resolve_report',
    'admin_search_users','admin_set_banned'
  ];
  sig TEXT;
BEGIN
  FOREACH fn IN ARRAY fns LOOP
    FOR sig IN
      SELECT n.nspname || '.' || p.proname || '(' ||
             pg_get_function_identity_arguments(p.oid) || ')'
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public' AND p.proname = fn
    LOOP
      EXECUTE 'REVOKE ALL ON FUNCTION ' || sig || ' FROM PUBLIC, anon';
      EXECUTE 'GRANT EXECUTE ON FUNCTION ' || sig || ' TO authenticated';
    END LOOP;
  END LOOP;
END$$;
