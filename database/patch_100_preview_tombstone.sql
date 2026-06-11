-- =====================================================================
--  PATCH 100 — inbox preview matches the chat when the last msg is
--  edited OR deleted-for-everyone
--
--  update_conversation_on_edit skipped soft-deleted rows, so deleting the
--  last message for everyone left the OLD text in the inbox while the chat
--  showed "This message was deleted" (the preview "lied"). Now it sets the
--  tombstone text for a soft-delete and the new text for an edit.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.update_conversation_on_edit()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.message_type <> 'system' THEN
    UPDATE public.conversations
       SET last_message = CASE
             WHEN COALESCE(NEW.is_deleted, FALSE)
               THEN 'This message was deleted'
             ELSE NEW.content END
     WHERE id = NEW.conversation_id
       AND last_message_at = NEW.created_at; -- only if it's the last msg
  END IF;
  RETURN NEW;
END;
$$;
