-- =====================================================================
--  PATCH 110 — inbox preview reliably shows "This message was deleted"
--  after delete-for-everyone (incl. photos / voice notes)
--
--  patch_100 only fired its trigger WHEN (old.content <> new.content). A
--  photo / voice message already has content = '' , so soft-deleting it
--  (content stays '') never fired the trigger and the inbox kept showing
--  "📷 Photo" / "🎙️ Voice note" — the tester report: "outside the chat the
--  message you deleted for everyone still appears as been sent".
--
--  Fix:
--   * also fire when is_deleted flips (covers media + any content-less row);
--   * decide the newest-message match on messages.created_at via NOT EXISTS
--     instead of the brittle last_message_at = created_at equality;
--   * never blank the preview on a non-delete content-less update (media
--     upload finalisation) — only a real text edit replaces the text.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.update_conversation_on_edit()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_preview text;
BEGIN
  IF NEW.message_type = 'system' THEN
    RETURN NEW;
  END IF;
  -- Only touch the preview when NEW is the conversation's newest message —
  -- editing/deleting an OLDER message must not overwrite the inbox preview.
  IF EXISTS (SELECT 1 FROM public.messages m
              WHERE m.conversation_id = NEW.conversation_id
                AND m.created_at > NEW.created_at) THEN
    RETURN NEW;
  END IF;
  IF COALESCE(NEW.is_deleted, FALSE) THEN
    v_preview := 'This message was deleted';
  ELSIF NEW.content IS NOT NULL AND NEW.content <> '' THEN
    v_preview := NEW.content;          -- a genuine text edit
  ELSE
    RETURN NEW;                        -- media / empty update: leave preview
  END IF;
  UPDATE public.conversations
     SET last_message = v_preview
   WHERE id = NEW.conversation_id;
  RETURN NEW;
END;
$$;

-- Fire on a content change OR an is_deleted flip (the latter is what a
-- photo/voice delete-for-everyone produces).
DROP TRIGGER IF EXISTS trg_update_conversation_on_edit ON public.messages;
CREATE TRIGGER trg_update_conversation_on_edit
  AFTER UPDATE ON public.messages
  FOR EACH ROW
  WHEN (old.content IS DISTINCT FROM new.content
        OR old.is_deleted IS DISTINCT FROM new.is_deleted)
  EXECUTE FUNCTION public.update_conversation_on_edit();
