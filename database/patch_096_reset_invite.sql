-- =====================================================================
--  PATCH 096 — admins can reset (revoke) a group's invite link
--
--  Deletes the current invite token (so existing links stop working) and
--  mints a fresh one via the existing generator. Admin-only.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.reset_group_invite(p_conversation BIGINT)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_conversation_admin(p_conversation) THEN
    RAISE EXCEPTION 'Only group admins can reset the invite link.';
  END IF;
  DELETE FROM public.group_invites WHERE conversation_id = p_conversation;
  RETURN public.get_or_create_group_invite(p_conversation);
END;
$$;
GRANT EXECUTE ON FUNCTION public.reset_group_invite(BIGINT) TO authenticated;
