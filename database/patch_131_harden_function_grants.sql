-- =====================================================================
--  PATCH 131 — lock down the SECURITY DEFINER RPC surface
--
--  Security advisor flagged ~111 SECURITY DEFINER functions in `public`
--  executable by the `anon` role via /rest/v1/rpc/*. Most should not be
--  callable by an unauthenticated client:
--    * 42 are TRIGGER functions — never meant to be called as RPCs at all.
--    * The rest are authenticated-only operations (groups, messaging,
--      friends, admin, etc.) that already no-op for anon (auth.uid() is
--      null) but shouldn't even be reachable.
--
--  This migration:
--    * Revokes EXECUTE on every trigger-returning SECURITY DEFINER function
--      from PUBLIC/anon/authenticated (triggers run as the table owner).
--    * For every other SECURITY DEFINER function: revokes EXECUTE from
--      PUBLIC/anon and grants it to `authenticated` only — EXCEPT the small
--      pre-login allowlist that the app legitimately calls before a session
--      exists (email existence/provider lookup, OTP + login rate limits).
--
--  Idempotent and resilient: each function is handled in its own block so a
--  permission hiccup on one never aborts the whole pass.
-- =====================================================================

DO $$
DECLARE
  r record;
  -- Functions the UNAUTHENTICATED app must still call (auth_service.dart):
  anon_allow text[] := ARRAY[
    'email_exists',
    'email_auth_providers',
    'register_otp_resend',
    'check_and_consume_rate_limit'
  ];
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure::text AS sig,
           p.proname,
           (p.prorettype = 'pg_catalog.trigger'::regtype) AS is_trigger
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.prosecdef
  LOOP
    BEGIN
      IF r.is_trigger THEN
        EXECUTE format(
          'REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated',
          r.sig);
      ELSIF r.proname = ANY(anon_allow) THEN
        -- Pre-login functions: keep reachable by anon + authenticated.
        EXECUTE format(
          'GRANT EXECUTE ON FUNCTION %s TO anon, authenticated', r.sig);
      ELSE
        EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', r.sig);
        EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', r.sig);
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'skip % : %', r.sig, SQLERRM;
    END;
  END LOOP;
END $$;

-- Pin search_path on the trigger/helper functions the advisor flagged as
-- mutable (defence against search_path hijacking).
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure::text AS sig
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname IN (
         'set_updated_at','recompute_seller_rating','touch_friendships_updated_at',
         'touch_post_comment_reactions_updated_at','sellers_one_per_user_guard'
       )
  LOOP
    BEGIN
      EXECUTE format('ALTER FUNCTION %s SET search_path = public', r.sig);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'skip search_path % : %', r.sig, SQLERRM;
    END;
  END LOOP;
END $$;
