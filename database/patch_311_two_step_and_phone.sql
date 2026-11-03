-- patch_311 — Server side of two-step login and phone verification, and
-- upload size caps on chat storage (3 Nov 2026).
--
-- Run AFTER patch_310. Safe to run twice.
--
--  1. mfa_ok(): a member who turned two-step on must have passed the code
--     (session aal2) to read or write messages, conversations, reactions,
--     calls, encryption keys and chat files. The app already stops at the
--     code screen; this stops someone using a stolen password-only token
--     against the API directly. Members WITHOUT two-step are unaffected.
--
--  2. admin_reset_two_step(user): support's way back in for a member who
--     lost the phone with their authenticator. Super admins only.
--
--  3. phone_ok(): phone verification, OFF until the owner switches it on
--     (app_config.require_phone_verification = 'true', which needs an SMS
--     provider set up in Supabase first — see docs/SECURITY_HANDOVER.md).
--     When on, an account created after phone_verification_cutoff cannot
--     post, comment, message, add friends, list products or jobs, pray
--     publicly or post stories until its phone is confirmed. One phone
--     number can belong to only one account (Supabase Auth enforces that
--     itself). Existing accounts, staff and the App Review demo account
--     are exempt.
--
--  4. chat_media / voice_notes had NO size limit: a bot could fill storage
--     (and the bill) with multi-gigabyte uploads. Now 50 MB / 20 MB.

BEGIN;

-- ============================================================ 1. mfa_ok

CREATE OR REPLACE FUNCTION public.mfa_ok()
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO ''
AS $$
  SELECT coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
      OR NOT EXISTS (
           SELECT 1 FROM auth.mfa_factors f
            WHERE f.user_id = auth.uid() AND f.status = 'verified');
$$;
REVOKE EXECUTE ON FUNCTION public.mfa_ok() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mfa_ok() TO authenticated, service_role;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['messages', 'conversations', 'conversation_participants',
      'message_reactions', 'calls', 'call_participants', 'e2ee_devices',
      'e2ee_prekeys', 'e2ee_signed_prekeys', 'chat_backup_keys']
  LOOP
    IF to_regclass('public.' || t) IS NULL THEN CONTINUE; END IF;
    EXECUTE format('DROP POLICY IF EXISTS two_step_required ON public.%I', t);
    -- RESTRICTIVE: ANDed with every existing policy, so it can only take
    -- access away, never grant it. `(select …)` evaluates once per query.
    EXECUTE format(
      'CREATE POLICY two_step_required ON public.%I AS RESTRICTIVE FOR ALL '
      'TO authenticated USING ((SELECT public.mfa_ok())) '
      'WITH CHECK ((SELECT public.mfa_ok()))', t);
  END LOOP;
END $$;

DROP POLICY IF EXISTS two_step_required_chat_files ON storage.objects;
CREATE POLICY two_step_required_chat_files ON storage.objects
  AS RESTRICTIVE FOR ALL TO authenticated
  USING (bucket_id NOT IN ('chat_media', 'voice_notes', 'chat_backups')
         OR (SELECT public.mfa_ok()))
  WITH CHECK (bucket_id NOT IN ('chat_media', 'voice_notes', 'chat_backups')
         OR (SELECT public.mfa_ok()));

-- ============================================== 2. support reset of 2-step

CREATE OR REPLACE FUNCTION public.admin_reset_two_step(p_user uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $$
DECLARE n integer;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Not allowed' USING ERRCODE = '42501';
  END IF;
  DELETE FROM auth.mfa_factors WHERE user_id = p_user;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_reset_two_step(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_reset_two_step(uuid) TO authenticated, service_role;

-- ===================================================== 3. phone_ok

INSERT INTO public.app_config (key, value, updated_at) VALUES
  ('require_phone_verification', 'false', now()),
  -- Accounts created before this moment never need it.
  ('phone_verification_cutoff', to_char(now() AT TIME ZONE 'UTC',
     'YYYY-MM-DD"T"HH24:MI:SS"Z"'), now())
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.phone_ok()
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO ''
AS $$
  SELECT coalesce((SELECT value FROM public.app_config
                    WHERE key = 'require_phone_verification'), 'false') <> 'true'
      OR EXISTS (
           SELECT 1 FROM auth.users u
            WHERE u.id = auth.uid()
              AND (u.phone_confirmed_at IS NOT NULL
                   OR u.created_at < coalesce(
                        (SELECT nullif(value, '')::timestamptz FROM public.app_config
                          WHERE key = 'phone_verification_cutoff'), '-infinity')
                   -- App Review demo account (never lock the reviewer out).
                   OR lower(u.email) = 'adiswamikuwa@gmail.com'))
      OR EXISTS (SELECT 1 FROM public.profiles p
                  WHERE p.id = auth.uid() AND p.is_super_admin);
$$;
REVOKE EXECUTE ON FUNCTION public.phone_ok() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.phone_ok() TO authenticated, service_role;

-- What the app asks to decide whether to show the "verify your phone"
-- screen: 'ok' or 'required'.
CREATE OR REPLACE FUNCTION public.my_phone_status()
 RETURNS text
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO ''
AS $$
  SELECT CASE WHEN public.phone_ok() THEN 'ok' ELSE 'required' END;
$$;
REVOKE EXECUTE ON FUNCTION public.my_phone_status() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_phone_status() TO authenticated;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['posts', 'post_comments', 'messages', 'conversations',
      'friendships', 'products', 'jobs', 'prayers', 'stories', 'events']
  LOOP
    IF to_regclass('public.' || t) IS NULL THEN CONTINUE; END IF;
    EXECUTE format('DROP POLICY IF EXISTS phone_verified_to_create ON public.%I', t);
    EXECUTE format(
      'CREATE POLICY phone_verified_to_create ON public.%I AS RESTRICTIVE '
      'FOR INSERT TO authenticated WITH CHECK ((SELECT public.phone_ok()))', t);
  END LOOP;
END $$;

-- ============================================ 4. chat storage size caps

UPDATE storage.buckets SET file_size_limit = 52428800 WHERE id = 'chat_media'
   AND file_size_limit IS NULL;
UPDATE storage.buckets SET file_size_limit = 20971520 WHERE id = 'voice_notes'
   AND file_size_limit IS NULL;

COMMIT;
