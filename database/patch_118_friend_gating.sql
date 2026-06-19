-- =====================================================================
--  PATCH 118 — Friend-gating (F3)
--
--  1) Non-friends can send at most 3 messages in a 1:1 chat until the
--     other person replies (or they become friends). WhatsApp-style
--     "message request" throttle so strangers can't spam.
--  2) You can only add your OWN accepted friends to a group.
-- =====================================================================

-- Reusable friendship check (accepted in either direction).
CREATE OR REPLACE FUNCTION public.are_friends(p_a uuid, p_b uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.friendships
    WHERE status = 'accepted'
      AND ((requester_id = p_a AND addressee_id = p_b)
        OR (requester_id = p_b AND addressee_id = p_a))
  );
$function$;

-- ---- 1) 3-message cap for non-friends ---------------------------------
CREATE OR REPLACE FUNCTION public.enforce_non_friend_message_cap()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_is_group BOOLEAN;
  v_a uuid;
  v_b uuid;
  v_other uuid;
  v_sent INT;
  v_replied BOOLEAN;
BEGIN
  SELECT is_group, participant_a_id, participant_b_id
    INTO v_is_group, v_a, v_b
    FROM public.conversations
    WHERE id = NEW.conversation_id;

  -- Only gate 1:1 chats with two known participants.
  IF COALESCE(v_is_group, FALSE) OR v_a IS NULL OR v_b IS NULL THEN
    RETURN NEW;
  END IF;

  -- Work out the other participant.
  IF NEW.sender_id = v_a THEN
    v_other := v_b;
  ELSIF NEW.sender_id = v_b THEN
    v_other := v_a;
  ELSE
    RETURN NEW; -- sender isn't a participant (shouldn't happen)
  END IF;

  -- Friends chat freely.
  IF public.are_friends(NEW.sender_id, v_other) THEN
    RETURN NEW;
  END IF;

  -- Once the other person has replied even once, the cap lifts.
  SELECT EXISTS (
    SELECT 1 FROM public.messages
    WHERE conversation_id = NEW.conversation_id
      AND sender_id = v_other
  ) INTO v_replied;
  IF v_replied THEN
    RETURN NEW;
  END IF;

  -- Not friends + no reply yet → cap the sender at 3 messages.
  SELECT count(*) INTO v_sent
    FROM public.messages
    WHERE conversation_id = NEW.conversation_id
      AND sender_id = NEW.sender_id;

  IF v_sent >= 3 THEN
    RAISE EXCEPTION
      'You can only send 3 messages until they reply.'
      USING ERRCODE = 'check_violation',
            HINT = 'Wait for a reply, or add them as a friend.';
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_non_friend_message_cap ON public.messages;
CREATE TRIGGER trg_non_friend_message_cap
  BEFORE INSERT ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.enforce_non_friend_message_cap();

-- ---- 2) Only add friends to a group -----------------------------------
CREATE OR REPLACE FUNCTION public.add_group_members(p_conversation bigint, p_user_ids uuid[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_actor TEXT; v_group TEXT; v_names TEXT;
BEGIN
  IF NOT public.is_conversation_admin(p_conversation) THEN
    RAISE EXCEPTION 'Only group admins can add members.';
  END IF;
  -- Friend-gate: an admin may only add their OWN accepted friends.
  IF EXISTS (
    SELECT 1 FROM unnest(p_user_ids) AS uid
    WHERE uid <> auth.uid() AND NOT public.are_friends(auth.uid(), uid)
  ) THEN
    RAISE EXCEPTION 'You can only add your friends to a group.'
      USING ERRCODE = 'check_violation';
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
$function$;
