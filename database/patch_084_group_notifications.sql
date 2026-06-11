-- =====================================================================
--  PATCH 084 — church members-chat notifications + skip left members
--
--  * Church MEMBERS group now notifies every church member (except the
--    sender) per message — previously it sent nothing.
--  * User-group notifications skip members who LEFT (left_at, patch_079).
--  Church channel + 1:1 behaviour unchanged.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.notify_new_message()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  a uuid; b uuid; other uuid;
  v_is_group boolean; v_group_name text; v_sender_name text;
  v_church_id bigint; v_church_kind text;
BEGIN
  IF NEW.message_type = 'system' THEN RETURN NEW; END IF;

  SELECT participant_a_id, participant_b_id, is_group, name, church_id, church_kind
    INTO a, b, v_is_group, v_group_name, v_church_id, v_church_kind
    FROM public.conversations WHERE id = NEW.conversation_id;

  SELECT COALESCE(NULLIF(btrim(full_name), ''), 'Someone')
    INTO v_sender_name FROM public.profiles WHERE id = NEW.sender_id;

  -- Church conversations (implicit membership via profiles.church_id).
  IF v_church_id IS NOT NULL THEN
    INSERT INTO public.notifications (
      user_id, title, body, type, reference_id, reference_type)
    SELECT p.id,
           COALESCE(NULLIF(btrim(v_group_name), ''),
             CASE WHEN v_church_kind = 'channel'
                  THEN 'Church announcement' ELSE 'Church group' END),
           v_sender_name || ': ' || COALESCE(substr(NEW.content, 1, 120), ''),
           CASE WHEN v_church_kind = 'channel' THEN 'announcement' ELSE 'message' END,
           NEW.conversation_id::text, 'conversation'
      FROM public.profiles p
     WHERE p.church_id = v_church_id
       AND p.id <> NEW.sender_id
       AND COALESCE(p.is_banned, FALSE) = FALSE;
    RETURN NEW;
  END IF;

  IF COALESCE(v_is_group, FALSE) THEN
    INSERT INTO public.notifications (
      user_id, title, body, type, reference_id, reference_type)
    SELECT cm.user_id,
           COALESCE(NULLIF(btrim(v_group_name), ''), 'Group chat'),
           v_sender_name || ': ' || COALESCE(substr(NEW.content, 1, 120), ''),
           'message', NEW.conversation_id::text, 'conversation'
      FROM public.conversation_members cm
     WHERE cm.conversation_id = NEW.conversation_id
       AND cm.user_id <> NEW.sender_id
       AND cm.left_at IS NULL;
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
$$;
