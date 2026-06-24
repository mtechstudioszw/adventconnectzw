-- =====================================================================
--  PATCH 123 — group add/remove system messages name the ACTOR
--
--  Bug: removing a member stored the system message as "<target> was
--  removed" authored by the TARGET. So the remover (and everyone else)
--  saw "Bob was removed" and never "You removed Bob" / "Michael removed
--  Bob". WhatsApp shows three views of the same event:
--     * remover  -> "You removed Bob"
--     * removed  -> "Michael removed you"
--     * others   -> "Michael removed Bob"
--
--  Fix: author the system message as the ACTOR (auth.uid()) and carry the
--  actor + target identity in messages.meta (jsonb) so the client can pick
--  the right phrasing per viewer. content stays a sensible third-person
--  string ("Michael removed Bob") so the inbox preview + any non-meta-aware
--  client still reads correctly. Same treatment for "added".
--
--  Legacy rows (no meta) keep working — the client falls back to its old
--  per-suffix localisation for them.
-- =====================================================================

-- Meta-carrying variant of the system-message helper. Mirrors
-- _group_system_message (patch_061) but also writes messages.meta.
CREATE OR REPLACE FUNCTION public._group_system_message_meta(
  p_conversation BIGINT, p_actor UUID, p_text TEXT, p_meta JSONB
) RETURNS VOID AS $$
  INSERT INTO public.messages
    (conversation_id, sender_id, content, message_type, meta)
  VALUES (p_conversation, p_actor, p_text, 'system', p_meta);
  UPDATE public.conversations
     SET last_message = p_text, last_sender_id = p_actor, last_message_at = now()
   WHERE id = p_conversation;
$$ LANGUAGE sql SECURITY DEFINER SET search_path = public;
GRANT EXECUTE ON FUNCTION
  public._group_system_message_meta(BIGINT, UUID, TEXT, JSONB) TO authenticated;

-- Remove a member — author = actor, content names actor + target, meta
-- carries both identities so each viewer gets the right phrasing.
CREATE OR REPLACE FUNCTION public.remove_group_member(
  p_conversation BIGINT, p_user_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_target TEXT; v_actor TEXT;
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
  SELECT COALESCE(NULLIF(btrim(full_name), ''), 'a member') INTO v_target
    FROM public.profiles WHERE id = p_user_id;
  SELECT COALESCE(NULLIF(btrim(full_name), ''), 'An admin') INTO v_actor
    FROM public.profiles WHERE id = auth.uid();
  PERFORM public._group_system_message_meta(
    p_conversation, auth.uid(),
    v_actor || ' removed ' || v_target,
    jsonb_build_object(
      'event', 'removed',
      'actor_id', auth.uid(),
      'target_id', p_user_id,
      'actor_name', v_actor,
      'target_name', v_target));
END;
$$;

-- Add members — already authored by the actor; now also carries meta so the
-- actor sees "You added X" while others see "Michael added X".
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
  PERFORM public._group_system_message_meta(
    p_conversation, auth.uid(),
    v_actor || ' added ' || COALESCE(v_names, 'a member'),
    jsonb_build_object(
      'event', 'added',
      'actor_id', auth.uid(),
      'actor_name', v_actor,
      'target_names', COALESCE(v_names, 'a member')));
  INSERT INTO public.notifications (
    user_id, title, body, type, reference_id, reference_type)
  SELECT uid, 'Added to a group',
         v_actor || ' added you to ' || v_group,
         'message', p_conversation::text, 'conversation'
    FROM unnest(p_user_ids) AS uid WHERE uid <> auth.uid();
END;
$$;
