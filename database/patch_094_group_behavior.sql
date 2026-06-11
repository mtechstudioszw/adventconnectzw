-- =====================================================================
--  PATCH 094 — group behaviour: admin/remove/add/join semantics
-- =====================================================================

-- 1. Making someone an admin notifies ONLY that person (no group-wide
--    "X made Y an admin" spam). The client renders "made you an admin".
CREATE OR REPLACE FUNCTION public.set_group_admin(
  p_conversation BIGINT, p_user_id UUID, p_make_admin BOOLEAN)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_actor TEXT; v_group TEXT;
BEGIN
  IF NOT public.is_conversation_admin(p_conversation) THEN
    RAISE EXCEPTION 'Only group admins can change roles.';
  END IF;
  UPDATE public.conversation_members
     SET role = CASE WHEN p_make_admin THEN 'admin' ELSE 'member' END
   WHERE conversation_id = p_conversation AND user_id = p_user_id;
  IF p_make_admin THEN
    SELECT COALESCE(NULLIF(btrim(full_name), ''), 'An admin') INTO v_actor
      FROM public.profiles WHERE id = auth.uid();
    SELECT COALESCE(NULLIF(btrim(name), ''), 'the group') INTO v_group
      FROM public.conversations WHERE id = p_conversation;
    INSERT INTO public.notifications (
      user_id, title, body, type, reference_id, reference_type)
    VALUES (p_user_id, 'Group admin',
            v_actor || ' made you an admin of ' || v_group,
            'message', p_conversation::text, 'conversation');
  END IF;
END;
$$;

-- 2. Removing a member KEEPS their row (left_at) so the group stays in
--    their list read-only; they can't post or receive until re-added /
--    given a link. removed_members still blocks self-rejoin via link.
CREATE OR REPLACE FUNCTION public.remove_group_member(
  p_conversation BIGINT, p_user_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_target TEXT;
BEGIN
  IF NOT public.is_conversation_admin(p_conversation) THEN
    RAISE EXCEPTION 'Only group admins can remove members.';
  END IF;
  IF p_user_id = auth.uid() THEN
    RAISE EXCEPTION 'Use leave_group to remove yourself.';
  END IF;
  UPDATE public.conversation_members SET left_at = now()
   WHERE conversation_id = p_conversation AND user_id = p_user_id
     AND left_at IS NULL;
  INSERT INTO public.conversation_removed_members (conversation_id, user_id)
  VALUES (p_conversation, p_user_id)
  ON CONFLICT (conversation_id, user_id) DO UPDATE SET removed_at = now();
  SELECT COALESCE(NULLIF(btrim(full_name), ''), 'A member') INTO v_target
    FROM public.profiles WHERE id = p_user_id;
  PERFORM public._group_system_message(p_conversation, p_user_id,
    v_target || ' was removed');
END;
$$;

-- 3. Adding members reactivates a left/removed row (clears left_at +
--    removed flag) and notifies each added user.
CREATE OR REPLACE FUNCTION public.add_group_members(
  p_conversation BIGINT, p_user_ids UUID[])
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_actor TEXT; v_group TEXT; v_names TEXT;
BEGIN
  IF NOT public.is_conversation_admin(p_conversation) THEN
    RAISE EXCEPTION 'Only group admins can add members.';
  END IF;
  INSERT INTO public.conversation_members (conversation_id, user_id, role)
  SELECT p_conversation, uid, 'member' FROM unnest(p_user_ids) AS uid
  ON CONFLICT (conversation_id, user_id) DO UPDATE SET left_at = NULL;
  DELETE FROM public.conversation_removed_members
   WHERE conversation_id = p_conversation AND user_id = ANY(p_user_ids);
  SELECT COALESCE(NULLIF(btrim(full_name), ''), 'An admin') INTO v_actor
    FROM public.profiles WHERE id = auth.uid();
  SELECT COALESCE(NULLIF(btrim(name), ''), 'a group') INTO v_group
    FROM public.conversations WHERE id = p_conversation;
  SELECT string_agg(COALESCE(NULLIF(btrim(full_name), ''), 'a member'), ', ')
    INTO v_names FROM public.profiles WHERE id = ANY(p_user_ids);
  PERFORM public._group_system_message(p_conversation, auth.uid(),
    v_actor || ' added ' || COALESCE(v_names, 'a member'));
  INSERT INTO public.notifications (
    user_id, title, body, type, reference_id, reference_type)
  SELECT uid, 'Added to a group',
         v_actor || ' added you to ' || v_group,
         'message', p_conversation::text, 'conversation'
    FROM unnest(p_user_ids) AS uid WHERE uid <> auth.uid();
END;
$$;

-- 4. Join via link → "X joined via link" + reactivate a left row.
CREATE OR REPLACE FUNCTION public.join_group_via_invite(p_token TEXT)
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_conv BIGINT; v_name TEXT;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not signed in.'; END IF;
  SELECT conversation_id INTO v_conv
    FROM public.group_invites WHERE token = p_token;
  IF v_conv IS NULL THEN
    RAISE EXCEPTION 'This invite link is invalid or has expired.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.conversation_removed_members
              WHERE conversation_id = v_conv AND user_id = auth.uid()) THEN
    RAISE EXCEPTION 'You were removed from this group and can''t rejoin with a link. Ask an admin to add you.';
  END IF;
  INSERT INTO public.conversation_members (conversation_id, user_id, role)
  VALUES (v_conv, auth.uid(), 'member')
  ON CONFLICT (conversation_id, user_id) DO UPDATE SET left_at = NULL;
  SELECT COALESCE(NULLIF(btrim(full_name), ''), 'Someone') INTO v_name
    FROM public.profiles WHERE id = auth.uid();
  PERFORM public._group_system_message(v_conv, auth.uid(),
    v_name || ' joined via link');
  RETURN v_conv;
END;
$$;
