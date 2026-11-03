-- patch_310 — Security hardening: lock signed-out access, rate-limit every
-- member write, close the rate-limit and quiz-score loopholes (3 Nov 2026).
--
-- Owner: "I need maximum security … rate limiting in the entire app to
-- prevent spam from bots."
--
-- Found by the audit (Supabase security advisors + a policy walk):
--
--  1. 126 SECURITY DEFINER functions were executable by `anon` — anyone
--     holding the app's public key (it ships inside every APK), signed in
--     or not. Most refuse a missing auth.uid(), but every one is an attack
--     surface the app never needed. Now only the handful the sign-in /
--     sign-up screens use before a session exists stay open (allowlist
--     below), and new functions are no longer anon-executable by default.
--
--  2. check_and_consume_rate_limit() was callable by anyone with ANY
--     identity key and ANY limit. That let one person pump fake hits into
--     SOMEONE ELSE's counter — e.g. 300 hits on a victim's 'message_send'
--     and the victim cannot send a message for an hour. It is now
--     server-only; the one client use (password reset, before sign-in)
--     gets its own fixed-limit function, password_reset_allowed().
--
--  3. Sign-in lookups (email_exists) were limited per EMAIL only, so a bot
--     could test thousands of different addresses to find which have
--     accounts. Now also limited per network (client IP).
--
--  4. Only 7 tables had write limits. A bot account could post unlimited
--     likes, follows, prayers, listings, jobs, applications, Pages, seller
--     and verification applications, quiz scores… Every member-writable
--     table that a person (not the app's own sync) creates rows in now has
--     one, through the existing enforce_write_rate_limit() trigger. The
--     ceilings are far above any real member's day; they exist to stop
--     scripts, not people.
--
--  5. quiz_scores accepted unlimited self-inserted rows of up to 100,000
--     points each — anyone could put themselves top of the leaderboard.
--     Now rate-limited (a real player cannot finish 120 rounds a day).
--
--  6. 16 functions had a mutable search_path (search-path hijack class).
--     Pinned to public.
--
-- Not done here (needs the dashboard, see the handover): leaked-password
-- protection, auth endpoint rate limits, CAPTCHA, MFA enforcement.

BEGIN;

-- ===================================================== helpers

-- The caller's network address, as Supabase's gateway reports it. Used
-- only as a rate-limit key for signed-out lookups; never stored elsewhere.
CREATE OR REPLACE FUNCTION public.request_ip()
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $$
  SELECT NULLIF(btrim(split_part(COALESCE(
    (current_setting('request.headers', true)::json ->> 'x-forwarded-for'),
    (current_setting('request.headers', true)::json ->> 'cf-connecting-ip'),
    ''), ',', 1)), '');
$$;

-- ============================================ 3. sign-in lookups by IP

CREATE OR REPLACE FUNCTION public.email_exists(p_email text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_ip text := public.request_ip();
BEGIN
  -- Per email (as before) AND per network (patch 310), so a bot cannot
  -- walk a list of addresses to learn which have accounts.
  IF NOT public.check_and_consume_rate_limit(
       lower(coalesce(p_email, '')), 'email_exists', 30, 3600) THEN
    RAISE EXCEPTION 'Too many lookups. Try again later.' USING ERRCODE = 'P0001';
  END IF;
  IF v_ip IS NOT NULL AND NOT public.check_and_consume_rate_limit(
       'ip:' || v_ip, 'email_exists_ip', 60, 3600) THEN
    RAISE EXCEPTION 'Too many lookups. Try again later.' USING ERRCODE = 'P0001';
  END IF;

  RETURN EXISTS (SELECT 1 FROM auth.users WHERE lower(email) = lower(p_email));
END;
$function$;

-- ============================== 2. password reset gets its own check

CREATE OR REPLACE FUNCTION public.password_reset_allowed(p_email text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ip text := public.request_ip();
BEGIN
  -- Fixed limits the caller cannot choose: 3 per email per hour, 10 per
  -- network per hour.
  IF NOT public.check_and_consume_rate_limit(
       lower(btrim(coalesce(p_email, ''))), 'password_reset', 3, 3600) THEN
    RETURN false;
  END IF;
  IF v_ip IS NOT NULL AND NOT public.check_and_consume_rate_limit(
       'ip:' || v_ip, 'password_reset_ip', 10, 3600) THEN
    RETURN false;
  END IF;
  RETURN true;
END;
$function$;

-- ======================================== 4/5. write limits everywhere
-- (action, max, window seconds). Each is per member.

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    -- reactions / social
    ('post_likes',              'post_like',            1000, 86400),
    ('post_comment_reactions',  'comment_reaction',     1000, 86400),
    ('message_reactions',       'message_reaction',      500,  3600),
    ('story_likes',             'story_like',            500, 86400),
    ('follows',                 'follow',                200, 86400),
    ('page_follows',            'page_follow',           200, 86400),
    ('church_followers',        'church_follow',          30, 86400),
    ('blocked_users',           'block_user',            100, 86400),
    ('saved_posts',             'save_post',             500, 86400),
    ('saved_listings',          'save_listing',          500, 86400),
    ('saved_jobs',              'save_job',              500, 86400),
    -- prayer
    ('prayers',                 'prayer_create',          20, 86400),
    ('prayer_responses',        'prayer_response',       200, 86400),
    ('prayer_circles',          'prayer_circle_create',   10, 86400),
    ('prayer_circle_members',   'prayer_circle_join',    100, 86400),
    -- marketplace / jobs / events
    ('products',                'listing_create',         30, 86400),
    ('product_variants',        'variant_create',        300, 86400),
    ('seller_ratings',          'seller_rating',          30, 86400),
    ('jobs',                    'job_create',             15, 86400),
    ('job_applications',        'job_apply',              40, 86400),
    ('job_alerts',              'job_alert_create',       20, 86400),
    ('events',                  'event_create',           15, 86400),
    ('event_rsvps',             'event_rsvp',            100, 86400),
    -- applications that a person reviews (spam here costs staff time)
    ('pages',                   'page_create',             5, 86400),
    ('sellers',                 'seller_apply',            5, 86400),
    ('business_applications',   'business_apply',          5, 86400),
    ('verification_requests',   'verification_apply',      5, 86400),
    ('church_admins',           'church_admin_claim',     10, 86400),
    ('church_edit_suggestions', 'church_edit_suggest',    20, 86400),
    ('church_suggestions',      'church_suggest',         20, 86400),
    ('youtube_channel_submissions', 'channel_submit',     10, 86400),
    -- posts of other kinds
    ('advent_news',             'news_submit',            10, 86400),
    ('notices',                 'notice_create',          20, 86400),
    ('announcements',           'announcement_create',    30, 86400),
    ('announcement_reactions',  'announcement_reaction', 500, 86400),
    ('feedback',                'feedback_send',          20, 86400),
    ('signup_surveys',          'signup_survey',           5, 86400),
    ('fundraiser_contributions','fundraiser_contribution', 30, 86400),
    -- quiz (5: the leaderboard)
    ('quiz_scores',             'quiz_score',            120, 86400),
    ('quiz_challenges',         'quiz_challenge',         60, 86400),
    ('quiz_reports',            'quiz_report',            30, 86400)
  ) AS t(tbl, action, max, win)
  LOOP
    IF to_regclass('public.' || r.tbl) IS NULL THEN
      CONTINUE;
    END IF;
    EXECUTE format('DROP TRIGGER IF EXISTS trg_rate_limit_%s ON public.%I', r.tbl, r.tbl);
    EXECUTE format(
      'CREATE TRIGGER trg_rate_limit_%s BEFORE INSERT ON public.%I '
      'FOR EACH ROW EXECUTE FUNCTION public.enforce_write_rate_limit(%L, %L, %L)',
      r.tbl, r.tbl, r.action, r.max::text, r.win::text);
  END LOOP;
END $$;

-- ===================================================== 6. search_path

DO $$
DECLARE f record;
BEGIN
  FOR f IN
    SELECT p.oid::regprocedure AS sig
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.prokind = 'f'
       AND p.proname IN ('call_error', 'clamp_message_sent_at', 'notif_actor_name',
         'stamp_prayer_answered_at', 'is_essential_notification',
         'subscriptions_lock_owner', 'staff_rank', 'quiz_week_start',
         'quiz_multiplier_for', 'quiz_points_for', 'quiz_room_new_code')
       AND NOT EXISTS (SELECT 1 FROM unnest(coalesce(p.proconfig, '{}')) c
                        WHERE c LIKE 'search_path=%')
  LOOP
    EXECUTE format('ALTER FUNCTION %s SET search_path = public', f.sig);
  END LOOP;
END $$;

-- ================================================== 1/2. function access

DO $$
DECLARE
  f record;
  -- What the sign-in, sign-up, password-reset and maintenance screens call
  -- BEFORE a session exists. Everything else needs a signed-in member.
  v_anon_ok constant text[] := ARRAY[
    'email_exists', 'email_auth_providers', 'register_otp_resend',
    'password_reset_allowed', 'maintenance_status', 'maintenance_active',
    -- Yes/no helpers that table policies applying to signed-out readers
    -- call (share pages read events, products, pages, posts as anon).
    -- Locking these would make those policies error, not deny.
    'is_super_admin', 'page_is_visible', 'page_role', 'can_edit_page',
    'can_see_profile_content', 'is_circle_member'];
BEGIN
  FOR f IN
    SELECT p.oid, p.oid::regprocedure AS sig, p.proname
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.prokind = 'f'
       AND has_function_privilege('anon', p.oid, 'EXECUTE')
       AND NOT (p.proname = ANY (v_anon_ok))
  LOOP
    -- Keep signed-in access exactly as it was: make an implicit (PUBLIC)
    -- grant explicit before removing PUBLIC.
    IF has_function_privilege('authenticated', f.oid, 'EXECUTE') THEN
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', f.sig);
    END IF;
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', f.sig);
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', f.sig);
  END LOOP;

  -- The allowlist: explicitly open to signed-out callers.
  FOR f IN
    SELECT p.oid::regprocedure AS sig
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = ANY (v_anon_ok)
  LOOP
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO anon, authenticated, service_role', f.sig);
  END LOOP;
END $$;

-- The rate-limit counter is server-only (loophole 2).
REVOKE EXECUTE ON FUNCTION public.check_and_consume_rate_limit(text, text, integer, integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_and_consume_rate_limit(text, text, integer, integer)
  TO service_role;
REVOKE EXECUTE ON FUNCTION public.request_ip() FROM PUBLIC, anon, authenticated;

-- New functions are no longer signed-out-callable by default.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  GRANT EXECUTE ON FUNCTIONS TO authenticated, service_role;

COMMIT;
