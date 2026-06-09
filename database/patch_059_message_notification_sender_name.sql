-- =====================================================================
--  PATCH 059 — Message notifications: sender name + group fan-out
--
--  notify_new_message() hardcoded the title 'New message' (so the inbox
--  and push never showed WHO messaged) and returned early for groups
--  (is_group rows have NULL participant_a/b), so group messages pushed
--  nobody.
--
--  Now: 1:1 → title = sender's name. Group → one notification per other
--  member, title = group name, body = "Sender: text". Each row still
--  triggers the notify-fcm webhook, so group push works too (and the
--  patch_058 per-conversation mute check in that function is honoured).
-- =====================================================================

CREATE OR REPLACE FUNCTION public.notify_new_message()
RETURNS TRIGGER AS $$
DECLARE
  a             uuid;
  b             uuid;
  other         uuid;
  v_is_group    boolean;
  v_group_name  text;
  v_sender_name text;
BEGIN
  SELECT participant_a_id, participant_b_id, is_group, name
    INTO a, b, v_is_group, v_group_name
    FROM public.conversations
   WHERE id = NEW.conversation_id;

  SELECT COALESCE(NULLIF(btrim(full_name), ''), 'Someone')
    INTO v_sender_name
    FROM public.profiles
   WHERE id = NEW.sender_id;

  IF COALESCE(v_is_group, FALSE) THEN
    INSERT INTO public.notifications (
      user_id, title, body, type, reference_id, reference_type
    )
    SELECT cm.user_id,
           COALESCE(NULLIF(btrim(v_group_name), ''), 'Group chat'),
           v_sender_name || ': '
             || COALESCE(substr(NEW.content, 1, 120), ''),
           'message',
           NEW.conversation_id::text,
           'conversation'
      FROM public.conversation_members cm
     WHERE cm.conversation_id = NEW.conversation_id
       AND cm.user_id <> NEW.sender_id;
    RETURN NEW;
  END IF;

  IF a IS NULL OR b IS NULL THEN RETURN NEW; END IF;
  other := CASE WHEN NEW.sender_id = a THEN b ELSE a END;
  IF other IS NULL OR other = NEW.sender_id THEN RETURN NEW; END IF;

  INSERT INTO public.notifications (
    user_id, title, body, type, reference_id, reference_type
  ) VALUES (
    other,
    v_sender_name,
    COALESCE(substr(NEW.content, 1, 140), 'You have a new message.'),
    'message',
    NEW.conversation_id::text,
    'conversation'
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
