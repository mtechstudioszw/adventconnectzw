-- patch_314 — Web console: gold tick review, quiz reports, hymn matching,
-- app settings, two-step reset with audit (owner, 4 Nov 2026: "add new
-- admin features in the admin dashboard … rather than using in app").
--
-- Same security model as every other admin_* function (admin/README.md):
--   * SECURITY DEFINER, and the FIRST statement checks the caller's staff
--     role (assert_staff) — or super admin, where ID documents are involved;
--   * every change is written to admin_audit_log via log_admin_action;
--   * EXECUTE for signed-in users only (the check inside does the rest),
--     never anon.
-- Safe to run twice.

BEGIN;

-- ============================================== 1. gold tick ID checks
-- Super admin only: these rows point at people's ID documents and selfies.

CREATE OR REPLACE FUNCTION public.admin_list_verifications(p_status text DEFAULT 'pending')
 RETURNS TABLE (
   id uuid, user_id uuid, member_name text, legal_name text, kind text,
   category text, page_id uuid, status text, reason text,
   created_at timestamptz, reviewed_at timestamptz,
   id_doc_path text, selfie_path text,
   paying boolean, plan text)
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Not authorized.' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
  SELECT r.id, r.user_id, p.full_name, r.legal_name, r.kind, r.category,
         r.page_id, r.status, r.reason, r.created_at, r.reviewed_at,
         r.id_doc_path, r.selfie_path,
         (coalesce(p.premium_until > now(), false)
            OR coalesce(p.verified_until > now(), false)),
         CASE
           WHEN coalesce(p.premium_until > now(), false)
             THEN 'Premium ' || coalesce(p.premium_tier, 'plus')
           WHEN coalesce(p.verified_until > now(), false) THEN 'Verified plan'
           ELSE 'Not paying'
         END
    FROM public.verification_requests r
    LEFT JOIN public.profiles p ON p.id = r.user_id
   WHERE p_status = 'all' OR r.status = p_status
   ORDER BY r.created_at DESC
   LIMIT 200;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_review_verification(
  p_id uuid, p_action text, p_reason text DEFAULT NULL)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
  v_result text;
  v_user uuid;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'Not authorized.' USING ERRCODE = '42501';
  END IF;
  SELECT r.user_id INTO v_user FROM public.verification_requests r WHERE r.id = p_id;
  -- The existing review (decides, notifies the member, recomputes the tick).
  v_result := public.review_verification(p_id, p_action, p_reason);
  PERFORM public.log_admin_action(
    'verification_' || p_action, 'verification', p_id::text,
    NULL, jsonb_build_object('user_id', v_user), NULLIF(trim(p_reason), ''));
  RETURN v_result;
END;
$$;

-- ================================================== 2. quiz reports

CREATE OR REPLACE FUNCTION public.admin_list_quiz_reports(p_resolved boolean DEFAULT false)
 RETURNS TABLE (
   id bigint, question_id text, is_generated boolean, question_text text,
   reason text, reporter text, created_at timestamptz, resolved boolean,
   options jsonb, correct_index integer, explanation text, reference text,
   is_published boolean)
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
BEGIN
  PERFORM public.assert_staff('moderator');
  RETURN QUERY
  SELECT r.id, r.question_id, r.is_generated, r.question_text, r.reason,
         p.full_name, r.created_at, r.resolved,
         q.options, q.correct_index, q.explanation, q.reference, q.is_published
    FROM public.quiz_reports r
    LEFT JOIN public.profiles p ON p.id = r.reported_by
    LEFT JOIN public.quiz_questions q
      ON NOT r.is_generated AND r.question_id ~ '^[0-9]+$'
     AND q.id = r.question_id::bigint
   WHERE r.resolved = p_resolved
   ORDER BY r.created_at DESC
   LIMIT 300;
END;
$$;

-- Close a report; optionally take the question out of the game.
CREATE OR REPLACE FUNCTION public.admin_resolve_quiz_report(
  p_id bigint, p_unpublish boolean DEFAULT false, p_note text DEFAULT NULL)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
  r public.quiz_reports%ROWTYPE;
BEGIN
  PERFORM public.assert_staff('moderator');
  SELECT * INTO r FROM public.quiz_reports qr WHERE qr.id = p_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No such report.' USING ERRCODE = 'P0002';
  END IF;
  UPDATE public.quiz_reports qr SET resolved = true WHERE qr.id = p_id;
  IF p_unpublish AND NOT r.is_generated AND r.question_id ~ '^[0-9]+$' THEN
    UPDATE public.quiz_questions qq SET is_published = false
     WHERE qq.id = r.question_id::bigint;
  END IF;
  PERFORM public.log_admin_action(
    CASE WHEN p_unpublish THEN 'quiz_question_unpublished' ELSE 'quiz_report_dismissed' END,
    'quiz_report', p_id::text, NULL,
    jsonb_build_object('question_id', r.question_id), NULLIF(trim(p_note), ''));
END;
$$;

-- =================================================== 3. hymn matching
-- Kristu MuNzwiyo (Christ in Song) number -> SDA Hymnal number. Drives the
-- "Also in" switch inside a hymn in the app (HymnLinkService).

CREATE OR REPLACE FUNCTION public.admin_list_hymn_links()
 RETURNS TABLE (cis_number integer, cis_title text, sda_number integer, sda_title text)
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
BEGIN
  PERFORM public.assert_staff('viewer');
  RETURN QUERY
  SELECT k.number, k.title, l.sda_number, s.title
    FROM public.hymns k
    LEFT JOIN public.hymn_links l ON l.cis_number = k.number
    LEFT JOIN public.hymns s
      ON s.collection = 'sda_hymnal' AND s.number = l.sda_number
   WHERE k.collection = 'kristu_munzwiyo'
   ORDER BY k.number;
END;
$$;

-- p_links: [{"cis": 1, "sda": 612}, {"cis": 2, "sda": null}, …]
-- null (or 0) removes that hymn's link. Every SDA number must exist.
CREATE OR REPLACE FUNCTION public.admin_set_hymn_links(p_links jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
  e jsonb;
  v_cis integer;
  v_sda integer;
  n integer := 0;
BEGIN
  PERFORM public.assert_staff('manager');
  IF jsonb_typeof(p_links) <> 'array' THEN
    RAISE EXCEPTION 'Expected a list.' USING ERRCODE = '22023';
  END IF;
  FOR e IN SELECT * FROM jsonb_array_elements(p_links) LOOP
    v_cis := (e ->> 'cis')::integer;
    v_sda := nullif((e ->> 'sda'), '')::integer;
    IF v_sda = 0 THEN v_sda := NULL; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.hymns h
                    WHERE h.collection = 'kristu_munzwiyo' AND h.number = v_cis) THEN
      RAISE EXCEPTION 'Kristu MuNzwiyo has no hymn %.', v_cis USING ERRCODE = '22023';
    END IF;
    IF v_sda IS NULL THEN
      DELETE FROM public.hymn_links hl WHERE hl.cis_number = v_cis;
    ELSE
      IF NOT EXISTS (SELECT 1 FROM public.hymns h
                      WHERE h.collection = 'sda_hymnal' AND h.number = v_sda) THEN
        RAISE EXCEPTION 'The SDA Hymnal has no hymn % (for Kristu MuNzwiyo %).', v_sda, v_cis
          USING ERRCODE = '22023';
      END IF;
      INSERT INTO public.hymn_links (cis_number, sda_number, updated_at, updated_by)
      VALUES (v_cis, v_sda, now(), auth.uid())
      ON CONFLICT ON CONSTRAINT hymn_links_pkey DO UPDATE
        SET sda_number = excluded.sda_number, updated_at = now(),
            updated_by = auth.uid();
    END IF;
    n := n + 1;
  END LOOP;
  PERFORM public.log_admin_action('hymn_links_saved', 'hymn_links', NULL,
    NULL, jsonb_build_object('count', n), NULL);
  RETURN n;
END;
$$;

-- ==================================================== 4. app settings
-- An allowlist, never "any key": app_config also holds AI pricing, call
-- limits and the fundraiser, which have their own screens or none.

CREATE OR REPLACE FUNCTION public.admin_get_app_settings()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
BEGIN
  PERFORM public.assert_staff('viewer');
  RETURN (SELECT coalesce(jsonb_object_agg(c.key, c.value), '{}'::jsonb)
            FROM public.app_config c
           WHERE c.key IN ('min_build_android', 'latest_build_android',
                         'min_build_ios', 'latest_build_ios', 'update_grace_days',
                         'captcha_site_key', 'require_phone_verification',
                         'ai_service_state'));
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_app_setting(p_key text, p_value text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
  v_old text;
  v text := btrim(coalesce(p_value, ''));
BEGIN
  PERFORM public.assert_staff('owner');
  IF p_key IN ('min_build_android', 'latest_build_android',
               'min_build_ios', 'latest_build_ios', 'update_grace_days') THEN
    IF v !~ '^[0-9]{1,6}$' THEN
      RAISE EXCEPTION 'Use a whole number.' USING ERRCODE = '22023';
    END IF;
  ELSIF p_key = 'require_phone_verification' THEN
    IF v NOT IN ('true', 'false') THEN
      RAISE EXCEPTION 'Use true or false.' USING ERRCODE = '22023';
    END IF;
  ELSIF p_key = 'ai_service_state' THEN
    IF v NOT IN ('live', 'suspended') THEN
      RAISE EXCEPTION 'Use live or suspended.' USING ERRCODE = '22023';
    END IF;
  ELSIF p_key = 'captcha_site_key' THEN
    IF v <> '' AND v !~ '^[0-9A-Za-z_-]{10,100}$' THEN
      RAISE EXCEPTION 'That does not look like a Turnstile site key.' USING ERRCODE = '22023';
    END IF;
  ELSE
    RAISE EXCEPTION 'That setting cannot be changed here.' USING ERRCODE = '22023';
  END IF;

  SELECT c.value INTO v_old FROM public.app_config c WHERE c.key = p_key;
  INSERT INTO public.app_config (key, value, updated_at)
  VALUES (p_key, v, now())
  ON CONFLICT (key) DO UPDATE SET value = excluded.value, updated_at = now();

  PERFORM public.log_admin_action('app_setting_changed', 'app_config', p_key,
    jsonb_build_object('value', v_old), jsonb_build_object('value', v), NULL);
END;
$$;

-- ============================================ 5. two-step reset, audited

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
  PERFORM public.log_admin_action('two_step_reset', 'user', p_user::text,
    NULL, jsonb_build_object('factors_removed', n), NULL);
  RETURN n;
END;
$$;

-- ======================================================= grants

DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'public.admin_list_verifications(text)',
    'public.admin_review_verification(uuid, text, text)',
    'public.admin_list_quiz_reports(boolean)',
    'public.admin_resolve_quiz_report(bigint, boolean, text)',
    'public.admin_list_hymn_links()',
    'public.admin_set_hymn_links(jsonb)',
    'public.admin_get_app_settings()',
    'public.admin_set_app_setting(text, text)',
    'public.admin_reset_two_step(uuid)']
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', f);
  END LOOP;
END $$;

COMMIT;
