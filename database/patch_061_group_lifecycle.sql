-- =====================================================================
--  PATCH 061 — Group lifecycle: system messages + removal block
--
--   * System messages (message_type='system') for created / added /
--     removed / left / admin changes — rendered centred like WhatsApp.
--   * conversation_removed_members: a removed user can't rejoin via the
--     invite link until an admin re-adds them.
--   * notify_new_message skips system rows (no push for "X left").
-- =====================================================================

-- ----- Removed-members ledger (locked to SECURITY DEFINER RPCs) -------
CREATE TABLE IF NOT EXISTS public.conversation_removed_members (
  conversation_id BIGINT NOT NULL
    REFERENCES public.conversations(id) ON DELETE CASCADE,
  user_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  removed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (conversation_id, user_id)
);
ALTER TABLE public.conversation_removed_members ENABLE ROW LEVEL SECURITY;
-- No policies: only SECURITY DEFINER functions below touch it.

-- ----- System-message helper -----------------------------------------
CREATE OR REPLACE FUNCTION public._group_system_message(
  p_conversation BIGINT, p_actor UUID, p_text TEXT
) RETURNS VOID AS $$
  INSERT INTO public.messages (conversation_id, sender_id, content, message_type)
  VALUES (p_conversation, p_actor, p_text, 'system');
  UPDATE public.conversations
     SET last_message = p_text, last_sender_id = p_actor, last_message_at = now()
   WHERE id = p_conversation;
$$ LANGUAGE sql SECURITY DEFINER SET search_path = public;

-- ----- notify_new_message: skip system rows --------------------------
CREATE OR REPLACE FUNCTION public.notify_new_message()
RETURNS TRIGGER AS $$
DECLARE
  a uuid; b uuid; other uuid;
  v_is_group boolean; v_group_name text; v_sender_name text;
BEGIN
  IF NEW.message_type = 'system' THEN RETURN NEW; END IF;

  SELECT participant_a_id, participant_b_id, is_group, name
    INTO a, b, v_is_group, v_group_name
    FROM public.conversations WHERE id = NEW.conversation_id;

  SELECT COALESCE(NULLIF(btrim(full_name), ''), 'Someone')
    INTO v_sender_name FROM public.profiles WHERE id = NEW.sender_id;

  IF COALESCE(v_is_group, FALSE) THEN
    INSERT INTO public.notifications (
      user_id, title, body, type, reference_id, reference_type)
    SELECT cm.user_id,
           COALESCE(NULLIF(btrim(v_group_name), ''), 'Group chat'),
           v_sender_name || ': ' || COALESCE(substr(NEW.content, 1, 120), ''),
           'message', NEW.conversation_id::text, 'conversation'
      FROM public.conversation_members cm
     WHERE cm.conversation_id = NEW.conversation_id
       AND cm.user_id <> NEW.sender_id;
    RETURN NEW;
  END IF;

  IF a IS NULL OR b IS NULL THEN RETURN NEW; END IF;
  other := CASE WHEN NEW.sender_id = a THEN b ELSE a END;
  IF other IS NULL OR other = NEW.sender_id THEN RETURN NEW; END IF;

  INSERT INTO public.notifications (
    user_id, title, body, type, reference_id, reference_type)
  VALUES (other, v_sender_name,
    COALESCE(substr(NEW.content, 1, 140), 'You have a new message.'),
    'message', NEW.conversation_id::text, 'conversation');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ----- create_group (keep active guard + creator system message) -----
CREATE OR REPLACE FUNCTION public.create_group(
  p_name TEXT, p_photo_url TEXT, p_description TEXT, p_member_ids UUID[]
) RETURNS BIGINT AS $$
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
  RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ----- add_group_members (clear removal + system message) ------------
