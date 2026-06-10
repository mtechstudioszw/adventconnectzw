-- =====================================================================
--  PATCH 079 — WhatsApp-style group leave / delete
--
--  Before: leave_group DELETED the membership row, so the group vanished
--  instantly and "delete conversation" had nothing coherent to do (stale
--  preview bug). Now:
--   * leave_group marks left_at (keeps the row) + posts a "left" system
--     message → the group stays in your list READ-ONLY.
--   * a left member can't POST (insert needs ACTIVE membership) but can
--     still SELECT (read history).
--   * delete_group_conversation removes your row → the group disappears
--     from your list forever (only allowed once you've left).
-- =====================================================================

ALTER TABLE public.conversation_members
  ADD COLUMN IF NOT EXISTS left_at TIMESTAMPTZ;

-- Still a member AND hasn't left — used to gate posting.
CREATE OR REPLACE FUNCTION public.is_active_conversation_member(p_conversation BIGINT)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.conversation_members m
     WHERE m.conversation_id = p_conversation
       AND m.user_id = auth.uid()
       AND m.left_at IS NULL
  );
$$;
GRANT EXECUTE ON FUNCTION public.is_active_conversation_member(BIGINT) TO authenticated;

-- Leaving marks left_at (keeps the row) instead of deleting.
CREATE OR REPLACE FUNCTION public.leave_group(p_conversation BIGINT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_actor TEXT;
BEGIN
  SELECT COALESCE(NULLIF(btrim(full_name), ''), 'A member') INTO v_actor
    FROM public.profiles WHERE id = auth.uid();
  PERFORM public._group_system_message(p_conversation, auth.uid(),
    v_actor || ' left');
  UPDATE public.conversation_members SET left_at = now()
   WHERE conversation_id = p_conversation AND user_id = auth.uid()
     AND left_at IS NULL;
END;
$$;

-- Delete the group conversation FOR ME (after leaving) — removes my row
-- so it disappears from my list.
CREATE OR REPLACE FUNCTION public.delete_group_conversation(p_conversation BIGINT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  DELETE FROM public.conversation_members
   WHERE conversation_id = p_conversation AND user_id = auth.uid();
END;
$$;
GRANT EXECUTE ON FUNCTION public.delete_group_conversation(BIGINT) TO authenticated;

-- Posting now requires ACTIVE membership (left members can read, not post).
-- Recreated verbatim from the live policy, swapping is_conversation_member
-- → is_active_conversation_member.
DROP POLICY IF EXISTS messages_insert_sender ON public.messages;
CREATE POLICY messages_insert_sender ON public.messages
  FOR INSERT
  WITH CHECK (
    (auth.uid() = sender_id) AND user_is_active() AND (
      (EXISTS (
        SELECT 1 FROM conversations c
         WHERE c.id = messages.conversation_id
           AND (auth.uid() = c.participant_a_id OR auth.uid() = c.participant_b_id)
      ))
      OR public.is_active_conversation_member(conversation_id)
    )
  );
