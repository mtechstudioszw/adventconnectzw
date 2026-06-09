-- =====================================================================
--  PATCH 053 — Group chat management RPCs
--
--  SECURITY DEFINER functions for the group lifecycle. Direct
--  INSERT/UPDATE/DELETE on conversation_members is denied by RLS (except
--  self-leave), so all admin actions route through these, each gated by
--  the patch_052 membership helpers. Depends on patch_052.
-- =====================================================================

-- ----- Create a group -------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_group(
  p_name        TEXT,
  p_photo_url   TEXT,
  p_description TEXT,
  p_member_ids  UUID[]
) RETURNS BIGINT AS $$
DECLARE
  v_uid  UUID := auth.uid();
  v_id   BIGINT;
  v_name TEXT := NULLIF(btrim(COALESCE(p_name, '')), '');
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not signed in.'; END IF;
  IF v_name IS NULL THEN RAISE EXCEPTION 'Group name is required.'; END IF;

  INSERT INTO public.conversations (
    is_group, name, photo_url, description, created_by, last_message_at
  ) VALUES (
    TRUE, v_name,
    NULLIF(btrim(COALESCE(p_photo_url, '')), ''),
    NULLIF(btrim(COALESCE(p_description, '')), ''),
    v_uid, now()
  ) RETURNING id INTO v_id;

  INSERT INTO public.conversation_members (conversation_id, user_id, role)
  VALUES (v_id, v_uid, 'admin');

  IF p_member_ids IS NOT NULL THEN
    INSERT INTO public.conversation_members (conversation_id, user_id, role)
    SELECT v_id, uid, 'member'
      FROM unnest(p_member_ids) AS uid
     WHERE uid <> v_uid
    ON CONFLICT DO NOTHING;
  END IF;

  RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ----- Add members (admin only) --------------------------------------
CREATE OR REPLACE FUNCTION public.add_group_members(
  p_conversation BIGINT,
  p_user_ids     UUID[]
) RETURNS VOID AS $$
BEGIN
  IF NOT public.is_conversation_admin(p_conversation) THEN
    RAISE EXCEPTION 'Only group admins can add members.';
  END IF;
  INSERT INTO public.conversation_members (conversation_id, user_id, role)
  SELECT p_conversation, uid, 'member'
    FROM unnest(p_user_ids) AS uid
  ON CONFLICT DO NOTHING;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ----- Remove a member (admin only; not yourself — use leave) --------
CREATE OR REPLACE FUNCTION public.remove_group_member(
  p_conversation BIGINT,
  p_user_id      UUID
) RETURNS VOID AS $$
BEGIN
  IF NOT public.is_conversation_admin(p_conversation) THEN
    RAISE EXCEPTION 'Only group admins can remove members.';
  END IF;
  IF p_user_id = auth.uid() THEN
    RAISE EXCEPTION 'Use leave_group to remove yourself.';
  END IF;
  DELETE FROM public.conversation_members
   WHERE conversation_id = p_conversation AND user_id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ----- Promote / demote an admin (admin only) ------------------------
CREATE OR REPLACE FUNCTION public.set_group_admin(
  p_conversation BIGINT,
  p_user_id      UUID,
  p_make_admin   BOOLEAN
) RETURNS VOID AS $$
BEGIN
  IF NOT public.is_conversation_admin(p_conversation) THEN
    RAISE EXCEPTION 'Only group admins can change roles.';
  END IF;
  UPDATE public.conversation_members
     SET role = CASE WHEN p_make_admin THEN 'admin' ELSE 'member' END
   WHERE conversation_id = p_conversation AND user_id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ----- Edit group (admin only) ---------------------------------------
CREATE OR REPLACE FUNCTION public.update_group(
  p_conversation BIGINT,
  p_name         TEXT,
  p_photo_url    TEXT,
  p_description  TEXT
) RETURNS VOID AS $$
BEGIN
  IF NOT public.is_conversation_admin(p_conversation) THEN
    RAISE EXCEPTION 'Only group admins can edit the group.';
  END IF;
  UPDATE public.conversations
     SET name        = COALESCE(NULLIF(btrim(COALESCE(p_name, '')), ''), name),
         photo_url   = COALESCE(p_photo_url, photo_url),
         description = COALESCE(p_description, description)
   WHERE id = p_conversation AND is_group = TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ----- Leave a group --------------------------------------------------
CREATE OR REPLACE FUNCTION public.leave_group(p_conversation BIGINT)
RETURNS VOID AS $$
BEGIN
  DELETE FROM public.conversation_members
   WHERE conversation_id = p_conversation AND user_id = auth.uid();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ----- Delete a group (admin only) -----------------------------------
CREATE OR REPLACE FUNCTION public.delete_group(p_conversation BIGINT)
RETURNS VOID AS $$
BEGIN
  IF NOT public.is_conversation_admin(p_conversation) THEN
    RAISE EXCEPTION 'Only group admins can delete the group.';
  END IF;
  DELETE FROM public.messages WHERE conversation_id = p_conversation;
  DELETE FROM public.conversations
   WHERE id = p_conversation AND is_group = TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

REVOKE ALL ON FUNCTION public.create_group(TEXT, TEXT, TEXT, UUID[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.add_group_members(BIGINT, UUID[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.remove_group_member(BIGINT, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_group_admin(BIGINT, UUID, BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_group(BIGINT, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.leave_group(BIGINT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delete_group(BIGINT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.create_group(TEXT, TEXT, TEXT, UUID[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.add_group_members(BIGINT, UUID[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_group_member(BIGINT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_group_admin(BIGINT, UUID, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_group(BIGINT, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.leave_group(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_group(BIGINT) TO authenticated;
