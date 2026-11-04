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
--     When on, EVERY account (owner, 4 Nov 2026: "once the update is live
--     everyone is required to verify … if it's not verified the account
--     will no longer work, no notification or anything") must confirm a
--     phone number:
--       * the app shows only the verify screen (client side);
--       * the database refuses new posts, comments, messages, friend
--         requests, listings, jobs, prayers, stories, events and calls;
--       * no notification is created for it, so no push either;
--       * nobody's call rings it.
--     One phone number can belong to only one account (Supabase Auth
--     enforces that itself). Exempt: super admins and the App Review demo
--     account. To exempt accounts created before a date instead, set
--     app_config.phone_verification_cutoff to that ISO date.
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
  -- Empty = nobody is exempt by age (the owner's call: everyone).
  ('phone_verification_cutoff', '', now())
ON CONFLICT (key) DO NOTHING;

-- For ANY account — used by the notification and call-ring gates below,
-- which run without a signed-in user.
CREATE OR REPLACE FUNCTION public.phone_ok_for(p_user uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO ''
AS $$
  SELECT p_user IS NULL
      OR coalesce((SELECT value FROM public.app_config
                    WHERE key = 'require_phone_verification'), 'false') <> 'true'
      OR EXISTS (
           SELECT 1 FROM auth.users u
            WHERE u.id = p_user
              AND (u.phone_confirmed_at IS NOT NULL
                   OR u.created_at < coalesce(
                        (SELECT nullif(value, '')::timestamptz FROM public.app_config
                          WHERE key = 'phone_verification_cutoff'), '-infinity')
                   -- App Review demo account (never lock the reviewer out).
                   OR lower(u.email) = 'adiswamikuwa@gmail.com'))
      OR EXISTS (SELECT 1 FROM public.profiles p
                  WHERE p.id = p_user AND p.is_super_admin);
$$;
REVOKE EXECUTE ON FUNCTION public.phone_ok_for(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.phone_ok_for(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.phone_ok()
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO ''
AS $$
  SELECT public.phone_ok_for(auth.uid());
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
      'friendships', 'products', 'jobs', 'prayers', 'stories', 'events',
      'calls', 'prayer_responses', 'post_likes', 'follows', 'quiz_scores']
  LOOP
    IF to_regclass('public.' || t) IS NULL THEN CONTINUE; END IF;
    EXECUTE format('DROP POLICY IF EXISTS phone_verified_to_create ON public.%I', t);
    EXECUTE format(
      'CREATE POLICY phone_verified_to_create ON public.%I AS RESTRICTIVE '
      'FOR INSERT TO authenticated WITH CHECK ((SELECT public.phone_ok()))', t);
  END LOOP;
END $$;

-- No notifications (and so no pushes) for an account that must verify.
-- INSERT only, so RETURN NULL here deliberately skips the row; it is not
-- the BEFORE-DELETE trap from patch 189.
CREATE OR REPLACE FUNCTION public.skip_notifications_until_phone_verified()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
BEGIN
  IF NOT public.phone_ok_for(NEW.user_id) THEN
    RETURN NULL;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_skip_notifications_until_phone_verified ON public.notifications;
CREATE TRIGGER trg_skip_notifications_until_phone_verified
  BEFORE INSERT ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public.skip_notifications_until_phone_verified();

-- Nobody's call rings an account that must verify. Same function as live
-- (patch 263) with one gate added; cancels still go out.
CREATE OR REPLACE FUNCTION public.call_dispatch(p_call uuid, p_user uuid, p_action text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'net'
AS $function$
DECLARE
  v_url    TEXT := public.call_cfg_text_safe('call.push_endpoint', '');
  v_secret TEXT := public.call_push_secret();
BEGIN
  IF v_url = '' THEN RETURN; END IF;
  IF p_action = 'ring' AND NOT public.phone_ok_for(p_user) THEN RETURN; END IF;

  IF v_secret IS NULL OR length(v_secret) = 0 THEN
    PERFORM public.call_log_event(p_call, p_user, 'push_unconfigured',
      jsonb_build_object('reason', 'no vault secret call_push_secret'));
    RETURN;
  END IF;

  PERFORM net.http_post(
    url     := v_url,
    headers := jsonb_build_object(
                 'Content-Type',  'application/json',
                 'x-call-secret', v_secret),
    body    := jsonb_build_object(
                 'call_id', p_call,
                 'user_id', p_user,
                 'action',  p_action),
    timeout_milliseconds := 5000
  );
EXCEPTION WHEN OTHERS THEN
  PERFORM public.call_log_event(p_call, p_user, 'push_failed',
    jsonb_build_object('code', SQLSTATE));
END;
$function$;

-- ============================================ 4. chat storage size caps

UPDATE storage.buckets SET file_size_limit = 52428800 WHERE id = 'chat_media'
   AND file_size_limit IS NULL;
UPDATE storage.buckets SET file_size_limit = 20971520 WHERE id = 'voice_notes'
   AND file_size_limit IS NULL;

COMMIT;