CREATE OR REPLACE FUNCTION public.add_group_members(
  p_conversation BIGINT, p_user_ids UUID[]
) RETURNS VOID AS $$
DECLARE v_actor TEXT; v_names TEXT;
BEGIN
  IF NOT public.is_conversation_admin(p_conversation) THEN
    RAISE EXCEPTION 'Only group admins can add members.';
  END IF;
  INSERT INTO public.conversation_members (conversation_id, user_id, role)
  SELECT p_conversation, uid, 'member' FROM unnest(p_user_ids) AS uid
  ON CONFLICT DO NOTHING;
  DELETE FROM public.conversation_removed_members
   WHERE conversation_id = p_conversation AND user_id = ANY(p_user_ids);
  SELECT COALESCE(NULLIF(btrim(full_name), ''), 'Someone') INTO v_actor
    FROM public.profiles WHERE id = auth.uid();
  SELECT string_agg(COALESCE(NULLIF(btrim(full_name), ''), 'a member'), ', ')
    INTO v_names FROM public.profiles WHERE id = ANY(p_user_ids);
  PERFORM public._group_system_message(p_conversation, auth.uid(),
    v_actor || ' added ' || COALESCE(v_names, 'members'));
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ----- remove_group_member (record removal + system message) ---------
CREATE OR REPLACE FUNCTION public.remove_group_member(
  p_conversation BIGINT, p_user_id UUID
) RETURNS VOID AS $$
DECLARE v_actor TEXT; v_target TEXT;
BEGIN
  IF NOT public.is_conversation_admin(p_conversation) THEN
    RAISE EXCEPTION 'Only group admins can remove members.';
  END IF;
  IF p_user_id = auth.uid() THEN
    RAISE EXCEPTION 'Use leave_group to remove yourself.';
  END IF;
  DELETE FROM public.conversation_members
   WHERE conversation_id = p_conversation AND user_id = p_user_id;
  INSERT INTO public.conversation_removed_members (conversation_id, user_id)
  VALUES (p_conversation, p_user_id)
  ON CONFLICT (conversation_id, user_id) DO UPDATE SET removed_at = now();
  SELECT COALESCE(NULLIF(btrim(full_name), ''), 'An admin') INTO v_actor
    FROM public.profiles WHERE id = auth.uid();
  SELECT COALESCE(NULLIF(btrim(full_name), ''), 'a member') INTO v_target
    FROM public.profiles WHERE id = p_user_id;
  PERFORM public._group_system_message(p_conversation, auth.uid(),
    v_actor || ' removed ' || v_target);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ----- set_group_admin (+ system message) ----------------------------
CREATE OR REPLACE FUNCTION public.set_group_admin(
  p_conversation BIGINT, p_user_id UUID, p_make_admin BOOLEAN
) RETURNS VOID AS $$
DECLARE v_actor TEXT; v_target TEXT;
BEGIN
  IF NOT public.is_conversation_admin(p_conversation) THEN
    RAISE EXCEPTION 'Only group admins can change roles.';
  END IF;
  UPDATE public.conversation_members
     SET role = CASE WHEN p_make_admin THEN 'admin' ELSE 'member' END
   WHERE conversation_id = p_conversation AND user_id = p_user_id;
  SELECT COALESCE(NULLIF(btrim(full_name), ''), 'An admin') INTO v_actor
    FROM public.profiles WHERE id = auth.uid();
  SELECT COALESCE(NULLIF(btrim(full_name), ''), 'a member') INTO v_target
    FROM public.profiles WHERE id = p_user_id;
  PERFORM public._group_system_message(p_conversation, auth.uid(),
    v_actor || CASE WHEN p_make_admin
      THEN ' made ' || v_target || ' an admin'
      ELSE ' removed ' || v_target || ' as admin' END);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ----- leave_group (+ system message) --------------------------------
CREATE OR REPLACE FUNCTION public.leave_group(p_conversation BIGINT)
RETURNS VOID AS $$
DECLARE v_actor TEXT;
BEGIN
  SELECT COALESCE(NULLIF(btrim(full_name), ''), 'A member') INTO v_actor
    FROM public.profiles WHERE id = auth.uid();
  PERFORM public._group_system_message(p_conversation, auth.uid(),
    v_actor || ' left');
  DELETE FROM public.conversation_members
   WHERE conversation_id = p_conversation AND user_id = auth.uid();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ----- join_group_via_invite (block removed users) -------------------
CREATE OR REPLACE FUNCTION public.join_group_via_invite(p_token TEXT)
RETURNS BIGINT AS $$
DECLARE v_conv BIGINT;
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
  ON CONFLICT DO NOTHING;
  RETURN v_conv;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
