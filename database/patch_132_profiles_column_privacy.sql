-- =====================================================================
--  PATCH 132 — stop other users reading your FCM push token
--
--  RLS on `profiles` is row-level: a discoverable profile row is readable by
--  any authenticated user (that's how the directory / search / suggestions
--  work). But the row also contains `fcm_token` — your Firebase push token —
--  so a crafted REST query (`?select=fcm_token`) could read other people's
--  device tokens. The app NEVER reads fcm_token from the client (it's only
--  ever written via update / claim_fcm_token, and read by SECURITY DEFINER
--  notify functions that run as the table owner), so we lock the column at
--  the privilege level.
--
--  Mechanism: Postgres column privileges only take effect once the blanket
--  table-level SELECT is removed, so we revoke table SELECT and re-grant it
--  for every column EXCEPT fcm_token. Generated dynamically so it stays
--  correct as columns evolve (new columns are hidden until granted —
--  fail-closed, which is the safe default).
--
--  anon gets no SELECT at all (the discoverable policy already requires an
--  authenticated session; this is belt-and-braces).
-- =====================================================================

DO $$
DECLARE cols text;
BEGIN
  SELECT string_agg(quote_ident(column_name), ', ')
    INTO cols
    FROM information_schema.columns
   WHERE table_schema = 'public'
     AND table_name = 'profiles'
     AND column_name <> 'fcm_token';

  REVOKE SELECT ON public.profiles FROM anon, authenticated;
  EXECUTE format('GRANT SELECT (%s) ON public.profiles TO authenticated', cols);
END $$;
