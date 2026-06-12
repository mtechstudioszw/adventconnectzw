-- =====================================================================
--  PATCH 104 — notify the sender when someone reacts to their message
--
--  Pure Supabase (no app code): a trigger on message_reactions INSERT
--  writes a notification for the message's sender (skipping self-
--  reactions). The existing notify-fcm webhook pushes it, the in-app
--  inbox shows it, and reference_type='conversation' routes the tap to
--  the chat and respects per-conversation mute.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.notify_message_reaction()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_sender UUID;
  v_conv   BIGINT;
  v_reactor TEXT;
BEGIN
  SELECT m.sender_id, m.conversation_id INTO v_sender, v_conv
    FROM public.messages m WHERE m.id = NEW.message_id;

  -- No sender found, or you reacted to your own message → no notification.
  IF v_sender IS NULL OR v_sender = NEW.user_id THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(NULLIF(btrim(full_name), ''), 'Someone') INTO v_reactor
    FROM public.profiles WHERE id = NEW.user_id;

  INSERT INTO public.notifications (
    user_id, title, body, type, reference_id, reference_type)
  VALUES (
    v_sender,
    'New reaction',
    v_reactor || ' reacted ' || COALESCE(NEW.emoji, '') ||
      ' to your message',
    'message',
    v_conv::text,
    'conversation');

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_message_reaction ON public.message_reactions;
CREATE TRIGGER trg_notify_message_reaction
  AFTER INSERT ON public.message_reactions
  FOR EACH ROW EXECUTE FUNCTION public.notify_message_reaction();
