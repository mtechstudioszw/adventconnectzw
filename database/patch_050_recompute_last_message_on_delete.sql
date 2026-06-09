-- patch_050: keep conversations.last_message in sync on message delete
-- ---------------------------------------------------------------------
-- Bug: deleting the most-recent message removed it from the chat but
-- left its text as the conversation's preview in the inbox ("I delete a
-- message and it still shows outside the chat"). sendMessage/sendVoiceNote
-- write conversations.last_message on INSERT, but deleteMessage only
-- removed the row — nothing recomputed the preview.
--
-- This AFTER DELETE trigger recomputes last_message / last_message_at
-- from the newest surviving message (NULL preview when none remain).
-- SECURITY DEFINER so it runs regardless of who deleted the row.
-- content already carries a human label for non-text messages
-- (voice notes store '🎙️ Voice note'), so no special-casing is needed.

CREATE OR REPLACE FUNCTION public.recompute_conversation_last_message()
RETURNS TRIGGER AS $$
DECLARE
  v_content TEXT;
  v_at      TIMESTAMPTZ;
BEGIN
  SELECT m.content, m.created_at
    INTO v_content, v_at
    FROM public.messages m
   WHERE m.conversation_id = OLD.conversation_id
   ORDER BY m.created_at DESC
   LIMIT 1;

  UPDATE public.conversations
     SET last_message    = v_content,                  -- NULL when none remain
         last_message_at = COALESCE(v_at, last_message_at)
   WHERE id = OLD.conversation_id;

  RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS messages_after_delete_recompute ON public.messages;
CREATE TRIGGER messages_after_delete_recompute
  AFTER DELETE ON public.messages
  FOR EACH ROW
  EXECUTE FUNCTION public.recompute_conversation_last_message();
