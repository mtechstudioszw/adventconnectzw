-- patch_315 — Web console, part 2: quiz questions, hymns, library items,
-- calls and fundraiser actions (owner, 4 Nov 2026: "if there are things
-- which are not built yet, do them now").
--
-- The app's admin screens edit quiz_questions / hymns / library_items
-- straight through table policies (super admin). The web console goes
-- through functions instead, like every other admin_* call:
--   * the FIRST statement checks the caller's staff role;
--   * values are validated here, not trusted from the browser;
--   * every change lands in admin_audit_log.
-- Ending a call and confirming/rejecting a fundraiser contribution keep the
-- existing functions (they already require a super admin) and only add the
-- audit entry.
-- Run AFTER patch_314. Safe to run twice.

BEGIN;

-- ================================================== quiz questions

CREATE OR REPLACE FUNCTION public.admin_list_quiz_questions(
  p_search text DEFAULT NULL, p_category text DEFAULT NULL, p_limit integer DEFAULT 100)
 RETURNS TABLE (id bigint, question text, options jsonb, correct_index integer,
   explanation text, reference text, category text, difficulty text,
   is_published boolean, created_at timestamptz)
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
BEGIN
  PERFORM public.assert_staff('viewer');
  RETURN QUERY
  SELECT q.id, q.question, q.options, q.correct_index, q.explanation,
         q.reference, q.category, q.difficulty, q.is_published, q.created_at
    FROM public.quiz_questions q
   WHERE (coalesce(p_search, '') = '' OR q.question ILIKE '%' || p_search || '%'
          OR q.id::text = p_search)
     AND (coalesce(p_category, '') = '' OR q.category = p_category)
   ORDER BY q.created_at DESC
   LIMIT greatest(1, least(coalesce(p_limit, 100), 500));
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_save_quiz_question(
  p_id bigint, p_question text, p_options jsonb, p_correct_index integer,
  p_explanation text, p_reference text, p_category text, p_difficulty text,
  p_is_published boolean)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
  v_id bigint;
  v_n integer;
BEGIN
  PERFORM public.assert_staff('manager');
  IF length(btrim(coalesce(p_question, ''))) < 8 THEN
    RAISE EXCEPTION 'Write the question in full.' USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(p_options) <> 'array' THEN
    RAISE EXCEPTION 'Options must be a list.' USING ERRCODE = '22023';
  END IF;
  v_n := jsonb_array_length(p_options);
  IF v_n < 2 OR v_n > 6 THEN
    RAISE EXCEPTION 'Give between 2 and 6 options.' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_options) o
              WHERE jsonb_typeof(o) <> 'string' OR btrim(o #>> '{}') = '') THEN
    RAISE EXCEPTION 'Every option needs text.' USING ERRCODE = '22023';
  END IF;
  IF p_correct_index IS NULL OR p_correct_index < 0 OR p_correct_index >= v_n THEN
    RAISE EXCEPTION 'Mark which option is correct.' USING ERRCODE = '22023';
  END IF;
  IF p_difficulty NOT IN ('easy', 'medium', 'hard') THEN
    RAISE EXCEPTION 'Difficulty must be easy, medium or hard.' USING ERRCODE = '22023';
  END IF;
  IF btrim(coalesce(p_category, '')) = '' THEN
    RAISE EXCEPTION 'Choose a category.' USING ERRCODE = '22023';
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO public.quiz_questions (question, options, correct_index,
      explanation, reference, category, difficulty, is_published)
    VALUES (btrim(p_question), p_options, p_correct_index,
      nullif(btrim(p_explanation), ''), nullif(btrim(p_reference), ''),
      btrim(p_category), p_difficulty, coalesce(p_is_published, true))
    RETURNING quiz_questions.id INTO v_id;
  ELSE
    UPDATE public.quiz_questions q
       SET question = btrim(p_question), options = p_options,
           correct_index = p_correct_index,
           explanation = nullif(btrim(p_explanation), ''),
           reference = nullif(btrim(p_reference), ''),
           category = btrim(p_category), difficulty = p_difficulty,
           is_published = coalesce(p_is_published, q.is_published)
     WHERE q.id = p_id
    RETURNING q.id INTO v_id;
    IF v_id IS NULL THEN
      RAISE EXCEPTION 'No such question.' USING ERRCODE = 'P0002';
    END IF;
  END IF;
  PERFORM public.log_admin_action(
    CASE WHEN p_id IS NULL THEN 'quiz_question_added' ELSE 'quiz_question_edited' END,
    'quiz_question', v_id::text, NULL,
    jsonb_build_object('published', p_is_published), NULL);
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_delete_quiz_question(p_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE v_before jsonb;
BEGIN
  PERFORM public.assert_staff('manager');
  SELECT to_jsonb(q) INTO v_before FROM public.quiz_questions q WHERE q.id = p_id;
  DELETE FROM public.quiz_questions q WHERE q.id = p_id;
  PERFORM public.log_admin_action('quiz_question_deleted', 'quiz_question',
    p_id::text, v_before, NULL, NULL);
END;
$$;

-- =========================================================== hymns

CREATE OR REPLACE FUNCTION public.admin_list_hymns(
  p_collection text DEFAULT 'sda_hymnal', p_search text DEFAULT NULL)
 RETURNS TABLE (id bigint, collection text, number integer, title text,
   lyrics text, category text, language text, is_published boolean)
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
BEGIN
  PERFORM public.assert_staff('viewer');
  RETURN QUERY
  SELECT h.id, h.collection, h.number, h.title, h.lyrics, h.category,
         h.language, h.is_published
    FROM public.hymns h
   WHERE h.collection = p_collection
     AND (coalesce(p_search, '') = '' OR h.title ILIKE '%' || p_search || '%'
          OR h.number::text = p_search)
   ORDER BY h.number
   LIMIT 800;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_save_hymn(
  p_id bigint, p_collection text, p_number integer, p_title text,
  p_lyrics text, p_category text, p_is_published boolean)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
  v_id bigint;
  v_lang text;
BEGIN
  PERFORM public.assert_staff('manager');
  v_lang := CASE p_collection
    WHEN 'sda_hymnal' THEN 'English'
    WHEN 'kristu_munzwiyo' THEN 'Shona'
  END;
  IF v_lang IS NULL THEN
    RAISE EXCEPTION 'Unknown hymnal.' USING ERRCODE = '22023';
  END IF;
  IF p_number IS NULL OR p_number < 1 OR p_number > 1000 THEN
    RAISE EXCEPTION 'Give the hymn number.' USING ERRCODE = '22023';
  END IF;
  IF btrim(coalesce(p_title, '')) = '' OR btrim(coalesce(p_lyrics, '')) = '' THEN
    RAISE EXCEPTION 'A hymn needs a title and words.' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (SELECT 1 FROM public.hymns h
              WHERE h.collection = p_collection AND h.number = p_number
                AND (p_id IS NULL OR h.id <> p_id)) THEN
    RAISE EXCEPTION 'That hymnal already has a hymn %.', p_number USING ERRCODE = '23505';
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO public.hymns (collection, number, title, lyrics, category,
      language, is_published)
    VALUES (p_collection, p_number, btrim(p_title), p_lyrics,
      nullif(btrim(p_category), ''), v_lang, coalesce(p_is_published, true))
    RETURNING hymns.id INTO v_id;
  ELSE
    UPDATE public.hymns h
       SET collection = p_collection, number = p_number, title = btrim(p_title),
           lyrics = p_lyrics, category = nullif(btrim(p_category), ''),
           language = v_lang,
           is_published = coalesce(p_is_published, h.is_published)
     WHERE h.id = p_id
    RETURNING h.id INTO v_id;
    IF v_id IS NULL THEN
      RAISE EXCEPTION 'No such hymn.' USING ERRCODE = 'P0002';
    END IF;
  END IF;
  PERFORM public.log_admin_action(
    CASE WHEN p_id IS NULL THEN 'hymn_added' ELSE 'hymn_edited' END,
    'hymn', v_id::text, NULL,
    jsonb_build_object('collection', p_collection, 'number', p_number), NULL);
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_delete_hymn(p_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE v_before jsonb;
BEGIN
  PERFORM public.assert_staff('owner');
  SELECT jsonb_build_object('collection', h.collection, 'number', h.number,
           'title', h.title)
    INTO v_before FROM public.hymns h WHERE h.id = p_id;
  DELETE FROM public.hymns h WHERE h.id = p_id;
  PERFORM public.log_admin_action('hymn_deleted', 'hymn', p_id::text,
    v_before, NULL, NULL);
END;
$$;

-- =================================================== library items
-- EGW books and music. Files are uploaded to the `library` bucket from the
-- console (super admin storage policy); this records the item.

CREATE OR REPLACE FUNCTION public.admin_list_library_items(p_kind text DEFAULT NULL)
 RETURNS SETOF public.library_items
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
BEGIN
  PERFORM public.assert_staff('viewer');
  RETURN QUERY
  SELECT * FROM public.library_items li
   WHERE coalesce(p_kind, '') = '' OR li.kind = p_kind
   ORDER BY li.kind, li.sort_order NULLS LAST, li.title;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_save_library_item(
  p_id bigint, p_kind text, p_title text, p_author text, p_description text,
  p_language text, p_cover_url text, p_file_url text, p_epub_url text,
  p_sort_order integer, p_is_published boolean)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
  v_id bigint;
  u text;
BEGIN
  PERFORM public.assert_staff('manager');
  IF p_kind NOT IN ('egw_book', 'music') THEN
    RAISE EXCEPTION 'Kind must be egw_book or music.' USING ERRCODE = '22023';
  END IF;
  IF btrim(coalesce(p_title, '')) = '' THEN
    RAISE EXCEPTION 'Give it a title.' USING ERRCODE = '22023';
  END IF;
  FOREACH u IN ARRAY ARRAY[p_cover_url, p_file_url, p_epub_url] LOOP
    IF coalesce(u, '') <> '' AND u !~ '^https://' THEN
      RAISE EXCEPTION 'Links must start with https://' USING ERRCODE = '22023';
    END IF;
  END LOOP;
  IF coalesce(p_file_url, '') = '' AND coalesce(p_epub_url, '') = '' THEN
    RAISE EXCEPTION 'Upload the file first.' USING ERRCODE = '22023';
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO public.library_items (kind, title, author, description,
      language, cover_url, file_url, epub_url, sort_order, is_published)
    VALUES (p_kind, btrim(p_title), nullif(btrim(p_author), ''),
      nullif(btrim(p_description), ''), nullif(btrim(p_language), ''),
      nullif(p_cover_url, ''), nullif(p_file_url, ''), nullif(p_epub_url, ''),
      p_sort_order, coalesce(p_is_published, true))
    RETURNING library_items.id INTO v_id;
  ELSE
    UPDATE public.library_items li
       SET kind = p_kind, title = btrim(p_title),
           author = nullif(btrim(p_author), ''),
           description = nullif(btrim(p_description), ''),
           language = nullif(btrim(p_language), ''),
           cover_url = nullif(p_cover_url, ''),
           file_url = nullif(p_file_url, ''),
           epub_url = nullif(p_epub_url, ''),
           sort_order = p_sort_order,
           is_published = coalesce(p_is_published, li.is_published)
     WHERE li.id = p_id
    RETURNING li.id INTO v_id;
    IF v_id IS NULL THEN
      RAISE EXCEPTION 'No such item.' USING ERRCODE = 'P0002';
    END IF;
  END IF;
  PERFORM public.log_admin_action(
    CASE WHEN p_id IS NULL THEN 'library_item_added' ELSE 'library_item_edited' END,
    'library_item', v_id::text, NULL,
    jsonb_build_object('kind', p_kind, 'title', p_title), NULL);
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_delete_library_item(p_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE v_before jsonb;
BEGIN
  PERFORM public.assert_staff('owner');
  SELECT jsonb_build_object('kind', li.kind, 'title', li.title,
           'file_url', li.file_url)
    INTO v_before FROM public.library_items li WHERE li.id = p_id;
  DELETE FROM public.library_items li WHERE li.id = p_id;
  PERFORM public.log_admin_action('library_item_deleted', 'library_item',
    p_id::text, v_before, NULL, NULL);
END;
$$;

-- ============================================ calls + fundraiser, audited

CREATE OR REPLACE FUNCTION public.admin_end_call(p_call uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE v jsonb;
BEGIN
  PERFORM public.assert_staff('owner');
  v := public.call_admin_end(p_call);   -- itself requires a super admin
  PERFORM public.log_admin_action('call_ended_by_admin', 'call', p_call::text,
    NULL, v, NULL);
  RETURN v;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_confirm_contribution(
  p_id bigint, p_amount_cents integer)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE ok boolean;
BEGIN
  PERFORM public.assert_staff('owner');
  ok := public.fundraiser_confirm_contribution(p_id, p_amount_cents);
  PERFORM public.log_admin_action('fundraiser_contribution_confirmed',
    'fundraiser_contribution', p_id::text, NULL,
    jsonb_build_object('amount_cents', p_amount_cents, 'ok', ok), NULL);
  RETURN ok;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_reject_contribution(p_id bigint, p_note text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE ok boolean;
BEGIN
  PERFORM public.assert_staff('owner');
  ok := public.fundraiser_reject_contribution(p_id, p_note);
  PERFORM public.log_admin_action('fundraiser_contribution_rejected',
    'fundraiser_contribution', p_id::text, NULL,
    jsonb_build_object('ok', ok), nullif(btrim(p_note), ''));
  RETURN ok;
END;
$$;

-- ======================================================= grants

DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'public.admin_list_quiz_questions(text, text, integer)',
    'public.admin_save_quiz_question(bigint, text, jsonb, integer, text, text, text, text, boolean)',
    'public.admin_delete_quiz_question(bigint)',
    'public.admin_list_hymns(text, text)',
    'public.admin_save_hymn(bigint, text, integer, text, text, text, boolean)',
    'public.admin_delete_hymn(bigint)',
    'public.admin_list_library_items(text)',
    'public.admin_save_library_item(bigint, text, text, text, text, text, text, text, text, integer, boolean)',
    'public.admin_delete_library_item(bigint)',
    'public.admin_end_call(uuid)',
    'public.admin_confirm_contribution(bigint, integer)',
    'public.admin_reject_contribution(bigint, text)']
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', f);
  END LOOP;
END $$;

COMMIT;
