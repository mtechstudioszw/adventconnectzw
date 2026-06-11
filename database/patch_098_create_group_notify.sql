-- =====================================================================
--  PATCH 098 — notify members added when a group is CREATED
--
--  add_group_members already notifies (patch_094), but create_group added
--  the initial members silently — so "X added you to <group>" never fired
--  for people put in the group at creation. Add the same notification.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.create_group(
  p_name TEXT, p_photo_url TEXT, p_description TEXT, p_member_ids UUID[])
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_id  BIGINT;
  v_name TEXT := NULLIF(btrim(COALESCE(p_name, '')), '');
  v_actor TEXT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not signed in.'; END IF;
  IF NOT public.user_is_active() THEN
    RAISE EXCEPTION 'Your account cannot create groups.';
  END IF;
  IF v_name IS NULL THEN RAISE EXCEPTION 'Group name is required.'; END IF;

  INSERT INTO public.conversations (
    is_group, name, photo_url, description, created_by, last_message_at)
  VALUES (TRUE, v_name,
    NULLIF(btrim(COALESCE(p_photo_url, '')), ''),
    NULLIF(btrim(COALESCE(p_description, '')), ''), v_uid, now())
  RETURNING id INTO v_id;

  INSERT INTO public.conversation_members (conversation_id, user_id, role)
  VALUES (v_id, v_uid, 'admin');

  IF p_member_ids IS NOT NULL THEN
    INSERT INTO public.conversation_members (conversation_id, user_id, role)
    SELECT v_id, uid, 'member' FROM unnest(p_member_ids) AS uid
     WHERE uid <> v_uid
    ON CONFLICT DO NOTHING;
  END IF;

  SELECT COALESCE(NULLIF(btrim(full_name), ''), 'Someone') INTO v_actor
    FROM public.profiles WHERE id = v_uid;
  PERFORM public._group_system_message(v_id, v_uid,
    v_actor || ' created the group "' || v_name || '"');

  -- Notify each added member (the missing "X added you to <group>").
  IF p_member_ids IS NOT NULL THEN
    INSERT INTO public.notifications (
      user_id, title, body, type, reference_id, reference_type)
    SELECT uid, 'Added to a group',
           v_actor || ' added you to ' || v_name,
           'message', v_id::text, 'conversation'
      FROM unnest(p_member_ids) AS uid WHERE uid <> v_uid;
  END IF;

  RETURN v_id;
END;
$function$;
