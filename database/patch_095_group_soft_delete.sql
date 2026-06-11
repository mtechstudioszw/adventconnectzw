-- =====================================================================
--  PATCH 095 — admin "delete group" = soft delete (notify + read-only)
--
--  Instead of hard-deleting everyone's copy, mark the conversation
--  deleted_at, post a system message, and notify members. The group
--  stays in everyone's list READ-ONLY (a BEFORE INSERT trigger blocks new
--  non-system messages) until each member removes it (delete_group_conversation).
-- =====================================================================

ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION public.delete_group(p_conversation BIGINT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_actor TEXT;
BEGIN
  IF NOT public.is_conversation_admin(p_conversation) THEN
    RAISE EXCEPTION 'Only group admins can delete the group.';
  END IF;
  SELECT COALESCE(NULLIF(btrim(full_name), ''), 'An admin') INTO v_actor
    FROM public.profiles WHERE id = auth.uid();
  UPDATE public.conversations SET deleted_at = now()
   WHERE id = p_conversation AND is_group = TRUE;
  PERFORM public._group_system_message(p_conversation, auth.uid(),
    v_actor || ' deleted this group');
  INSERT INTO public.notifications (
    user_id, title, body, type, reference_id, reference_type)
  SELECT cm.user_id, 'Group deleted',
         v_actor || ' deleted the group',
         'message', p_conversation::text, 'conversation'
    FROM public.conversation_members cm
   WHERE cm.conversation_id = p_conversation
     AND cm.user_id <> auth.uid() AND cm.left_at IS NULL;
END;
$$;

-- Read-only enforcement: no new (non-system) messages in a deleted group.
CREATE OR REPLACE FUNCTION public.block_insert_into_deleted()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.message_type <> 'system' AND EXISTS (
    SELECT 1 FROM public.conversations
     WHERE id = NEW.conversation_id AND deleted_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'This group has been deleted.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_block_insert_into_deleted ON public.messages;
CREATE TRIGGER trg_block_insert_into_deleted
  BEFORE INSERT ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.block_insert_into_deleted();
