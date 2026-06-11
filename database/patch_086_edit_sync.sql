-- =====================================================================
--  PATCH 086 — sync the inbox preview when a message is edited
--
--  Editing a message updated messages.content (and the chat bubble shows
--  "edited"), but the conversation's last_message preview was only set on
--  INSERT — so the chat list kept showing the OLD text until reopened.
--  This updates conversations.last_message when the EDITED message is the
--  conversation's last one, so the preview refreshes everywhere live.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.update_conversation_on_edit()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.message_type <> 'system'
     AND COALESCE(NEW.is_deleted, FALSE) = FALSE THEN
    UPDATE public.conversations
       SET last_message = NEW.content
     WHERE id = NEW.conversation_id
       AND last_message_at = NEW.created_at; -- only if it's the last msg
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_update_conversation_on_edit ON public.messages;
CREATE TRIGGER trg_update_conversation_on_edit
  AFTER UPDATE ON public.messages
  FOR EACH ROW
  WHEN (OLD.content IS DISTINCT FROM NEW.content)
  EXECUTE FUNCTION public.update_conversation_on_edit();
