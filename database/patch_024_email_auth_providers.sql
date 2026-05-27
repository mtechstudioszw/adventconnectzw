-- =====================================================================
--  PATCH 024 — email_auth_providers RPC
--
--  WHY: The app needs to know whether a given email is bound to
--       email/password, Google OAuth, or both — so the auth screen
--       can route OAuth-only users to "Continue with Google"
--       instead of asking for a password they don't have.
--
--       The existing email_exists() RPC just answers yes/no on
--       presence; this one returns the provider mix.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.email_auth_providers(p_email text)
RETURNS text[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT COALESCE(
    array_agg(DISTINCT i.provider ORDER BY i.provider),
    ARRAY[]::text[]
  )
  FROM auth.users u
  JOIN auth.identities i ON i.user_id = u.id
  WHERE u.email = lower(p_email);
$$;

GRANT EXECUTE ON FUNCTION public.email_auth_providers(text)
  TO anon, authenticated;
