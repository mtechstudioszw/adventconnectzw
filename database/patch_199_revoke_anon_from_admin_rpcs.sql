-- patch_199: take EXECUTE on every admin_* RPC away from `anon`.
--
-- WHAT WAS FOUND (9 Aug 2026, pre-release audit)
--
-- Eleven admin functions were executable by the `anon` role:
--
--   admin_active_users_series, admin_deletion_reasons, admin_feature_usage,
--   admin_list_audit_log, admin_list_staff, admin_notify_user,
--   admin_platform_breakdown, admin_premium_stats, admin_set_maintenance,
--   admin_set_staff_role, admin_usage_stats
--
-- NOT a live vulnerability. Every one of them calls assert_super_admin() or
-- assert_staff(...) first, and those test auth.uid(), which is NULL for anon.
-- Verified by calling four of them over HTTP with nothing but the public anon
-- key: all four returned 42501 "Not authorized." and no data.
--
-- It is still wrong, for the reason patch_197 already had to be written: the
-- guard is the ONLY thing standing between an unauthenticated request and
-- `admin_set_staff_role`. One regression in one guard — a NULL check, a
-- SECURITY DEFINER search_path slip, a future rewrite — turns a
-- defence-in-depth gap into remote privilege escalation with no login. There
-- is no reason for anon to be able to reach these at all: the console signs
-- in before it calls anything.
--
-- HOW IT HAPPENED: the same trap as patch_197. Supabase grants EXECUTE on new
-- functions to `anon` and `authenticated` EXPLICITLY, so the
-- `REVOKE ALL ... FROM public` these patches were written with removes the
-- PUBLIC grant and leaves the role grants untouched.
--
-- Loops over pg_proc rather than listing names: overloads have to be revoked
-- per-signature, and a hand-written list goes stale the next time an admin
-- RPC is added.

-- BOTH grant paths have to go, and they are not the same trap.
--
-- patch_197's lesson was that `REVOKE ... FROM public` leaves Supabase's
-- EXPLICIT grants to anon/authenticated in place. The first version of this
-- patch therefore revoked from `anon` — and left four functions still
-- reachable, because those four had no anon grant at all: their ACL read
-- `=X/postgres`, the PUBLIC grant, which anon inherits.
--
-- So the two traps are mirror images, and a function can carry either or
-- both. Revoke PUBLIC and anon on every pass; whichever is absent is a no-op.
DO $$
DECLARE
  fn RECORD;
BEGIN
  FOR fn IN
    SELECT p.oid::regprocedure AS sig
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname LIKE 'admin\_%'
       AND has_function_privilege('anon', p.oid, 'EXECUTE')
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', fn.sig);
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon', fn.sig);
    -- Restated, because revoking PUBLIC can take `authenticated` with it when
    -- authenticated held nothing of its own. The console must keep working.
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', fn.sig);
    RAISE NOTICE 'locked down %', fn.sig;
  END LOOP;
END;
$$;

-- `authenticated` KEEPS execute. That is the console's only way in, and the
-- staff-role guard inside each function is what makes it safe — a signed-in
-- member who is not staff still gets 42501.
--
-- DELIBERATELY NOT TOUCHED: maintenance_status() and maintenance_active().
-- Both must stay callable by anon. The app checks maintenance at splash,
-- before anyone has signed in, and the whole point of the maintenance screen
-- is that it can explain itself to a signed-out user. Neither returns
-- anything private — a message the outage is meant to broadcast, and a
-- boolean.
