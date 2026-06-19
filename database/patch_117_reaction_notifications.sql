-- =====================================================================
--  PATCH 117 — notify a message author when someone reacts to them.
--
--  Bug report: "if user B reacts to your message it doesn't show outside
--  the chat". Reactions were stored in public.message_reactions but the
--  message's author was never notified, so no FCM push ever fired.
--
--  Fix: an AFTER INSERT trigger on public.message_reactions inserts a row
--  into public.notifications addressed to the message author. The existing
--  "notify-fcm-on-notification-insert" trigger turns that row into a push
--  automatically, so we only need the INSERT here.
--
--  Notes:
--   * SECURITY DEFINER so the trigger can read messages/profiles and write
--     notifications regardless of the reactor's RLS.
--   * The reactor never gets notified about reacting to their own message.
--   * reference_id holds the CONVERSATION id and reference_type =
--     'conversation' so tapping the notification opens the chat (the
--     in-app router deep-links reference_type='conversation' by id).
--   * De-dupe window: skip if a 'reaction' notification for this same
--     recipient + this same conversation already landed in the last 60s.
--     That stops toggle/multi-emoji spam and gently batches a burst of
--     reactions into one push (WhatsApp-style), at the minor cost of
--     collapsing reactions to two different messages within the same minute.
--   * The reaction emoji is taken straight from NEW.emoji (already valid
--     UTF-8 in the DB). All literal text we write here is ASCII only, so
--     nothing can corrupt to "??" in transit (see patch_115).
-- =====================================================================

CREATE OR REPLACE FUNCTION public.notify_on_message_reaction()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  author_id        UUID;
  convo_id         BIGINT;
  reactor_name     TEXT;
BEGIN
  -- Resolve the reacted message's author + conversation.
  SELECT m.sender_id, m.conversation_id
    INTO author_id, convo_id
  FROM public.messages m
  WHERE m.id = NEW.message_id;

  -- No such message, or reacting to your own message: nothing to do.
  IF author_id IS NULL OR author_id = NEW.user_id THEN
    RETURN NEW;
  END IF;

  -- De-dupe: at most one reaction notification per (recipient, conversation)
  -- per 60 seconds, so toggling a reaction or firing several emojis at once
  -- collapses into a single push instead of spamming.
  IF EXISTS (
    SELECT 1 FROM public.notifications n
    WHERE n.user_id = author_id
      AND n.type = 'reaction'
      AND n.reference_id = convo_id::text
      AND n.created_at > now() - interval '60 seconds'
  ) THEN
    RETURN NEW;
  END IF;

  -- Reactor's display name (ASCII fallback).
  SELECT COALESCE(NULLIF(TRIM(p.full_name), ''), 'Someone')
    INTO reactor_name
  FROM public.profiles p
  WHERE p.id = NEW.user_id;

  IF reactor_name IS NULL THEN
    reactor_name := 'Someone';
  END IF;

  INSERT INTO public.notifications
    (user_id, title, body, type, reference_id, reference_type)
  VALUES (
    author_id,
    reactor_name || ' reacted to your message',
    NEW.emoji,
    'reaction',
    convo_id::text,
    'conversation'
  );

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_notify_on_message_reaction ON public.message_reactions;

CREATE TRIGGER trg_notify_on_message_reaction
AFTER INSERT ON public.message_reactions
FOR EACH ROW
EXECUTE FUNCTION public.notify_on_message_reaction();
