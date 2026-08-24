-- =====================================================================
--  PATCH 254 — take EXECUTE on the fundraiser RPCs away from `anon`
--
--  WHAT WAS FOUND (24 Aug 2026, reviewing patch_253 before building the
--  admin console on top of it)
--
--  All seven functions patch_253 created were executable by the `anon`
--  role, including the two that move money:
--
--    fundraiser_status, fundraiser_record_pledge, fundraiser_dismiss,
--    fundraiser_list_pending, fundraiser_confirm_contribution,
--    fundraiser_reject_contribution, fundraiser_force_pending
--
--  NOT a live vulnerability, and it is worth being precise about why
--  rather than overstating it. Each of the three admin functions calls
--  `is_super_admin()` first, and the member-facing ones read
--  `auth.uid()`. Both are NULL for an unauthenticated caller, so anon
--  reaches an exception or an empty result and never data.
--
--  It is still wrong, for exactly the reason patch_199 already had to be
--  written for the `admin_*` family: the guard becomes the ONLY thing
--  between an unauthenticated request and
--  `fundraiser_confirm_contribution` — the one function in this feature
--  that can raise the public total. One regression in one guard turns a
--  defence-in-depth gap into remote fund manipulation with no login.
--  There is no reason for anon to reach these at all; the app signs in
--  before it calls anything.
--
--  HOW IT HAPPENED — and the correction that matters
--
--  The first version of this patch did `REVOKE ALL ... FROM anon`,
--  following patch_199's stated reasoning that Supabase grants EXECUTE
--  to `anon` and `authenticated` explicitly. It applied cleanly, and
--  changed nothing: anon still had EXECUTE on all seven afterwards.
--
--  The actual ACL says why:
--
--    =X/postgres | postgres=X/postgres | authenticated=X/postgres | ...
--    ^
--    an EMPTY grantee before the '=' is PUBLIC
--
--  Postgres grants EXECUTE on every new function to PUBLIC by default.
--  `anon` was never granted anything directly — it inherits from
--  PUBLIC, and `REVOKE ... FROM anon` cannot remove a privilege the role
--  does not directly hold. The revoke succeeded and was a no-op.
--
--  So the fix is `REVOKE ... FROM PUBLIC`. The explicit
--  `authenticated=X` and `service_role=X` entries survive that, which is
--  exactly what we want; they are re-stated below anyway.
--
--  Verify with `proacl`, never with has_function_privilege('anon',...)
--  alone: that answers "can anon execute this", not "where does the
--  privilege come from", and the two questions have different fixes.
--
--  Loops over pg_proc rather than naming functions, so that overloads
--  and anything added to the family later are covered too.
--
--  IDEMPOTENT: yes.
-- =====================================================================

DO $$
DECLARE
  r RECORD;
  v_n INTEGER := 0;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname LIKE 'fundraiser%'
  LOOP
    -- PUBLIC first: this is the one that actually reaches anon.
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', r.sig);
    -- Then anon by name, in case a future patch grants it directly.
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon', r.sig);
    v_n := v_n + 1;
  END LOOP;
  RAISE NOTICE 'patch_254: revoked PUBLIC + anon on % fundraiser function(s)', v_n;
END $$;


-- Re-state what `authenticated` must keep. The REVOKE above only named
-- anon, so these are already intact — but stating them makes the
-- intended grant list explicit in one place, and makes the patch safe
-- to re-run against a database where someone has since revoked more
-- broadly.
--
-- The three admin functions stay reachable by `authenticated` on
-- purpose: the founder calls them from the in-app admin queue as a
-- signed-in super admin. `is_super_admin()` inside each one is what
-- actually gates them.
GRANT EXECUTE ON FUNCTION public.fundraiser_status() TO authenticated;
GRANT EXECUTE ON FUNCTION public.fundraiser_dismiss() TO authenticated;
GRANT EXECUTE ON FUNCTION public.fundraiser_record_pledge(INTEGER, TEXT, TEXT)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.fundraiser_list_pending() TO authenticated;
GRANT EXECUTE ON FUNCTION public.fundraiser_confirm_contribution(BIGINT, INTEGER)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.fundraiser_reject_contribution(BIGINT, TEXT)
  TO authenticated;

-- fundraiser_force_pending() is a trigger function. It is invoked by the
-- trigger as the table owner and needs no role grant at all, which is
-- why it is absent above and why revoking anon on it changes nothing.


-- =====================================================================
--  VERIFICATION
-- =====================================================================
-- Every fundraiser function: anon false, authenticated true
-- (except force_pending, which needs neither).
--
--   SELECT p.proname,
--          has_function_privilege('anon',          p.oid, 'EXECUTE') AS anon,
--          has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth
--     FROM pg_proc p
--     JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname = 'public' AND p.proname LIKE 'fundraiser%'
--    ORDER BY p.proname;
--
--   -- expect anon = f on every row.
--
-- Then confirm WHERE the privilege went, which is the check the first
-- version of this patch was missing. No bare '=X/...' entry may remain:
--
--   SELECT p.proname, array_to_string(p.proacl, ' | ') AS acl
--     FROM pg_proc p
--     JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname = 'public' AND p.proname LIKE 'fundraiser%'
--    ORDER BY p.proname;
--
--   -- expect: postgres=X/postgres | authenticated=X/postgres |
--   --         service_role=X/postgres
--   -- a leading '=X/postgres' means PUBLIC still holds it and the
--   -- revoke did not take.
--
-- And the feature still works for a signed-in member:
--   SELECT campaign_key, status, goal_cents, raised_cents
--     FROM public.fundraiser_status();
-- =====================================================================
