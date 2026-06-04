-- =====================================================================
--  PATCH 041 — Fix email_exists / email_auth_providers (signature drift)
--
--  BUG: patch_028 wrote email_exists() + email_auth_providers() to
--       rate-limit themselves via
--         check_and_consume_rate_limit(p_key, p_window_seconds, p_max_hits)
--       But check_and_consume_rate_limit was later REDEFINED (patch_036
--       era) with a different signature:
--         check_and_consume_rate_limit(p_identity_key, p_action_key,
--                                      p_max, p_window_seconds)
--       So both lookups raised 42883 "function does not exist" on every
--       call. The app's _onContinue treats that failure as "couldn't
--       verify this email" and dead-ends the user at the email field —
--       blocking ALL email sign-up + sign-in. (Google tolerated the
--       null and still worked, which is why it wasn't obvious.)
--
--  FIX: re-create both functions calling the CURRENT 4-arg signature.
--       Behaviour is unchanged otherwise (30 lookups / hour / email).
--
--  IDEMPOTENT: CREATE OR REPLACE.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.email_exists(p_email TEXT)
RETURNS BOOLEAN AS $$
DECLARE
  allowed BOOLEAN;
BEGIN
  SELECT public.check_and_consume_rate_limit(
    p_identity_key   := lower(coalesce(p_email, '')),
    p_action_key     := 'email_exists',
    p_max            := 30,
    p_window_seconds := 3600
  ) INTO allowed;

  IF NOT allowed THEN
    RAISE EXCEPTION 'Too many lookups. Try again later.'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN EXISTS (
    SELECT 1 FROM auth.users WHERE lower(email) = lower(p_email)
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

REVOKE ALL ON FUNCTION public.email_exists(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.email_exists(TEXT) TO anon, authenticated;


CREATE OR REPLACE FUNCTION public.email_auth_providers(p_email TEXT)
RETURNS TEXT[] AS $$
DECLARE
  providers TEXT[];
  allowed BOOLEAN;
BEGIN
  SELECT public.check_and_consume_rate_limit(
    p_identity_key   := lower(coalesce(p_email, '')),
    p_action_key     := 'email_auth_providers',
    p_max            := 30,
    p_window_seconds := 3600
  ) INTO allowed;

  IF NOT allowed THEN
    RAISE EXCEPTION 'Too many lookups. Try again later.'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT ARRAY_AGG(DISTINCT provider) INTO providers
    FROM auth.identities i
    JOIN auth.users u ON u.id = i.user_id
    WHERE lower(u.email) = lower(p_email);

  RETURN COALESCE(providers, ARRAY[]::TEXT[]);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

REVOKE ALL ON FUNCTION public.email_auth_providers(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.email_auth_providers(TEXT) TO anon, authenticated;
